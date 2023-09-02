#remove duplicates from the penguin labels (edges only)
#also writes new table with coordinates for each label

#Grant 5/23/2023 (Gull version)
#Last update: 9/1/2023 (for using with ADPE data instead)
# v2 re-factord to avoid hard-coding file names etc.

library(dplyr)
library(readr)
library(stringr)
library(future.apply)
library(foreach)
library(doParallel)
library(terra)
library(sf)

# set working directory
wd <- "Z:/informatics/s031/analyses/RI_penguin_count_UAV/"
setwd(wd)

colony <- "royd"
ortho_prefix <- "royd_20191204"
model_name <- "adult_s2_best"
label <- "ADPE_sit"

# Set the directory path where the individual label files are located
#label_path <- paste0(wd,"predict/2019/croz_20191202/adult_s2_best/labels")
output_path <- paste0(wd,"predict/2019/",ortho_prefix,"/",model_name,"/")
label_path <- paste0(output_path,"labels")
dupe_indicators_csv <- paste0(output_path,"dupe_indicators.csv")
dupe_indicators_shp <- paste0(output_path,"dupe_indicators.shp")
de_duplicated_csv <- paste0(output_path,"de_duplicated.csv")
de_duplicated_shp <- paste0(output_path,"de_duplicated.shp")
de_duplicated_smaller_csv <- paste0(output_path,"de_duplicated_smaller.csv")
de_duplicated_smaller_shp <- paste0(output_path,"de_duplicated_smaller.shp")

# Define crs of the orthomosaic and tiles if data are projected:
crs <- st_crs("+proj=lcc +lat_1=-76.666667 +lat_2=-79.333333 +lat_0=-78.021171 +lon_0=169.333333 +x_0=500000 +y_0=300000 +ellps=WGS84 +datum=WGS84 +units=m +no_defs")

georeftable <- paste0(wd,"predict/2019/",ortho_prefix,"/tiles/",ortho_prefix,"_tilesGeorefTable_v2.csv")

# if you are going to need to calculate the pixel dimensions, specify which ortho this is coming from
# the values will depend on the pixel resolution of the original orthomosaic
# of <- r"(Y:\PenguinCounting\croz_20191202\croz_20191202.tif)"
of <- r"(Y:\PenguinCounting\royd_20191204\royd_20191204.tif)"

ortho <-
  terra::rast(of)
pixW <- xres(ortho)
pixH <- yres(ortho)

# for Croz_20191202:
# pixW <- 0.0159296
# pixH <- 0.0159385

# for Royd_20191204:
# pixW <- 0.012167
# pixH <- 0.012167

###############################################################################
## Build a combined predictions df if needed
###############################################################################
# note that this can take some time - don't re-do it unless you need to! 
# can skip to the next read.csv command if you've already built this file
#
# make a df with the label data of interest:
# in the case of predictions from yolo v5, these will each be in their own file
# with the name of the tile in the title, and the columns in this order:
# label category (0 - ADPE nest, 1 - ADPE stand, 2  ADPE chick) --DOUBLE CHECK THIS
# x_center: The center of the object's bounding box in the x-axis, as a normalized value between 0 and 1.
# y_center: The center of the object's bounding box in the y-axis, as a normalized value between 0 and 1.
# width: The width of the object's bounding box, as a normalized value.
# height: The height of the object's bounding box, as a normalized value.
# confidence: The confidence score of the detection.

# so, need to loop through the whole directory of interest and append into a single CSV

# note that there is one folder for each model for each UAV survey - so all the labels in the given directory
# will be the same (0)

# Get a list of all label file names in the directory
label_files <- array(list.files(path = label_path, pattern = "\\.txt$", full.names = TRUE))

# Set the number of cores for parallel processing
plan(multisession, workers = 16)  # Adjust the number of workers as needed

# Function to process a label file and return its data frame
process_label_file <- function(file) {
  # Extract tile name from the file name
  tile_name <- paste0(str_extract(file, paste0("(",colony,"_\\d+_\\d+_\\d+)")), ".jpg")
  
  # Read the label file
  labels <- read_delim(file, delim = " ", col_names = FALSE, show_col_types = FALSE)
  
  # Check that the label file is not empty
  if (nrow(labels) == 0) {
    stop("The label file is empty")
  }
  
  # Create a data frame for the current file's data
  file_data <- data.frame(
    tileName = rep(tile_name, nrow(labels)),
    label = labels$X1,
    box_center_w = labels$X2,
    box_center_h = labels$X3,
    box_width = labels$X4,
    box_height = labels$X5,
    confidence = labels$X6
  )
  
  return(file_data)
  # print(file_data$tileName)
}

