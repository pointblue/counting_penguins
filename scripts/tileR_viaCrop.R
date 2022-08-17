# TODO: Add comment
# 
# Author: lsalas
###############################################################################


libs<-c("plyr","rgdal","raster","RStoolbox","gdalUtils","aws.s3")  #"doParallel","foreach"
suppressPackageStartupMessages(lapply(libs, require, character.only = TRUE))

r<-stack("/home/ubuntu/orthos/croz_20191202.tif")
tdnlst<-strsplit("/home/ubuntu/orthos/croz_20191202.tif","/")
tdn<-tdnlst[[1]][length(tdnlst[[1]])];tdn<-substr(tdn,1,nchar(tdn)-4)
savepth<-paste0("/home/ubuntu/tiles/",tdn,"_tiles/")
if(!dir.exists(savepth)){ dir.create(savepth) }
bucketdir<-"1920_UAV_survey/orthomosaics/croz/191202/croz_20191202_tiles/"

## PASS KEYS HERE!!!
keydf<-read.csv("/home/ubuntu/key/AnnieKeys.csv",stringsAsFactors=F,header=F)
Sys.setenv(AWS_ACCESS_KEY_ID=keydf[1,2], AWS_SECRET_ACCESS_KEY=keydf[2,2],"AWS_DEFAULT_REGION" = "us-west-2")

#cl <- makeCluster(8)
#registerDoParallel(cl)

er<-extent(r)
tzpx<-512	# Tile size in pixels on x
tzpy<-256	# on y
length_x<-er[2]-er[1]
length_y<-er[2]-er[1]
rezx<-length_x/ncol(r) #resolution in the projection's units (meters)
rezy<-length_y/nrow(r)
tzx<-8.27  #tzpx*rezx
tzy<-4.13  #tzpy*rezy - if not flooring, I get 259 pixels

# Making the overlap be 20 pixels
seqlen_x<-tzx-(rezx*20)
seqlen_y<-tzy-(rezy*20)
#Now, overlapping by 20% on the tile positions
ne<-seq(er[1],er[2],by=seqlen_x);nn<-seq(er[3],er[4],by=seqlen_y)

## Make the table of tiles and their extents 
tm<-Sys.time()
tilesdf<-ldply(.data=ne,.fun=function(tx,tzx,tzy,ne,nn,r){
			txe<-tx+tzx
			londf<-ldply(nn,function(ty,tzy,tx,txe,ne,nn,r){   #can parallelize here .parallel=T but need snow and declare cores
						tye<-ty+tzy
						txnm<-sum(tx>ne); tynm<-sum(ty>nn)
						cnmt<-paste0("x",txnm,"_y",tynm)
						tdf<-data.frame(name=cnmt,xmin=tx,xmax=txe,ymin=ty,ymax=tye)	
						return(tdf)
					},tzy=tzy,tx=tx,txe=txe,ne=ne,nn=nn,r=r)
			return(londf)
		},tzx=tzx,tzy=tzy,ne=ne,nn=nn,rr)
nrow(tilesdf)==length(unique(tilesdf$name))
tilesmeta<-paste0(savepth,tdn,"_tileData.RData")
save(tilesdf,file=tilesmeta)
kk<-try(put_object(file=tilesmeta,object=paste0(bucketdir,tdn,"_tileData.RData"),bucket="pb-adelie"),silent=T)
if(inherits(kk,"try-error")){print(paste("Could not save metadata table into bucket"))}
Sys.time()-tm # less than 2 minutes if not tiling

## Cannot vectorize and parallelize because of lack of memory
## The filter works but generates no tiles for the first few hours
## No need to generate the geoTiffs - jpegs will do
## Consider generating the tiles on the fly:
## Make a table of cellId, lat-lon for each cell in the ortho raster
## Make tables of the 4 tiff layers, with cellID
## Read the extent of tiles in the table of tiles, subset by xy, retrive cell IDs, use cellIDs to retrieve values from the 4 tiff layers, construct the stack, plotRGB

tm<-Sys.time()
savestatus<-integer()
for(tx in ne){
	txe<-tx+tzx
	for(ty in nn){
		tye<-ty+tzy
		txnm<-sum(tx>ne); tynm<-sum(ty>nn)
		cnmt<-paste0("x",txnm,"_y",tynm)
		
		tcr<-try(crop(r,extent(c(tx,txe,ty,tye))),silent=TRUE); 
		if(!inherits(tcr,"try-error")){
			#if(!identical(tcr@data@min[1:3],tcr@data@max[1:3])){
			#writeRaster(tcr,filename=paste0(savepth,nmt,".tif"),format="GTiff",overwrite=TRUE)  NO NEED!
				filen<-paste0(savepth,cnmt,".jpg")
				jpeg(filename = filen,	width = 512, height = 256, units = "px", quality = 100)
					plotRGB(tcr)
				dev.off()
				savestatus<-c(savestatus,1)
				kk<-try(put_object(file=filen,object=paste0(bucketdir,cnmt,".jpg"),bucket="pb-adelie"),silent=T)
				if(inherits(kk,"try-error")){
					print(paste("Could not save",cnmt))
				}else{
					#delete the tile
					print(paste("Saved",cnmt))
					unlink(filen)
				}
			#}else{
			#	savestatus<-c(savestatus,2)
			#	print(paste("Not saving",cnmt))
			#}
		}else{
			savestatus<-c(savestatus,0)
		}
	}
}
Sys.time()-tm 

tilesdf$saveStatus<-savestatus
save(tilesdf,file=paste0(savepth,tdn,"_tileData.RData"))
kk<-try(put_object(file=tilesmeta,object=paste0(bucketdir,tdn,"_tileData.RData"),bucket="pb-adelie"),silent=T)
if(inherits(kk,"try-error")){print(paste("Could not save metadata table into bucket"))}




tm<-Sys.time()
for(tx in 0:ne){ #ne
	mnx<-(tx*tzx)+er[1]; mxx<-mnx+tzx
	for(ty in 0:nn){ #nn
		mny<-(ty*tzy)+er[3]; mxy<-mny+tzy
		nmx<-paste0("x",tx); nmy<-paste0("y",ty)
		nmt<-paste0(nmx,"_",nmy); nmts<-paste0(nmt,"S")
		
		tcr<-try(crop(r,extent(c(mnx,mxx,mny,mxy))),silent=TRUE); 
		tcrs<-try(crop(r,extent(c(mnsx,mxsx,mnsy,mxsy))),silent=TRUE)
		if(!inherits(tcr,"try-error")){
			#if(!identical(tcr@data@min[1:3],tcr@data@max[1:3])){
			#writeRaster(tcr,filename=paste0(savepth,nmt,".tif"),format="GTiff",overwrite=TRUE)
			jpeg(filename = paste0(savepth,nmt,".jpg"),	width = 512, height = 256, units = "px", quality = 100)
			plotRGB(tcr)
			dev.off()
			#}
		}
		if(!inherits(tcrs,"try-error")){
			#if(!identical(tcrs@data@min[1:3],tcrs@data@max[1:3])){
			#writeRaster(tcrs,filename=paste0(savepth,nmts,".tif"),format="GTiff",overwrite=TRUE)
			jpeg(filename = paste0(savepth,nmts,".jpg"),	width = 512, height = 256, units = "px", quality = 100)
			plotRGB(tcrs)
			dev.off()
			#}
		}
		
	}
}
Sys.time()-tm

