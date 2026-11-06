# --------------------------------------------------------------------
# consolidate_labels_remove_duplicates.R
# Consolidates YOLO detections for one orthomosaic and processes them
# into georeferenced, de-duplicated point datasets (pipeline Step 6,
# first part):
#   1. Combines the per-tile label files into combined_predictions.csv.
#   2. Retrieves the survey's confidence threshold from the UAVSurveys
#      database and keeps detections with confidence >= threshold.
#   3. Calculates projected coordinates for each detection from the tile
#      georeference table and the orthomosaic's resolution and CRS.
#      Tiles are assumed to be 512 x 256 pixels.
#   4. Removes duplicate detections (centers within 0.5 m of each other;
#      the highest-confidence detection is kept), flags "solo" detections
#      (the only detection in its tile and the four adjacent tiles), and
#      records the distance to the nearest non-duplicate neighbor within
#      3 m. This runs in parallel batches of detections; detections in
#      different batches are not compared, so results can differ slightly
#      with the number of cores (cn). Duplicates missed at batch
#      boundaries are removed in a final pass.
#   5. Applies the proximity mask (keeps detections that are not solo and
#      have a non-duplicate neighbor within 3 m), removes remaining
#      duplicates, writes shapefiles, and records the count in the
#      MaskedCleaned field of the ModelPredictions table.
#
# Surveys split into several orthomosaics (e.g., Cape Bird north, mid,
# south) are processed one orthomosaic at a time; outputs are written to
# a subfolder per orthomosaic.
#
# Outputs:
#   data/<survey>/predict/counts/<model>/csv/<ortho>/
#     combined_predictions.csv, final_results_threshold<NN>.csv
#   data/<survey>/predict/counts/<model>/GIS/<ortho>/
#     all_labels.shp, de_duplicated_labels_par<cn>.shp,
#     threshold<NN>_labels.shp, masked_labels.shp,
#     masked_labels_cleaned.shp
# where <NN> is the threshold x 100 and <cn> the number of cores.
#
# Run from the project root.
#
# Developed with assistance from Gemini (Google) and Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(dplyr)
library(foreach)
library(doParallel)
library(readr)
library(stringr)
library(fs)
library(sf)
library(terra)
library(RANN)
library(data.table)
library(RSQLite)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
# Full name of the orthomosaic, without the .tif extension. For surveys
# split into several orthomosaics, run once per orthomosaic.
ortho_name_full <- "bird_south_adpe_2025-12-01_lcc169"

# Survey directory override, normally NULL (derived from the orthomosaic
# name). Needed only for the combined mid-south orthomosaic of the 2021
# Cape Bird survey: manual_survey_directory <- "bird_adpe_2021-12-02"
manual_survey_directory <- NULL

# Trained model used for detection
model_name <- "ADPE_20250804_adult_sit"

# Number of cores (batches) for de-duplication; recorded in the name of
# the de_duplicated_labels_par<cn> output
cn <- 12

# --------------------------------------------------------------------
# Derived names and paths
# --------------------------------------------------------------------
if (!is.null(manual_survey_directory) && nzchar(manual_survey_directory)) {
  survey_directory <- manual_survey_directory
} else {
  # Remove a sub-site name (_north, _mid, _south) and the final component
  # (e.g., _lcc169) to get the survey directory
  survey_directory <- str_remove(ortho_name_full, "_north|_mid|_south") %>%
    sub("_[^_]+$", "", .)
}
ortho_name <- ortho_name_full

georeftable <- fs::path("data", survey_directory, "predict",
                        paste0(ortho_name, "_tilesGeorefTable.csv"))
orthoinfo   <- fs::path("data", survey_directory, "predict",
                        paste0(ortho_name, "_OrthoInfo.csv"))
ortho_file  <- fs::path("data", survey_directory, "orthomosaics",
                        paste0(ortho_name, ".tif"))
labels_path <- fs::path("data", survey_directory, "predict", "counts",
                        model_name, "labels")
csv_path    <- fs::path("data", survey_directory, "predict", "counts",
                        model_name, "csv", ortho_name)
