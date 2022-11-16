# TODO: Add comment
# 
# Author: lsalas
###############################################################################

libs<-c("ggplot2","plyr")
lapply(libs, require, character.only = TRUE)

basedir<-"C:/Users/lsalas/Downloads/croz20191202_preds/"

## SO WE ARE CLEAR:
# a snap is a prediction found within a set snapping distance to a known penguin
# a match is a prediction that is a snap and is determined to be the only or the best snap to a known penguin

## LOGIC:
# We want to match predictions to known penguins first in descending order of probability
# So for each tile, we start sorting the predictions in descending order of probability
# We loop while there are predictions to match and unassigned known penguins
# 	We try to snap the prediction to a known penguin
#		There are snaps:
#			Take the closest one, the prediction is a TP - save: penguinID, prob, validID, distance, match=TP; remove validID from table of knowns
#		No snaps:
#			The prediction is a FP - save: penguinID, prob, validID=NA, distance=NA, match=FP
#	No more known penguins to snap to
#		All remaining predictions are FP - save: 
#	No more predictions but still some known penguins
#		The remaining known penguins are FN - save: penguinID=NA, prob=1, validID, distance=NA, match=FN

## Validation functions

## USE the box to see if pred falls within.
## Function to snap a prediction to one or more known penguins
# pID is the ID of the penguin prediction we are tryng to snap
# prob is the probability of the prediction
# pcoords is the x.y vector of coordinates of that prediction
# validtable is the (ever shrinking) table of known, yet to be snapped penguins in the same tile as pID
# Return: the top snap as a match or no match as a data.frame:
#			penguinID, prob, validID, distance, match
findSnaps<-function(pID,prob,pcoords,validtiletable){
	# ...if there are records in validtiletable
	if(nrow(validtiletable)>0){
		# Find the snaps, sort by distance, take the closest if any found
		vttmf<-subset(validtiletable,(boxT>=pcoords[2]) & (boxB<=pcoords[2]) & (boxR>=pcoords[1]) & (boxL<=pcoords[1]))
		if(nrow(vttmf)>0){
			#take the closest penguin to the prediction
			vttmf$dist<-as.numeric(sapply(1:nrow(vttmf),function(rr,vttmf,pcoords){
								vx<-vttmf[rr,"tilx"];vy<-vttmf[rr,"tily"]
								distv<-sqrt(((pcoords[1]-vx)^2)+((pcoords[2]-vy)^2))
								return(distv)
							},vttmf=vttmf,pcoords=pcoords))
			vttmf<-vttmf[order(vttmf$dist),]
			sdf<-data.frame(penguinID=pID, prob=prob, validID=vttmf[1,"validID"], distance=vttmf[1,"dist"], match="TP")
		}else{
			#No detection within the box
			sdf<-data.frame(penguinID=pID, prob=prob, validID=NA, distance=NA, match="FP")
		}
		
	}else{ #no more valids to snap to
		sdf<-data.frame(penguinID=pID, prob=prob, validID=NA, distance=NA, match="FP")
	}
	
	return(sdf)
}

