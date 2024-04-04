library(raster)

filename<-"Z:/Informatics/S031/S0311920/croz1920/UAV/orthomosaics/croz/191202/croz_20191202.tif"
r<-raster(filename)
SpRef<-crs(r)
SpRef