gis_path    <- fs::path("data", survey_directory, "predict", "counts",
                        model_name, "GIS", ortho_name)
db_path     <- fs::path("data", "UAVSurveys.db")

# --------------------------------------------------------------------
# Confidence threshold from the database
# --------------------------------------------------------------------
con <- dbConnect(SQLite(), dbname = db_path)
th <- dbGetQuery(con, "
  SELECT Threshold FROM ModelPredictions
  WHERE OrthomosaicName = ? AND ModelName = ?",
                 params = list(paste0(ortho_name, ".tif"), model_name))$Threshold
dbDisconnect(con)

if (length(th) != 1 || is.na(th)) {
  stop("Expected one threshold in ModelPredictions for orthomosaic ",
       ortho_name, " and model ", model_name, "; found ", length(th), ".")
}

message("Survey directory: ", survey_directory)
message("Orthomosaic: ", ortho_name)
message("Model: ", model_name)
message("Confidence threshold: ", th)
message("Labels path: ", labels_path)

# --------------------------------------------------------------------
# Combine label files
# --------------------------------------------------------------------
# One label file per tile with at least one detection
label_files <- list.files(
  path = labels_path,
  pattern = paste0("^", ortho_name, ".*\\.txt$"),
  full.names = TRUE
)

# Read one label file: class, box center (x, y) and size normalized to
# the tile, and confidence
process_label_file <- function(file) {
  tile_name <- paste0(gsub("\\.txt$", "", basename(file)), ".jpg")
  labels <- fread(file, header = FALSE, sep = " ")
  data.table(
    tileName     = rep(tile_name, nrow(labels)),
    label        = labels$V1,
    box_center_w = labels$V2,
    box_center_h = labels$V3,
    box_width    = labels$V4,
    box_height   = labels$V5,
    confidence   = labels$V6
  )
}

# Read files in parallel (row order follows label_files)
cl <- makeCluster(max(1, floor(detectCores() / 4)))
registerDoParallel(cl)
combined_data <- foreach(file = label_files, .combine = "rbind",
                         .packages = c("data.table")) %dopar% {
                           process_label_file(file)
                         }
stopCluster(cl)

# Record the lowest confidence retained at inference
if (nrow(combined_data) > 0) {
  min_confidence_rounded <- round(min(combined_data$confidence, na.rm = TRUE), 3)
  message("Initial confidence threshold for this run: ", min_confidence_rounded)
  con <- dbConnect(SQLite(), dbname = db_path)
  dbExecute(con, "
    UPDATE ModelPredictions
    SET InitialConfThreshold = ?
    WHERE OrthomosaicName = ? AND ModelName = ?",
            params = list(min_confidence_rounded, paste0(ortho_name_full, ".tif"),
                          model_name))
  dbDisconnect(con)
}

dir_create(csv_path)
fwrite(combined_data, file = paste0(csv_path, "/combined_predictions.csv"),
       sep = ",", quote = FALSE)

# --------------------------------------------------------------------
# Apply threshold and identify adjacent tiles
# --------------------------------------------------------------------
df <- fread(paste0(csv_path, "/combined_predictions.csv"))
df <- subset(df, confidence >= th)

# Nominal tile dimensions (pixels)
df$img_width  <- 512
df$img_height <- 256

# Column and row of each tile from its name (<ortho_name>_<col>_<row>.jpg)
extract_info_vectorized <- function(img_files, ortho_name) {
  pattern <- paste0(ortho_name, "_(\\d+)_(\\d+)\\.jpg")
  matches <- str_match(img_files, pattern)
  list(col = as.integer(matches[, 2]), row = as.integer(matches[, 3]))
}
info <- extract_info_vectorized(df$tileName, ortho_name)

# Names of the four adjacent tiles
df$bottom_tile <- ifelse(!is.na(info$col), paste0(ortho_name, "_", info$col, "_", info$row + 1, ".jpg"), NA)
df$top_tile    <- ifelse(!is.na(info$col), paste0(ortho_name, "_", info$col, "_", info$row - 1, ".jpg"), NA)
df$left_tile   <- ifelse(!is.na(info$row), paste0(ortho_name, "_", info$col - 1, "_", info$row, ".jpg"), NA)
df$right_tile  <- ifelse(!is.na(info$row), paste0(ortho_name, "_", info$col + 1, "_", info$row, ".jpg"), NA)