## Function to loop through all predictions in a tile and try to match them
# predsttable is the table with predictions
# validttable is the table of known penguin presences
# Return: a data.frame with match results
matchPredictions<-function(predsttable, validttable){
	
	snapsdf<-data.frame()
	
	nvr<-nrow(subset(validttable,label!="no_ADPE"))
	#If no predictions to the tile...(possibly all FN)
	if(nrow(predsttable)==0){
		
		#If there are validation records... definitively these are FN
		if(nvr>0){
			fnrecs<-data.frame(penguinID=rep(NA,nvr), prob=rep(1,nvr), validID=validttable$validID, distance=rep(NA,nvr), match="FN")
			snapsdf<-fnrecs
		}
		
	}else{
		# There are predictions, but what if no penguins found by observers?
		if(nvr==0){
			# No penguins in the tile, all predictions are FP
			fprecs<-data.frame(penguinID=predsttable$penguinID, prob=predsttable$probDet, validID=NA, distance=NA, match="FP")
			snapsdf<-fprecs
		}else{
			#we have both penguins and predictions, so...
			#sort preds by prob descending
			predsttable<-predsttable[order(predsttable$probDet, decreasing=T),]
			
			#loop through each to find snaps with findSnaps
			for(pID in predsttable$penguinID){
				ptt<-subset(predsttable,penguinID==pID)
				prob<-ptt$probDet
				pcx<-ptt$tilx;pcy<-ptt$tily
				
				#snap it
				snapt<-findSnaps(pID=pID,prob=prob,pcoords=c(pcx,pcy),validtiletable=validttable)
				
				#take result and add to tally
				snapsdf<-rbind(snapsdf,snapt)
				
				#update the validttable as needed
				snapID<-snapt$validID
				if(!is.na(snapID)){
					validttable<-subset(validttable, validID != snapID)
				}
				
				#if no more valids in validttable, let findSnaps handle it - set all remaining preds to FP
				
			}
			
			#if there are still valids, all these are FN - need to set prob to 1 so when penalizing we always have them there
			unvr<-nrow(validttable)
			if(unvr>0){
				fnrecs<-data.frame(penguinID=rep(NA,unvr), prob=rep(1,unvr), validID=validttable$validID, distance=rep(NA,unvr), match="FN")
				#add to tally
				snapsdf<-rbind(snapsdf,fnrecs)
			}
		}
	}
	
	return(snapsdf)
}


## load the data - CAREFUL filtering the labels to match the model
# label "ADPE_a_stand" = model "adult_stand_s5_best"
# label "ADPE_a" =  model "adult_s2_best"
preddf<-read.csv(paste0(basedir,"croz_20191202_preds_adult_stand_s5_best.csv"))
valdf<-read.csv(paste0(basedir,"croz_20191202_validation_labels.csv"))
valdf<-subset(valdf,label %in% c("no_ADPE","ADPE_a_stand"))

## Need to add a validID to the validations table...
## NEED to use pixels, no rels - in both preds and vals
tiledims<-c(512,256)
valdf$tilx<-round(valdf$x*tiledims[1])
valdf$tily<-round(valdf$y*tiledims[2])
# Using a Manhattan filter before the Euclidian, with the box drawn by volunteers
# And the Euclidian only to choose the presence nearest to the prediction if there are many within the Manhattan filter
valdf$boxL<-round((valdf$x-valdf$width)*tiledims[1])
valdf$boxR<-round((valdf$x+valdf$width)*tiledims[1])
valdf$boxT<-round((valdf$y+valdf$height)*tiledims[2])
valdf$boxB<-round((valdf$y-valdf$height)*tiledims[2])
preddf$tilx<-round(preddf$relX*tiledims[1])
preddf$tily<-round(preddf$relY*tiledims[2])

tiles<-unique(valdf$tileName)
# Filtering out bad tiles
badValTiles<-c("croz_20191202_151_407", "croz_20191202_115_347", "croz_20191202_126_404", "croz_20191202_131_396", "croz_20191202_283_506", "croz_20191202_56_292")
tiles<-tiles[which(!tiles %in% badValTiles)]

validationsdf<-ldply(tiles,function(tt,predstable, validtable){
			predsttable<-subset(predstable,grepl(tt,tilename))
			vttable<-subset(validtable,tileName==tt)
			
			#Add a unique ID to each validation record, so we can have referential integrity to each prediction
			validttable<-ldply(unique(vttable$tileName),function(tnam,vttable){
						vtt<-subset(vttable,tileName==tnam)
						vtt$validID<-paste0(tnam,"::",1:nrow(vtt))
						return(vtt)
					},vttable=vttable)
			
			rdf<-matchPredictions(predsttable=predsttable,validttable=validttable)
			if(nrow(rdf)>0){rdf$tilename<-tt}
			return(rdf)
		},predstable=preddf, validtable=valdf)

## There are 9,976 predictions in the 1,000 tiles inspected
nrow(validationsdf) #=20,947 assessments
nrow(subset(valdf,label!="no_ADPE")) #=10,942 penguins detected by volunteers
nrow(valdf)-nrow(subset(valdf,label=="no_ADPE")) #460 records with no penguins, ergo 460 tiles inspected with no penguins
