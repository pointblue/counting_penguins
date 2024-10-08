# Process YOLO-formatted labels generated by count_[whatever].py
# Grant Aug 2023 to Jan 2024
# updated March 28, 2024 to reflect new directory structure

library(dplyr)
library(tidyr)
library(foreach)
library(doParallel)
library(readr)
library(stringr)
library(sf)
library(raster)
library(terra)
library(RANN)
library(data.table)
library(RSQLite)

# --------------------------------------------------------
# Provide details of the survey labels you are processing:
# These are used throughout the code, but should be the only
# Place you need to set them
# --------------------------------------------------------

season <- "2018"
survey <- "royd_adpe_2018-11-28_lcc169" # this is usally the prefix of the ortho file name
directory <- "royd_adpe_2018-11-28" # this should match the directory name where you put your Georeftable
ortho_name <- "royd_adpe_2018-11-28_lcc169"
ortho_file <- paste0("orthomosaics/",directory,"/",ortho_name,".tif") # Don't need this if
# it has been previously processed and an orthoinfo file exists (see below) - just to read the resolution and CRS
# note that if the ortho was not projected when the tiles were made, this code will not work because it is using distance
# get the correct threshold from the database if it has been calculated:
con <- dbConnect(SQLite(), dbname = "data/UAVSurveys.db")
query <- sprintf("SELECT Threshold FROM ModelPredictions WHERE OrthomosaicName = '%s.tif'", ortho_name)
th <- dbGetQuery(con, query)$Threshold
dbDisconnect(con)
# or specify threshold here instead:
# th <- 0.50 # the confidence threshold you will be using for this run; 0.5 is the usual
# starting point, but best determined by comparing stats (see thresholding code separately)

# Should not need to change this often:
model <- "ADPE_20231024_adult_sit"

# Below should not need to be modified:
georeftable <- paste0("data/",directory,"/predict/",ortho_name,"_tilesGeorefTable.csv")
orthoinfo <- paste0("data/",directory,"/predict/",ortho_name,"_OrthoInfo.csv")
labels_path <- paste0("data/",directory,"/predict/counts/",model,"/labels")
csv_path <- paste0("data/",directory,"/predict/counts/",model,"/csv")

# -----------------------------------------
# Combine labels files generated by predict
# you can skip this step if it has already been done
# -----------------------------------------

# Note that there is one folder for each model for each UAV survey 
# Get a list of all label file names in the labels directory
label_files <- list.files(path = labels_path, pattern = "\\.txt$", full.names = TRUE)

# Function to process a label file and return its data frame
process_label_file <- function(file) {
  tile_name <- gsub("\\.txt$", "", basename(file))
  tile_name <- paste0(tile_name, ".jpg")
  
  labels <- fread(file, header = FALSE, sep = " ")
  
  # Create a data.table
  file_data <- data.table(
    tileName = rep(tile_name, nrow(labels)),
    label = labels$V1,
    box_center_w = labels$V2,
    box_center_h = labels$V3,
    box_width = labels$V4,
    box_height = labels$V5,
    confidence = labels$V6
  )
  
  return(file_data)
}

# Register the parallel backend in order to speed this up (takes a long time otherwise)
# cl <- makeCluster(detectCores() - 1)  # Leaving one core free for other tasks
cl <- makeCluster(detectCores()/4)  # or use 25% of what's available?

registerDoParallel(cl)

# Process label files in parallel
combined_data <- foreach(file=label_files, .combine='rbind', .packages=c("data.table")) %dopar% {
  process_label_file(file)
}

# Stop the parallel backend
stopCluster(cl)

# Write the combined data to a CSV file
fwrite(combined_data, file = paste0(csv_path, "/combined_predictions.csv"), sep = ",", quote = FALSE)

# --------------------------------------------------------------
# Start processing the combined labels file
# You can start here if combined_predictions has already been created
# --------------------------------------------------------------

df <- fread(paste0(csv_path,"/combined_predictions.csv"))

# or just:
# df <- combined_data
# df <- read.csv(r"(Z:\Informatics\S031\analyses\RI_penguin_count_UAV\data\bird_adpe_2022-11-26\predict\counts\ADPE_20231024_adult_sit\csv\bird_north_adpe_2022-11-26_lcc169\combined_predictions.csv)")

# subsetting here can speed things up along the way, but remember that you did it!
df <- subset(df, confidence >= th) # pick a confidence number that makes sense for your survey
# note that when you de-duplicate below you will be setting this number again - and obviously it
# won't work as intended if you set it to a lower number down there!
# subset more for special cases, such as the various Cape Birds (north, mid, south):
# df <- df[grepl("north", df$tileName, ignore.case = TRUE), ]
# df <- df[grepl("mid", df$tileName, ignore.case = TRUE), ]
# df <- df[grepl("south", df$tileName, ignore.case = TRUE), ]