# --------------------------------------------------------------------
# Projected coordinates for each detection
# --------------------------------------------------------------------
grt <- fread(georeftable)
df <- left_join(df, grt, by = "tileName")
if (anyNA(df$northing)) {
  stop(sum(is.na(df$northing)), " detections are on tiles missing from ",
       "the georeference table.")
}

# CRS and resolution: from OrthoInfo.csv if present, otherwise from the
# orthomosaic (and saved to OrthoInfo.csv for next time)
if (file.exists(orthoinfo)) {
  ortho_info_df <- read.csv(orthoinfo)
  crs_r <- st_crs(ortho_info_df$crs_r)
  xres <- as.numeric(ortho_info_df$xres)
  yres <- as.numeric(ortho_info_df$yres)
} else {
  r <- rast(ortho_file)
  crs_r <- st_crs(crs(r))
  xres <- res(r)[1]
  yres <- res(r)[2]
  write.csv(data.frame(crs_r = crs(r), xres = xres, yres = yres),
            orthoinfo, row.names = FALSE)
}

df$geo_x <- df$easting + (df$box_center_w * 512 * xres)
df$geo_y <- df$northing - (df$box_center_h * 256 * yres)
df$box_area <- (df$box_width * xres * df$img_width) *
  (df$box_height * yres * df$img_height)

# --------------------------------------------------------------------
# Parallel duplicate removal and neighbor flags
# --------------------------------------------------------------------
# Detections within dr of each other are duplicates. A detection is
# flagged solo if it is the only detection in its tile and the four
# adjacent tiles; d3m records the distance to the nearest non-duplicate
# neighbor within 3 m (NA if none).
thn <- as.character(th * 100)   # threshold, for output file names
dr <- 0.5                       # duplicate radius (m)

setDT(df)
df[, label_id := .I]            # unique, sequential ID
df[, clustered := FALSE]        # TRUE once assigned to a duplicate group
df[, cluster_id := label_id]    # duplicate group ID
df[, solo := FALSE]
df[, d3m := 0]

# Separate R sessions as workers (the default on Windows, set explicitly
# here so that results do not depend on the operating system)
cl <- makeCluster(cn, type = "PSOCK")
registerDoParallel(cl)
n <- nrow(df)
batches <- split(df, cut(seq(n), breaks = cn, labels = FALSE))

process_batch <- function(batch_df) {
  for (current_label_id in unique(batch_df$label_id)) {
    current_label <- batch_df[label_id == current_label_id]
    tile <- current_label$tileName
    
    # Detections in this tile and the four adjacent tiles
    nl_count <- batch_df[(tileName == tile | bottom_tile == tile | top_tile == tile |
                            left_tile == tile | right_tile == tile), .N]
    if (nl_count == 1) {
      batch_df[label_id == current_label_id, `:=`(solo = TRUE)]
      next
    }
    subset_df <- batch_df[((tileName == tile | bottom_tile == tile | top_tile == tile |
                              left_tile == tile | right_tile == tile)),
                          .(label_id, tileName, geo_x, geo_y, confidence)]
    
    # Distance to the nearest neighbor farther than dr and within 3 m
    nn_results_3m <- nn2(data.matrix(subset_df[, .(geo_x, geo_y)]),
                         query = data.matrix(current_label[, .(geo_x, geo_y)]),
                         searchtype = "radius", radius = 3)
    nn3m <- nn_results_3m$nn.dists[nn_results_3m$nn.dists <= 3 &
                                     nn_results_3m$nn.dists > dr]
    v_nn3m <- if (length(nn3m) > 0) round(nn3m[1], 2) else NA
    batch_df[label_id == current_label_id, `:=`(d3m = v_nn3m)]
    
    # Detections within dr (including this one) form a duplicate group
    nn_results <- nn2(data.matrix(subset_df[, .(geo_x, geo_y)]),
                      query = data.matrix(current_label[, .(geo_x, geo_y)]),
                      searchtype = "radius", radius = dr)
    valid_neighbor_indices <- nn_results$nn.idx[nn_results$nn.dists < dr]
    neighbor_label_ids <- subset_df$label_id[valid_neighbor_indices]
    existing_cluster_ids <- unique(batch_df[label_id %in% neighbor_label_ids, cluster_id])
    
    if (length(neighbor_label_ids) > 1) {
      chosen_cluster_id <- ifelse(length(existing_cluster_ids) > 0 &&
                                    !is.na(existing_cluster_ids[1]),
                                  existing_cluster_ids[1], current_label_id)
      batch_df[label_id %in% neighbor_label_ids,
               `:=`(cluster_id = chosen_cluster_id, clustered = TRUE)]
    }
  }
  batch_df
}

