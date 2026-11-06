# --------------------------------------------------------------------
# create_calibration_files_batch.R
# Creates the files used to calibrate model counts against manual counts
# (pipeline Step 7, first part). For each survey:
#   1. Defines the colony footprint from the de-duplicated, masked
#      detections (masked_labels_cleaned.shp) of all its orthomosaics and
#      overlays a 10 m x 10 m grid; cells without detections are dropped.
#   2. Samples 30 cells spread across the colony by k-means clustering of
#      cell centroids (one cell drawn per cluster; seed 42).
#   3. Assigns the sampled cells alternately to two observers.
#   4. Writes the grid, the sampled cells, the model candidate nests in
#      the sampled cells, and blank point layers for the observers to
#      digitize candidate nests into. Observers then copy that layer to
#      add occupied territories and total individuals (see
#      calibrate_counts.R for the file names it expects).
#
# Output, in data/<survey>/calibration_counts_survey_names/:
#   <survey>_assessment_grid_all.shp
#   <survey>_selected_cells_for_counting.shp
#   <survey>_candidate_nests_model_selected_cells.shp
#   <survey>_selected_cells_Observer_<1|2>.shp
#   <survey>_candidate_nests_Observer_<1|2>.shp  (blank; delete the
#                                                 placeholder point first)
#
# The sampled cells and the manual counts made in them cannot be
# regenerated, so surveys that already have sampled cells are skipped
# unless overwrite = TRUE.
#
# Run after clip_detections_to_nesting_areas_batch.R and before the
# manual counts and calibrate_counts.R. Run from the project root.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(sf)
library(dplyr)
library(RSQLite)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
db_name        <- "data/UAVSurveys.db"
model_name     <- "ADPE_20250804_adult_sit"
grid_size      <- 10  # meters
n_sample_cells <- 30  # number of cells to sample

# Surveys to process. NULL processes every survey with candidate nest
# totals for the model that does not yet have sampled cells.
surveys_to_run <- NULL

# Replace existing calibration files. Leave FALSE: existing sampled cells
# and the manual counts made in them would be lost.
overwrite <- FALSE

# Output folder name (within each survey folder) and file name prefix
cal_folder <- "calibration_counts_survey_names"
cal_file <- function(survey_name, name) {
  file.path("data", survey_name, cal_folder, paste0(survey_name, "_", name))
}

# --------------------------------------------------------------------
# Create calibration files for one survey
# --------------------------------------------------------------------