# Process label files in parallel and combine results
combined_data <- future_apply(label_files, FUN = process_label_file, MARGIN = 1, 
                              future.seed = TRUE, future.chunk.size = 1e3) %>%
  bind_rows()

plan(sequential)

# Write the combined data to a CSV file
write_csv(combined_data, paste0(label_path,"/combined_predictions.csv"))

df <- combined_data

# start here if you already made the combined_predictions df
# df <- read.csv(paste0(label_path,"/combined_predictions.csv"))

# add the img_file column for later use
df$img_file<-df$tileName

# specify tile dimensions - these should be 512 (W) by 256 (H) but note that lots of things depend on that!
df$img_width <- (512)
df$img_height <- (256)

# note that the way we are running YOLO for ADPE, the category is always 0, so would need to modify
# the following depending on which model output you are running this on
df$int_category <- 0
df$label <- label

# add some new columns which are used by the duplicate detector:
df$lt_dupe_poss <- NA
df$rt_dupe_poss <- NA
df$tt_dupe_poss <- NA
df$bt_dupe_poss <- NA
df$left_dupe <- NA
df$right_dupe <- NA
df$top_dupe <- NA
df$bottom_dupe <- NA

####################################################################################
## Figure out which tiles are adjacent - will only have tiles where there were labels
# Note that regex is needed do to the variable number of numbers in the tile names
####################################################################################

# Function to extract row, and column values from img_file
extract_info <- function(img_file) {
  pattern <- paste0("(", colony, ")(_)(\\d{8})(_)(\\d{1,3})(_)(\\d{1,3})(\\.jpg)")
  matches <- regexec(pattern, img_file, perl=TRUE)
  if (matches[[1]][1] != -1) {
    #plot_name <- substring(img_file, matches[[1]][2], matches[[1]][3]-1)
    col <- as.integer(substring(img_file, matches[[1]][6], matches[[1]][7] - 1))
    row <- as.integer(substring(img_file, matches[[1]][8], matches[[1]][9] - 1))
  } else {
    #plot_name <- NA
    col <- NA
    row <- NA
  }
  return(list(col = col, row = row))
}

# Not sure threading this actually helps, but it takes a while either way
# Set the number of cores you want to use when finding the adjacent tiles
num_cores <- 16  # Adjust based on your system's capabilities

# Register the parallel backend
cl <- makeCluster(num_cores)
registerDoParallel(cl)

# Function to process each row (adding the adjacent tile names)
process_row <- function(img_file) {
  info <- extract_info(img_file)
  if (!is.na(info$col)) {
    bottom_tile <- paste0(ortho_prefix,"_", info$col, "_", info$row + 1, ".jpg")
  } else {
    bottom_tile <- NA
  }
  
  if (!is.na(info$col)) {
    top_tile <- paste0(ortho_prefix,"_", info$col, "_", info$row - 1, ".jpg")
  } else {
    top_tile <- NA
  }
  
  if (!is.na(info$row)) {
    left_tile <- paste0(ortho_prefix,"_", info$col - 1, "_", info$row, ".jpg")
  } else {
    left_tile <- NA
  }
  
  if (!is.na(info$row)) {
    right_tile <- paste0(ortho_prefix,"_", info$col + 1, "_", info$row, ".jpg")
  } else {
    right_tile <- NA
  }
  
  return(data.frame(
    bottom_tile = bottom_tile,
    top_tile = top_tile,
    left_tile = left_tile,
    right_tile = right_tile
  ))
}

# Apply the function to each row using parallelization
# this will take several minutes for Crozier
result_list <- foreach(i = 1:nrow(df), .combine = rbind) %dopar% {
  process_row(df$img_file[i])
}

# Stop the parallel backend
stopCluster(cl)

# Combine the result with the original dataframe
result_df <- data.frame(result_list)
df <- cbind(df, result_df)

## get rid of weird labels
# Calculate box area in square pixels
df$box_area_pixels <- df$box_height * 256 * df$box_width * 512

summary(df$box_area_pixels)
# Filter out rows with box_area_pixels > 1225 (35 x 35 pixels) for Crozier 2019
# df <- df[df$box_area_pixels <= 1225, ]
# Filter out rows with box_area_pixels > 1500 for Royds 2019
df <- df[df$box_area_pixels <= 1500, ]