# specify tile dimensions: 
df$img_width <- (512)
df$img_height <- (256)

#------------------------------------
# Determine which tiles are adjacent
# This speeds up de-duplication below
#------------------------------------

# Function to extract col and row information
extract_info_vectorized <- function(img_files, survey) {
  pattern <- paste0(survey, "_(\\d+)_(\\d+)\\.jpg") # this assumes file naming convention
  # of surveyname_column_row.jpg 
  matches <- str_match(img_files, pattern)
  
  cols <- as.integer(matches[,2])
  rows <- as.integer(matches[,3])
  
  list(col = cols, row = rows)
}

# Vectorized extraction
info <- extract_info_vectorized(df$tileName, survey)

# Create new columns for the adjacent bottom, top, left, and right tiles
df$bottom_tile <- ifelse(!is.na(info$col), paste0(survey, "_", info$col, "_", info$row + 1, ".jpg"), NA)
df$top_tile    <- ifelse(!is.na(info$col), paste0(survey, "_", info$col, "_", info$row - 1, ".jpg"), NA)
df$left_tile   <- ifelse(!is.na(info$row), paste0(survey, "_", info$col - 1, "_", info$row, ".jpg"), NA)
df$right_tile  <- ifelse(!is.na(info$row), paste0(survey, "_", info$col + 1, "_", info$row, ".jpg"), NA)

# ---------------------------------------
# Add x and y coordinates to every label
# ---------------------------------------

# Read in the georeference info - this needs to be projected in order for the de-duplication
# to work correctly
# georeftable <- "data/bird_adpe_2021-12-02/predict/bird_mid_south_adpe_2021-12-03_lcc169_tilesGeorefTable.csv"

grt <- fread(georeftable)

# write_csv(grt, georeftable)
# Merge the dataframes
df <- left_join(df, grt, by="tileName")

# Get the crs and resolution of the ortho 
# it might exist in a csv if you wrote it there previously:
# orthoinfo <- "data/bird_adpe_2021-12-02/predict/bird_mid_south_adpe_2021-12-03_lcc169_OrthoInfo.csv"

if (file.exists(orthoinfo)) {
  # Read the CSV file into a data frame
  ortho_info_df <- read.csv(orthoinfo)
  # Extract the variables
  crs_r <- CRS(ortho_info_df$crs_r)
  xres <- as.numeric(ortho_info_df$xres)
  yres <- as.numeric(ortho_info_df$yres)
} else { # have to get the info out of the raster
  r <- rast(ortho_file)
  # Get the CRS - this needs to be projected: lcc169 for Ross Island
  crs_r <- crs(r)
  # Get the x and y resolution from the ortho, if you have it and it is projected
  resolution <- res(r)
  xres <- resolution[1]
  yres <- resolution[2]
  # Write the ortho info for easier retrieval next time:
  ortho_info_df <- data.frame(crs_r = as.character(crs_r), xres = xres, yres = yres)
  write.csv(ortho_info_df, orthoinfo, row.names = FALSE)
  
}

# you can also do this without downloading the orthos from S3 - see:
# get_S3_ortho_metadata.R

# Print the resolution just to make sure it is as expected (should be < 2cm)
print(paste("X resolution: ", xres))
print(paste("Y resolution: ", yres))

# Create new columns for geographic coordinates
# the values will depend on the pixel resolution of the orthos
# if you are dealing with old tiles you need to do this first:
# df <- df %>% rename(northing = northng)

df$geo_x <- df$easting + (df$box_center_w*512*xres)
df$geo_y <- df$northing - (df$box_center_h*256*yres)

# add box area so you can filter out weird-sized labels below
df$box_area <- (df$box_width * xres * df$img_width)  * (df$box_height * yres * df$img_height)

mean(df$box_area)
hist(df$box_area)

# keep a backup from this point so you can iterate
df_backup <- df

# subset as appropriate - everything below will need some iteration
# as you learn the properties of this particular survey imagery
df <- df_backup 

# you shouldn't need to do this, but if you do, make sure
# there isn't something wrong with your georeftable:
# df <- subset(df, !is.na(northing))

# -------------------------------

# -----------------------------------------------------------
# Parallelized duplicate remover 
# (12 minutes to process 319,244 labels on an older laptop, using 12 cpu's) 
# but you lose some duplicates along the edges of the batches
# this also tries to eliminate penguins that are not in sub-colonies
# using two approaches - if only one penguin in a group of nine tiles
# that gets marked as "solo" and if no penguins within a certain
# distance (default is 3m) then also gets flagged "d3m = 1"
# -----------------------------------------------------------