create_calibration_files <- function(survey_name, model_name, db_name,
                                     grid_size, n_sample_cells,
                                     overwrite = FALSE) {
  
  cat("\n============================================================\n")
  cat("Processing:", survey_name, "|", model_name, "\n")
  cat("============================================================\n")
  
  con <- dbConnect(SQLite(), dbname = db_name)
  on.exit(dbDisconnect(con), add = TRUE)
  
  # Existing sampled cells are protected
  if (file.exists(cal_file(survey_name, "selected_cells_for_counting.shp")) && !overwrite) {
    cat("Calibration files exist, skipping:", survey_name, "\n")
    return(invisible(NULL))
  }

  ortho_names <- dbGetQuery(con, "
    SELECT OrthomosaicName FROM SurveyImagery WHERE SurveyId = ?",
    params = list(survey_name)) %>%
    pull(OrthomosaicName) %>% tools::file_path_sans_ext()
  if (length(ortho_names) == 0) {
    stop("No orthomosaics found in SurveyImagery for survey '", survey_name, "'.")
  }
  
  gis_dir <- paste0("data/", survey_name, "/predict/counts/", model_name, "/GIS/")
  
  # --- Read masked_cleaned detections (defines the colony footprint) ---
  all_masked <- list()
  
  for (ortho_name in ortho_names) {
    ortho_dir <- file.path(gis_dir, ortho_name)
    shp_path <- file.path(ortho_dir, "masked_labels_cleaned.shp")
    
    if (file.exists(shp_path)) {
      pts <- st_read(shp_path, quiet = TRUE)
      pts$ortho <- ortho_name
      all_masked <- c(all_masked, list(pts))
      cat("Read", nrow(pts), "masked_labels_cleaned detections from", ortho_name, "\n")
    } else {
      warning("File not found: ", shp_path)
    }
  }
  
  masked_detections <- bind_rows(all_masked)
  cat("Total masked_cleaned detections:", nrow(masked_detections), "\n")
  
  # --- Read candidate nest detections (used for count comparison) ---
  all_clipped <- list()
  
  for (ortho_name in ortho_names) {
    ortho_dir <- file.path(gis_dir, ortho_name)
    shp_path <- file.path(ortho_dir, paste(ortho_name, "candidate_nests.shp", sep = "_"))
    
    if (file.exists(shp_path)) {
      pts <- st_read(shp_path, quiet = TRUE)
      pts$ortho <- ortho_name
      all_clipped <- c(all_clipped, list(pts))
      cat("Read", nrow(pts), "candidate nests from", ortho_name, "\n")
    } else {
      warning("File not found: ", shp_path)
    }
  }
  
  clipped_detections <- bind_rows(all_clipped)
  cat("Total candidate nests:", nrow(clipped_detections), "\n")
  
  if (nrow(clipped_detections) == 0) {
    stop("No candidate nest shapefiles found for '", survey_name,
         "'; run clip_detections_to_nesting_areas_batch.R first.")
  }
  
  # --- Create grid over masked_cleaned extent (the colony footprint) ---
  grid <- st_make_grid(st_buffer(st_as_sfc(st_bbox(masked_detections)), grid_size),
                       cellsize = grid_size, square = TRUE) %>%
    st_as_sf() %>%
    rename(geometry = x) %>%
    mutate(cell_id = row_number())
  
  st_crs(grid) <- st_crs(masked_detections)
  
  # --- Count detections per cell ---
  # Column names kept to <=10 chars so they survive shapefile round-trips
  grid$mask_n <- lengths(st_intersects(grid, masked_detections))
  grid$clip_n <- lengths(st_intersects(grid, clipped_detections))
  
  # Remove cells with no masked_cleaned detections (outside colony footprint)
  grid <- grid %>% filter(mask_n > 0)
  cat("Non-empty cells (masked_cleaned):", nrow(grid), "\n")
  
  cat("\nCandidate nests per cell:\n")
  print(summary(grid$clip_n))
  
  # --- Spatially distributed sampling using k-means clustering ---
  set.seed(42)
  n_to_sample <- min(n_sample_cells, nrow(grid))
  
  if (nrow(grid) <= n_to_sample) {
    sampled_cells <- grid
    cat("Colony has fewer cells than requested sample; using all", nrow(grid), "cells\n")
  } else {
    centroids <- st_coordinates(st_centroid(grid))
    km <- kmeans(centroids, centers = n_to_sample, nstart = 10)
    grid$cluster <- km$cluster
    
    sampled_cells <- grid %>%
      group_by(cluster) %>%
      slice_sample(n = 1) %>%
      ungroup() %>%
      select(-cluster)
  }
  
  sampled_cells <- sampled_cells %>%
    mutate(manual_n = NA_integer_)
  
  cat("\nTotal sampled cells:", nrow(sampled_cells), "\n")
  cat("Candidate nests in sampled cells:", sum(sampled_cells$clip_n), "\n")
  
  # --- Assign cells to two observers ---
  # Shuffle then alternate so each observer gets a spatially mixed set
  sampled_cells <- sampled_cells %>%
    slice_sample(n = nrow(.)) %>%
    mutate(observer = if_else(row_number() %% 2 == 1, "Observer_1", "Observer_2"))
  
  cat("\nCells per observer:\n")
  print(table(sampled_cells$observer))
  
  # --- Export for manual counting ---
  output_dir <- file.path("data", survey_name, cal_folder)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  # Full grid with model counts (cell count N is used by calibrate_counts.R)
  st_write(grid, cal_file(survey_name, "assessment_grid_all.shp"),
           delete_layer = TRUE, quiet = TRUE)

  # Sampled cells only (for manual counting)
  st_write(sampled_cells, cal_file(survey_name, "selected_cells_for_counting.shp"),
           delete_layer = TRUE, quiet = TRUE)

  # Model candidate nests within sampled cells (visual reference for observers)
  sampled_det_idx <- lengths(st_intersects(clipped_detections, sampled_cells)) > 0
  sampled_detections <- clipped_detections[sampled_det_idx, ]
  st_write(sampled_detections,
           cal_file(survey_name, "candidate_nests_model_selected_cells.shp"),
           delete_layer = TRUE, quiet = TRUE)

  # Per-observer shapefiles (cells)
  for (obs in unique(sampled_cells$observer)) {
    obs_cells <- sampled_cells %>% filter(observer == obs)
    st_write(obs_cells,
             cal_file(survey_name, paste0("selected_cells_", obs, ".shp")),
             delete_layer = TRUE, quiet = TRUE)
  }
  
  # Blank point layers for each observer to digitize candidate nests into.
  # Note: shapefiles cannot store an empty point layer without defaulting to
  # a line type, so we include a single dummy point at (0,0) that observers
  # should delete before starting.
  # Observers then duplicate this layer and add standing occupied birds to
  # produce the occupied territory and total individual layers.
  dummy_point <- st_sf(
    notes = "DELETE THIS ROW - placeholder to set geometry type",
    geometry = st_sfc(st_point(c(0, 0)), crs = st_crs(masked_detections))
  )
  
  for (obs in unique(sampled_cells$observer)) {
    out_path <- cal_file(survey_name, paste0("candidate_nests_", obs, ".shp"))
    st_write(dummy_point, out_path, delete_layer = TRUE, quiet = TRUE)
  }
  
  cat("\nExported to:", output_dir, "\n")
  invisible(TRUE)
}

# --------------------------------------------------------------------
# Run
# --------------------------------------------------------------------
con <- dbConnect(SQLite(), dbname = db_name)
surveys <- dbGetQuery(con, "
  SELECT DISTINCT cc.SurveyId
  FROM CalibratedCounts cc
  JOIN ModelPredictions mp ON mp.PredictId = cc.PredictId
  WHERE cc.CandidateNestTotal IS NOT NULL AND mp.ModelName = ?
  ORDER BY cc.SurveyId", params = list(model_name))$SurveyId
dbDisconnect(con)

if (!is.null(surveys_to_run)) {
  missing <- setdiff(surveys_to_run, surveys)
  if (length(missing) > 0) stop("No candidate nest totals for: ", paste(missing, collapse = ", "))
  surveys <- surveys_to_run
}

failures <- character(0)
for (s in surveys) {
  tryCatch(
    create_calibration_files(s, model_name, db_name, grid_size, n_sample_cells,
                             overwrite = overwrite),
    error = function(e) {
      message("Failed for survey '", s, "': ", conditionMessage(e))
      failures <<- c(failures, s)
    })
}
if (length(failures) > 0) {
  stop(length(failures), " survey(s) failed: ", paste(failures, collapse = ", "))
}
cat("\nDone. Open the", cal_folder, "folders in QGIS to begin manual counting.\n")
