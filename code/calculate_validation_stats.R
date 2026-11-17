# --------------------------------------------------------------------
# calculate_validation_stats.R
# Selects the confidence threshold for one or more surveys (pipeline
# Step 5) using the functions in validation_functions.R:
#   1. create_validation_layers() georeferences the expert-reviewed
#      validation labels and the model detections on the same tiles,
#      including detections on reviewed tiles that contain no penguins.
#   2. compute_threshold_results() matches detections to reference boxes
#      across confidence thresholds, selects the threshold that maximizes
#      F1 score, and records the result in the ModelPredictions table.
#
# Surveys are named as <colony>_<species>_<date> (e.g.,
# bird_adpe_2025-12-01). Set surveys_to_run to one or more survey names,
# or to "all" to process every survey with predictions from the model and
# a validation folder. Failures are collected and reported at the end.
#
# Outputs, per survey:
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
model_name  <- "ADPE_20250804_adult_sit"

# One or more survey names, or "all"
# surveys_to_run <- c("all")
surveys_to_run <- c("bird_adpe_2023-11-30", "bird_adpe_2024-11-29", "bird_adpe_2025-12-01")

# Lowest threshold evaluated; equal to the confidence threshold used at
# inference, below which no detections were retained
min_thresh <- 0.10

# Optional: names of the model's training tiles, to confirm that no
# validation tile was used in training
training_tiles <- NULL
# training_tiles <- tools::file_path_sans_ext(
#   list.files("training_data/adult_20250804/images"))

# --------------------------------------------------------------------
# Surveys to process
# --------------------------------------------------------------------
if (identical(surveys_to_run, "all")) {
  con <- dbConnect(SQLite(), db_name)
  surveys_to_run <- dbGetQuery(con, "
    SELECT DISTINCT SurveyId FROM ModelPredictions WHERE ModelName = ?
    ORDER BY SurveyId", params = list(model_name))$SurveyId
  dbDisconnect(con)
  surveys_to_run <- surveys_to_run[dir.exists(file.path("data", surveys_to_run, "validate"))]
}
message("Surveys to process: ", length(surveys_to_run))

# --------------------------------------------------------------------
# Run
# --------------------------------------------------------------------
failures <- list()
for (survey in surveys_to_run) {
  # Survey name: <colony>_<species>_<date>
  parts   <- strsplit(survey, "_")[[1]]
  colony  <- parts[1]
  species <- parts[2]
  date    <- parts[3]
  message("\n--- ", survey, " ---")
  tryCatch({
    create_validation_layers(db_name = db_name, colony = colony,
                             species = species, date = date,
                             model_name = model_name, bucket = bucket,
                             base_prefix = base_prefix,
                             training_tiles = training_tiles)
    compute_threshold_results(db_name = db_name, colony = colony,
                              species = species, date = date,
                              model_name = model_name, min_thresh = min_thresh)
  }, error = function(e) {
    failures[[survey]] <<- conditionMessage(e)
    message("Error in ", survey, ": ", conditionMessage(e))
  })
}

# --------------------------------------------------------------------
# Report failures
# --------------------------------------------------------------------
if (length(failures) > 0) {
  message("\n", length(failures), " survey(s) failed:")
  for (s in names(failures)) message("  ", s, ": ", failures[[s]])
} else {
  message("\nAll ", length(surveys_to_run), " survey(s) processed.")
}