results <- foreach(batch = batches, .combine = rbind,
                   .packages = c("data.table", "RANN")) %dopar% {
                     process_batch(batch)
                   }
stopCluster(cl)

# Keep the highest-confidence detection in each duplicate group
final_results <- results[order(-confidence), .SD[1], by = cluster_id]

# --------------------------------------------------------------------
# Write first-pass outputs
# --------------------------------------------------------------------
dir_create(gis_path)

# All detections above the threshold, before de-duplication
sf_obj_all <- st_as_sf(df, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj_all, fs::path(gis_path, "all_labels.shp"), append = FALSE)

write_csv(final_results, fs::path(csv_path, paste0("final_results_threshold", thn, ".csv")))
sf_obj_dedup1 <- st_as_sf(final_results, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj_dedup1, fs::path(gis_path, paste0("de_duplicated_labels_par", cn, ".shp")),
         append = FALSE)

# --------------------------------------------------------------------
# Proximity mask and final duplicate removal
# --------------------------------------------------------------------
# "Masked" here means the proximity filter (not solo, and a non-duplicate
# neighbor within 3 m), not a spatial clip. Clipping to nesting areas is
# done by a later script.
threshold_df <- subset(final_results, confidence >= th)
masked_df <- subset(threshold_df, d3m > 0 & d3m <= 3 & !solo)

sf_obj_thresh <- st_as_sf(threshold_df, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj_thresh, fs::path(gis_path, paste0("threshold", thn, "_labels.shp")),
         append = FALSE)
sf_obj_masked <- st_as_sf(masked_df, coords = c("geo_x", "geo_y"), crs = crs_r)
st_write(sf_obj_masked, fs::path(gis_path, "masked_labels.shp"), append = FALSE)

# Remove duplicates missed at batch boundaries: for each detection, if
# its nearest neighbor is within 0.5 m, drop the neighbor
coords <- st_coordinates(sf_obj_masked)
is_duplicate <- rep(FALSE, nrow(sf_obj_masked))
if (nrow(coords) > 1) {
  nn <- RANN::nn2(coords, coords, k = 2)
  for (i in 1:nrow(sf_obj_masked)) {
    if (is_duplicate[i]) next
    if (nn$nn.dists[i, 2] < 0.5) {
      is_duplicate[nn$nn.idx[i, 2]] <- TRUE
    }
  }
}
sf_obj_clean <- sf_obj_masked[!is_duplicate, ]
st_write(sf_obj_clean, fs::path(gis_path, "masked_labels_cleaned.shp"), append = FALSE)

# --------------------------------------------------------------------
# Record the count in the database (replaces any earlier value)
# --------------------------------------------------------------------
con <- dbConnect(SQLite(), dbname = db_path)
n_upd <- dbExecute(con, "
  UPDATE ModelPredictions
  SET MaskedCleaned = ?
  WHERE OrthomosaicName = ? AND ModelName = ?",
                   params = list(nrow(sf_obj_clean), paste0(ortho_name_full, ".tif"), model_name))
dbDisconnect(con)
if (n_upd != 1) warning(n_upd, " ModelPredictions rows updated; expected 1.")
message("MaskedCleaned = ", nrow(sf_obj_clean))