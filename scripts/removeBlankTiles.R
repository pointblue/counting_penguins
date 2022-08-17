# TODO: Add comment
# 
# Author: lsalas
###############################################################################


library(plyr); library(raster); libary(doParallel); library(foreach)

cl <- makeCluster(8)
registerDoParallel(cl)

orthoname<-"croz_20191202"
savepth<-paste0("/home/ubuntu/tiles/",orthoname,"_tiles/")
if(!dir.exists(savepth)){stop("Check ortho name - not found")}

## load the tiles table
load(file=paste0(savepth,orthoname,"_tileData.RData"))

## loop through each tile name
## Examine the jpeg: convert to df and see if min-max range is <5. If so, delete.
tilespath<-paste0("/home/ubuntu/tiles/",orthoname,"_tiles/")

keepTiles<-llply(tilesdf$name,.parallel=T,.fun=function(nn,tilespath){
			tilep<-paste0(tilespath,nn,".jpg")
			rr<-raster(tilep)
			rdf<-as.data.frame(rr)
			if((max(rdf[,1])-min(rdf[,1]))<10){
				return("")
			}else{
				return(nn)
			}
		},tilespath=tilespath)
tilesdf<-subset(tilesdf, name %in% keepTiles)

save(tilesdf,file=paste0(savepth,orthoname,"_tileData_filtered.RData"))