# Now need to determine if there are any box centers at the edges of any of the tiles
# Create new columns and mark potentially duplicated labels
# the scale of these things set to 27 - 31 pixels based on visualizing results. 
# A whole penguin measures about 27.7 x 15.6 pixels
# Note that the numbers are as a proportion of the pixel width or height of the tile
df$lt_dupe_poss <- ifelse(df$box_center_w < 0.06, 1, 0) ##within 31 pixels of left edge
df$rt_dupe_poss <- ifelse(df$box_center_w > 0.94, 1, 0) ##within 31 pixels of right edge
df$tt_dupe_poss <- ifelse(df$box_center_h < 0.12, 1, 0) ##within 31 pixels of top edge
df$bt_dupe_poss <- ifelse(df$box_center_h > 0.88, 1, 0) ##within 31 pixels of bottom edge

# sum(df$lt_dupe_poss == 1 & df$int_category==0)
# sum(df$rt_dupe_poss == 1 & df$int_category==0)
# sum(df$tt_dupe_poss == 1 & df$int_category==0)
# sum(df$bt_dupe_poss == 1 & df$int_category==0)

#####################################
## check for horizontal duplicates
#####################################
# if you're starting over here:
# df <- read.csv("predict/2019/croz_20191202/adult_s2_best/all_nests_with_dupe_indicators_v6.csv")
# df$img_file<-df$tileName


df$left_dupe <- 0
df$right_dupe <- 0
df$dupe_id <- NA # for uniquely identifying all the duplicates
dc <- 0 # dupecounter

# on the horizontal (x) axis, we have 512 pixels
# if a penguin is about 31 pixels max dimension, then we want to find any boxes that are within say 1.5 x 
# so I tried 46.5 pixels, or 9% of the 512 in the width dimension, but this tuned out to be  bit too aggressive
# so reduced to 7% (14% on the horizontal and 7% on the vertical)

for (i in 1:nrow(df)) {
  if (i %% 10000 == 0) {
    print(paste("Processing row:", i))
  }
  if (df$lt_dupe_poss[i] == 1 && !is.na(df$left_tile[i])) {
    left_tile <- df$left_tile[i]
    bch = df$box_center_h[i]
    bcw = df$box_center_w[i]
    matching_row <- df[df$img_file == left_tile & abs(df$box_center_h-bch)<0.14 & abs(df$box_center_w-bcw) > 0.90,]
    # Tried 0.1 and 0.8 at first and still had a lot of duplicates, so trying 0.15, then 0.24...
    # 0.18 should be right for the vertical - that allows 1.5 penguin dimensions?
    
    if (nrow(matching_row) > 0 && sum(matching_row$rt_dupe_poss > 0) && 
        (sum(matching_row$int_category == 0) > 0))  { # i.e., there was at least one nest in the matching set
      df$left_dupe[i] <- 1
      df$right_dupe[df$img_file == left_tile & abs(df$box_center_h-bch)<0.14 & abs(df$box_center_w-bcw) > 0.90] <-1
      dc = dc+1
      df$dupe_id[i] <- dc 
      df$dupe_id[df$img_file == left_tile & abs(df$box_center_h-bch)<0.14 & abs(df$box_center_w-bcw) > 0.90] <- dc
      # print(df$dupe_id[i])
      # it is going to replace dupe_id with the most recent dupe indicator - but either way it will be marked as a duplicate label?
    }
  }
}

# sum(df$left_dupe==1 & df$int_category!=3)
# sum(df$right_dupe==1 & df$int_category!=3)
# Note that this next part works pretty well, but there are cases (2 that I found on Twain)
# where a corner gull was tagged on 3 of 4 tiles and they get marked as 2 different dupes

#####################################
## check for vertical duplicates
#####################################
df$top_dupe <- 0
df$bottom_dupe <- 0
for (i in 1:nrow(df)) {
  
  if (i %% 10000 == 0) {
    print(paste("Processing row:", i))
  }
  
  if (df$tt_dupe_poss[i] == 1 && !is.na(df$top_tile[i])) {
    # print(i)
    top_tile <- df$top_tile[i]
    bcw = df$box_center_w[i]
    bch = df$box_center_h[i]
    matching_row <- df[df$img_file == top_tile & abs(df$box_center_w-bcw)<0.07 & abs(df$box_center_h-bch) > 0.85, ]
    # Tried 0.05 and 0.80 at first - still lots of duplicates, so now trying 0.10 and 0.80, then 0.12...
    if (nrow(matching_row) > 0 && sum(matching_row$bt_dupe_poss > 0) && 
        (sum(matching_row$int_category == 0) > 0)) { #i.e., there was at least one nest in the matching set
      df$top_dupe[i] <- 1
      df$bottom_dupe[df$img_file == top_tile & abs(df$box_center_w-bcw)<0.07 & abs(df$box_center_h-bch) > 0.85] <- 1
      if (!is.na(df$dupe_id[i])) { #already has a dupe id - use the same label
        df$dupe_id[df$img_file == top_tile & abs(df$box_center_w-bcw)<0.07 & abs(df$box_center_h-bch) > 0.85] <- df$dupe_id[i]
        # print(df$dupe_id[i])
      } else {
        dc = dc + 1
        df$dupe_id[i] <- dc 
        df$dupe_id[df$img_file == top_tile & abs(df$box_center_w-bcw)<0.07 & abs(df$box_center_h-bch) > 0.85] <- dc
        # print(df$dupe_id[i])
        # it is going to replace dupe_id with the most recent dupe indicator - but either way it will be marked as a duplicate label?
      }
    }
  }
}