thn <- as.character(th*100) # for naming files at end so you can tell what th was applied
dr <- 0.5 # the radius (m) that we assume a legit separate individual can be counted
# i.e., if label is within dr (dupe-radius) it is a duplicate label
# get rid of any boxes that are too small to be real sitting penguins (roughly .30 x .40 = 0.12 square m)
# and apply the confidence threshold
df <- subset(df, box_area > 0.1 & box_area < 0.3 & confidence >= th)

# if you need to subset to something else:
# df <- df[grepl("south", df$tileName, ignore.case = TRUE), ]

setDT(df)  # Convert 'df' to data.table for efficiency in the processing below

# add start values for label, clustered, solo, d3m
df[, label_id := .I] # every label gets a unique, sequential ID
df[, clustered := FALSE] # all are assigned False for cluster - i.e., not duplicated
df[, cluster_id := label_id] # all cluster_id's start by matching label_id
df[, solo := FALSE] # for identifying solo nests
df[, d3m := 0] # for identifying nests with neighbors within 3m

# Register the parallel back end with however many cores you want to use
cn <- 8 # core number you want to use. More cores faster but more duplication along edges
registerDoParallel(cores = cn)

n <- nrow(df)
batches <- split(df, cut(seq(n), breaks = cn, labels = FALSE))

# batch_df <- df

process_batch <- function(batch_df) {
  # Proceed within the loop over each unique label
  for (current_label_id in unique(batch_df$label_id)) {
    # current_label_id = batch_df$label_id[2]
    # Get the label details for the current label
    current_label <- batch_df[label_id == current_label_id]
    tile <- current_label$tileName
    # print(tile)
    
    # count labels in the adjacent tiles
    nl_count <- batch_df[(tileName == tile | bottom_tile == tile | top_tile == tile |
                            left_tile == tile | right_tile == tile), .N]
    # if count = 1 (i.e. only one label in this and adjacent tiles
    # label as solo nest and move on (although a lot of these are simply shadows)
    if (nl_count == 1) {
      batch_df[label_id == current_label_id, `:=`(solo = TRUE)]
      next
    }
    
    # # If it gets here, there are labels (potential duplicates) in this or adjacent tiles
    # # But they might still be further than 3m away, in which case we might want to drop them
    # # Subset the data for the current tile and its adjacent tiles so that the 
    # # number of labels being checked for duplication is minimized - also only 
    # # labels have not already been assigned a new cluster_id (i.e., already 
    # # part of a set of duplicates)
    subset_df <- batch_df[((tileName == tile | bottom_tile == tile | top_tile == tile |
                              left_tile == tile | right_tile == tile)),
                          .(label_id, tileName, geo_x, geo_y, confidence)]
    
    # Check for whether there is another label within 3m that is not within 0.5m (dupes)
    # if so record distance
    # note that you want these neighbors to have relatively high confidence - see setting above
    nn_results_3m <- nn2(data.matrix(subset_df[, .(geo_x, geo_y)]),
                         query = data.matrix(current_label[, .(geo_x, geo_y)]),
                         searchtype = "radius",
                         radius = 3)
    
    # # find the neighbors that are more than dr but <= 3m away
    nn3m <- nn_results_3m$nn.dists[nn_results_3m$nn.dists <= 3 & nn_results_3m$nn.dists > dr]
    
    # # if there are any neighbors as specified above, record distance to nearest neighbor
    if (length(nn3m) > 0) {
      v_nn3m <- round(nn3m[1],2)
    } else {
      v_nn3m <- NA
    }
    
    batch_df[label_id == current_label_id, `:=`(d3m = v_nn3m)]
    
    # Duplicate tagging:
    # Find neighboring labels within 0.50m, including the label itself (these are 
    # considered duplicates; the one with the highest confidence will be selected
    # below)
    nn_results <- nn2(data.matrix(subset_df[, .(geo_x, geo_y)]),
                      query = data.matrix(current_label[, .(geo_x, geo_y)]),
                      searchtype = "radius",
                      radius = dr)
    
    valid_neighbor_indices <- nn_results$nn.idx[nn_results$nn.dists < dr]
    
    neighbor_label_ids <- subset_df$label_id[valid_neighbor_indices]
    
    # # Check for existing cluster IDs among neighbors
    existing_cluster_ids <- unique(batch_df[label_id %in% neighbor_label_ids, cluster_id])
    
    # # Assign the current label_id as the cluster_id for all neighbors found
    if (length(neighbor_label_ids) > 1) {
      # Use an existing cluster_id if available, otherwise use current_label_id
      chosen_cluster_id <- ifelse(length(existing_cluster_ids) > 0 && !is.na(existing_cluster_ids[1]),
                                  existing_cluster_ids[1],
                                  current_label_id)
      
      batch_df[label_id %in% neighbor_label_ids, `:=`(cluster_id = chosen_cluster_id, clustered = TRUE)]
    }
    
  }
  return(batch_df)
  
}

