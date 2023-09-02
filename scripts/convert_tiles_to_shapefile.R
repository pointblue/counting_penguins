library(sf)
library(rgdal)
library(tidyverse)
library(terra)

# read in ortho
of <-
  r"(predict/2019/royd_20191204/royd_20191204.tif)"
#note that this relied on mapping s3:deju-penguinscience as Y (used TNT drive for that)
#otherwise would need to download the ortho

ortho <-
  terra::rast(of)
pixW <- xres(ortho)
pixH <- yres(ortho)

ext(ortho)
st_crs(ortho)
maxPix_y <-
  dim(ortho)[1]
maxPix_x <-
  dim(ortho)[2]

tiledat <-
  read_csv(r"(predict\2019\royd_20191204\tiles\royd_20191204_tilesGeorefTable.csv)") %>% 
  mutate(pixelX = pixelX+0.0000001, pixelY = pixelY + 0.0000001) %>% 
  mutate(geo_x = xFromCol(ortho,pixelX),
         geo_y = yFromRow(ortho,pixelY)
         )

write_csv(tiledat, r"(predict\2019\royd_20191204\tiles\royd_20191204_tilesGeorefTable_v2.csv)")

img_width = 512
img_height = 256

df <-
  tiledat %>% 
  mutate(
    # box pixel coordinates relative to tile pixels (upper left)
    left = pixelX,
    right = ifelse((pixelX+img_width) > maxPix_x, maxPix_x,(pixelX+img_width)),
    top = pixelY,
    bottom = ifelse((pixelY+img_height) > maxPix_y, maxPix_y,(pixelY+img_height))
    # # pixelX = upper left tile corner in ortho pixels
    # left = pixelX + tile_px_left,
    # right = pixelX + tile_px_right,
    # top = pixelY + tile_px_top,
    # bottom = pixelY + tile_px_bottom
  ) %>% 
  # compute geo coordinates
  mutate(
    left_geo =  xFromCol(ortho, left),
    right_geo = xFromCol(ortho, right),
    top_geo = yFromRow(ortho, top),
    bottom_geo = yFromRow(ortho, bottom))


# Create polygons
polygons_list <- lapply(1:nrow(df), function(i) {
  Polygon(cbind(
    c(
      df$left_geo[i],
      df$right_geo[i],
      df$right_geo[i],
      df$left_geo[i],
      df$left_geo[i]
    ),
    c(
      df$bottom_geo[i],
      df$bottom_geo[i],
      df$top_geo[i],
      df$top_geo[i],
      df$bottom_geo[i]
    )
  ))
})

# define projection
proj <- "+proj=lcc +datum=WGS84 +lat_1=-76.6666667 +lat_2=-79.3333333 +lon_0=169.3333333 +lat_0=-78.021171 +x_0=500000 +y_0=300000 +units=m +no_defs"

# Convert list of polygons to SpatialPolygons
sp_polygons <-
  SpatialPolygons(lapply(1:length(polygons_list), function(i) {
    Polygons(list(polygons_list[[i]]), ID = as.character(i))
  }), proj4string = CRS(proj))

sp_polygons_df <-
  SpatialPolygonsDataFrame(sp_polygons, data = df[,c(1:3)])

# Convert the SpatialPolygonsDataFrame to an sf object
sf_object <- st_as_sf(sp_polygons_df)

# Write the sf object to a shapefile
st_write(
  sf_object,
  "predict/2019/royd_20191204/adult_s2_best/royd_20191204_tiles.shp",
  append = FALSE
)

