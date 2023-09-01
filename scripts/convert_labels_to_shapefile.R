library(sf)
library(rgdal)
library(tidyverse)
library(terra)

# read in ortho
of <-
  r"(predict\2019\croz_20191202\croz_20191202.tif)"

ortho <-
  terra::rast(of)
pixW <- xres(ortho)
pixH <- yres(ortho)

ext(ortho)
img_width = 512
img_height = 256

# Table with prediction labels
df <-
  read_csv(r"(predict\2019\croz_20191202\adult_s2_best\all_nests_with_dupe_indicators_v7.csv)") %>%
  mutate(width_px = box_width * img_width,
         height_px = box_height * img_height) %>% 
  mutate(x_center_px = box_center_w*img_width,
         y_center_px = box_center_h*img_height) %>%
  mutate(
    # box pixel coordinates relative to tile pixels (upper left)
    tile_px_left = x_center_px - (width_px / 2),
    tile_px_right = x_center_px + (width_px / 2),
    tile_px_top = y_center_px + (height_px / 2),
    tile_px_bottom = y_center_px - (height_px / 2),
    # pixelX = upper left tile corner in ortho pixels
   left = pixelX + tile_px_left,
   right = pixelX + tile_px_right,
   top = pixelY + tile_px_top,
   bottom = pixelY + tile_px_bottom
  ) %>% 
  # compute geo coordinates
  mutate(
    left_geo =  xFromCol(ortho, left),
    right_geo = xFromCol(ortho, right),
    top_geo = yFromRow(ortho, top),
    bottom_geo = yFromRow(ortho, bottom))

# mutate(lat = yFromRow(ortho, pixelY),
#        lon = xFromCol(ortho, pixelX))

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
  SpatialPolygonsDataFrame(sp_polygons, data = df[,c(1:21)])


# Convert the SpatialPolygonsDataFrame to an sf object
sf_object <- st_as_sf(sp_polygons_df)


# Write the sf object to a shapefile
st_write(
  sf_object,
  "predict/2019/croz_20191202/adult_s2_best/croz_20191202_combined_predictions.shp",
  append = FALSE
)