results <- foreach(batch = batches, .combine = rbind, .packages = c("data.table", "RANN")) %dopar% {
  processed_batch <- process_batch(batch)
}

stopImplicitCluster()

# Ensure that for each cluster_id, the row with the highest confidence is retained:
final_results <- results[order(-confidence), .SD[1], by = cluster_id]
duplicates <- df[!final_results, on = "label_id"]

# 000000000000000000000000000000000000000
# Write the results to csv and shapefiles
# 000000000000000000000000000000000000000

# write a csv with all results
write_csv(final_results, paste0("data/",directory,"/predict/counts/",model,"/csv/final_results_threshold",thn,".csv"))
                              
# Can start from here if already processed: 
# final_results <- read.csv(paste0("predict/",season,"/",directory,"/counts/",model,"/csv/final_results_threshold80.csv"))

# write_csv(final_results, "C:/gballard/S031/analyses/counting_penguins/predict/2023/bird_north_adpe_2023-11-30_lcc169/counts/ADPE_20231024_adult_sit/csv/final_results_threshold75.csv")

# write full shapefile
sf_obj <- st_as_sf(df, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj, paste0("data/",directory,"/predict/counts/",model,"/GIS/all_labels.shp"), append=FALSE)

# Make shapefile of de-duplicated results (without threshold, without mask)
sf_obj <- st_as_sf(final_results, coords = c("geo_x", "geo_y"), crs = crs_r)
# Write shapefile
st_write(sf_obj, paste0("data/",directory,"/predict/counts/",model,"/GIS/de_duplicated_labels_par",cn,".shp"), append=FALSE)

# write duplicates shapefile
sf_obj <- st_as_sf(duplicates, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj, paste0("data/",directory,"/predict/counts/",model,"/GIS/duplicate_labels_par",cn,".shp"), append=FALSE)
length(unique(final_results$cluster_id))

# apply the threshold 
# threshold_df <- df
threshold_df <- subset(final_results, confidence >= th)
nrow(threshold_df)

# make shapefile with threshold applied
sf_obj <- st_as_sf(threshold_df, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj, paste0("data/",directory,"/predict/counts/",model,"/GIS/threshold",thn,"_labels.shp"), append=FALSE)

# apply the solo and distance mask
# the solo part doesn't seem to help here - too restrictive!
# masked_df <- subset(final_results, confidence >= 0.75 & solo == FALSE & d3m > 0 & d3m <= 3)
masked_df <- subset(final_results, confidence >= th & d3m > 0 & d3m <= 3 & !solo) # there has to be at least one other bird between 0 and 3m

# make shapefile with threshold and mask applied
# crs_r = crs_lcc169
sf_obj <- st_as_sf(masked_df, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj, paste0("data/",directory,"/predict/counts/",model,"/GIS/masked_labels.shp"), append=FALSE)

# ------------------------------------------------------------------------------
# More de-duplication here 
# If you want to start with one of the above-generated files:
sf_obj <- st_read(paste0("data/",directory,"/predict/counts/",model,"/GIS/masked_labels.shp"))

# One more pass to de-duplicate masked_df (or "sf_obj" - whichever one you want),
# which sometimes still has quite a few duplicates somehow - when there's time, 
# continue to try to understand why that is?
# This procedure runs extremely quickly with RANN... just a few seconds for 220K
# records. Probably should run it before processing stuff above!

# Assuming sf_obj is your sf object with the correct CRS

# Extract coordinates
coords <- st_coordinates(sf_obj)

# Define the distance threshold (in meters)
threshold <- 0.5

# Initialize a vector to mark duplicates
n <- nrow(sf_obj)
is_duplicate <- rep(FALSE, n)

# Perform nearest neighbor search using RANN
# nn2 returns the indices of the nearest neighbors and the distances
nn <- nn2(coords, coords, k = 2)  # k = 2 to include the point itself

# Mark duplicates
for (i in 1:n) {
  if (is_duplicate[i]) next  # Skip already marked duplicates
  
  if (i %% 1000 == 0) {
    print(paste("Processing row:", i))
  }
  # The first column in nn$nn.idx is the point itself, so we check the second column
  nearest_neighbor_index <- nn$nn.idx[i, 2]
  nearest_distance <- nn$nn.dists[i, 2]
  
  if (nearest_distance < threshold) {
    is_duplicate[nearest_neighbor_index] <- TRUE
  }
}

# Remove duplicates
sf_obj_clean <- sf_obj[!is_duplicate, ]

# write the new layer
st_write(sf_obj_clean, paste0("data/",directory,"/predict/counts/",model,"/GIS/masked_labels_cleaned.shp"), append=FALSE)

# if you want to review the shapefile later:
# shapefile <- st_read(paste0("data/",directory,"/predict/counts/",model,"/GIS/bird_north_adpe_2022-11-26_lcc169/masked_labels_cleaned.shp"))
