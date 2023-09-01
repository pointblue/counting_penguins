# fix tile coordinates from the tiler script, which was providing incorrect coordinates due
# to working from lower left corner instead of upper left...
# 5/31/2023
# updated 8/28/2023 to work with penguin data instead

library(terra)
library(tidyverse)
library(sf)

setwd("Z:/informatics/s031/analyses/counting_penguins/")
of <- r"(Y:\PenguinCounting\croz_20191202\croz_20191202.tif)"
#note that this relied on mapping s3:deju-penguinscience as Y (used TNT drive for that)
#otherwise would need to download the ortho 

ortho <-
  terra::rast(of)
pixW <- xres(ortho)
pixH <- yres(ortho)
# 1.59296 for pixW for croz_20191202
# 1.59385 for pixH for croz_20191202

grt <- ("predict/2019/croz_20191202/tiles/croz_20191202_tilesGeorefTable.csv")

tile_tab <-
  read_csv(grt, 
           col_types = c("c","n","n","n","n"))

##
tile_corners <-
  tile_tab %>% 
  mutate(lat = yFromRow(ortho,pixelY),
         lon = xFromCol(ortho,pixelX))

# plot to check alignment
image(ortho)
points(tile_corners$lon, tile_corners$lat)

write_csv(tile_corners, "predict/2019/croz_20191202/tiles/croz_20191202_tilesGeorefTable_v2.csv")

cor(tile_tab$pixelX, tile_corners$lon)
