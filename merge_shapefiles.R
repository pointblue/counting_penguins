# to merge shapefiles - for example South, Mid, and North Bird
# predictions

library(sf)
shapefile1 <- st_read("predict/2022/bird_mid_20221126_lcc169/counts/ADPE_20231024_adult_sit/GIS/all_labels.shp")
shapefile2 <- st_read("predict/2022/bird_north_20221126_lcc169/counts/ADPE_20231024_adult_sit/GIS/all_labels.shp")
shapefile3 <- st_read("predict/2022/bird_south_20221126/counts/ADPE_20231024_adult_sit/GIS/all_labels.shp")

columns_shapefile1 <- names(shapefile1)
columns_shapefile2 <- names(shapefile2)
columns_shapefile3 <- names(shapefile3)

extra_columns_in_3_vs_1 <- setdiff(columns_shapefile3, columns_shapefile1)
extra_columns_in_3_vs_2 <- setdiff(columns_shapefile3, columns_shapefile2)

# Combine and unique the lists in case the extra column is not in both
extra_columns_in_3 <- unique(c(extra_columns_in_3_vs_1, extra_columns_in_3_vs_2))

# Print the extra columns
print(extra_columns_in_3)

#drop extra column(s)
shapefile3 <- subset(shapefile3, select = -clstr_d)  
  
merged_shapefile <- rbind(shapefile1, shapefile2, shapefile3)

st_write(merged_shapefile, "data/bird_adpe_2022-11-26/predict/counts/ADPE_20231024_adult_sit/GIS/all_labels.shp", delete_layer = TRUE)