# number of labels that are duplicated:
dupe_nests<-length(unique(df$dupe_id))

# number of nests
total_nests<-nrow(subset(df, int_category==0))

print(total_nests-dupe_nests)

#write the full csv in case it is useful - or if you need to re-start from here:
#note that it won't have geo_x and geo_y yet if this is the first time through
#write_csv(df, "predict/2019/croz_20191202/adult_s2_best/all_nests_with_dupe_indicators_v7.csv")
write_csv(df, dupe_indicators_csv)

# can start from here if you have already done above previously
#df <- read_csv("predict/2019/croz_20191202/adult_s2_best/all_nests_with_dupe_indicators_v7.csv")
df <- read_csv(dupe_indicators_csv)

############################################
## add latitude and longitude to every label
############################################

# read in the georeference info:
grt <- read.csv(georeftable)

# df <- rename(df, tileName = img_file)
df_backup <- df
df <- df_backup

# Merge the dataframes
df <- left_join(df, grt, by="tileName")


# image_url <- "https://deju-penguinscience.s3.us-east-2.amazonaws.com/PenguinCounting/croz_20191202/croz_20191202.tif"
# of <- terra::rast(image_url)
#note that this relied on mapping s3:deju-penguinscience as Y (used TNT drive for that)
#otherwise would need to download the ortho 

df$label_geo_x <- df$geo_x + (df$box_center_w*512*pixW)
df$label_geo_y <- df$geo_y - (df$box_center_h*256*pixH)

write_csv(df, dupe_indicators_csv)
############################################################

# Create an sf object from the CSV data
sf_obj <- st_as_sf(df, coords = c("label_geo_x", "label_geo_y"), crs = crs)

# Write the sf object to a shapefile
#st_write(sf_obj, "predict/2019/croz_20191202/adult_s2_best/all_nests_with_dupe_indicators_v7.shp", append=FALSE)
st_write(sf_obj, dupe_indicators_shp, append=FALSE)


# make a subset that retains all the non-duplicated labels and the duplicated labels with the highest
# confidence score

de_duplicated_nests_df <- df %>%
  group_by(dupe_id) %>%
  mutate(is_duplicate = !is.na(dupe_id)) %>%
  arrange(is_duplicate, desc(confidence)) %>%
  filter(!is_duplicate | row_number() == 1) %>%
  ungroup() %>%
  select(-is_duplicate)

df <- de_duplicated_nests_df

# write it if you want
#write_csv(df, r"(Z:\Informatics\S031\analyses\RI_penguin_count_UAV\predict\2019\croz_20191202\adult_s2_best\combined_predictions.csv)")
#write_csv(df, "predict/2019/croz_20191202/adult_s2_best/de_duplicated_nests_v7.csv")
write_csv(df, de_duplicated_csv)

#df <- read.csv(de_duplicated_csv)
# number of nests
total_nests<-nrow(subset(df, confidence>0.05))
# 2312 for Royds 2019-20 

#Make a smaller version with only the fileds you need
#subset_df <- filter(df, grepl("twain", tileName))
#subset_df <- df
subset_df <- df[, c("tileName", "label_geo_x", "label_geo_y", "confidence", "dupe_id", "int_category")]

#write_csv(subset_df, "predict/2019/croz_20191202/adult_s2_best/de_duplicated_nests_smaller_v7.csv")
write_csv(subset_df, de_duplicated_smaller_csv)

## write the subset as a shapefile:
# Create an sf object from the CSV data
sf_obj <- st_as_sf(subset_df, coords = c("label_geo_x", "label_geo_y"), crs = crs)
#sf_obj <- st_as_sf(df, coords = c("geo_x", "geo_y"), crs = crs)

# Write the sf object to a shapefile
#st_write(sf_obj, "predict/2019/croz_20191202/adult_s2_best/de_duplicated_nests_smaller_v7.shp", append=FALSE)
#st_write(sf_obj, "predict/2019/croz_20191202/adult_s2_best/de_duplicated_nests_smaller_v7.shp", append=FALSE)
st_write(sf_obj, de_duplicated_smaller_shp, append=FALSE)

nrows(df[df$confi])
