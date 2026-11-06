# --------------------------------------------------------------------
# calculate_validation_stats.R
# Selects the confidence threshold for one survey (pipeline Step 5) using
# the functions in validation_functions.R:
#   1. create_validation_layers() georeferences the expert-reviewed
#      validation labels and the model detections on the same tiles.
#   2. compute_threshold_results() matches detections to reference boxes
#      across confidence thresholds, selects the threshold that maximizes
#      F1 score, and records the result in the ModelPredictions table.
#
# Outputs:
#   data/<survey>/validate/<survey>_validation.gpkg
#   data/<survey>/validate/<survey>_threshold_results.csv
#   figs/validation/<survey>_precision_recall.jpg, <survey>_FScores.jpg
#
# Requires AWS credentials with read access to the bucket. Run from the
# project root.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/validation_functions.R")

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
# AWS region must be set before any S3 or GDAL /vsis3/ access
Sys.setenv(AWS_DEFAULT_REGION = "us-east-2", AWS_REGION = "us-east-2")

bucket      <- "deju-penguinscience"
base_prefix <- "PenguinCounting"
db_name     <- "data/UAVSurveys.db"

colony     <- "bird"
species    <- "adpe"
date       <- "2025-12-01"
model_name <- "ADPE_20250804_adult_sit"

# Lowest threshold evaluated; equal to the confidence threshold used at
# inference, below which no detections were retained
min_thresh <- 0.10

# Optional: names of the model's training tiles, to confirm that no
# validation tile was used in training
training_tiles <- NULL
# training_tiles <- tools::file_path_sans_ext(
#   list.files("training_data/adult_20250804/images"))

# --------------------------------------------------------------------
# Run
# --------------------------------------------------------------------
create_validation_layers(db_name = db_name, colony = colony,
                         species = species, date = date,
                         model_name = model_name, bucket = bucket,
                         base_prefix = base_prefix,
                         training_tiles = training_tiles)

compute_threshold_results(db_name = db_name, colony = colony,
                          species = species, date = date,
                          model_name = model_name, min_thresh = min_thresh)
