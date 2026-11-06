# --------------------------------------------------------------------
# clip_detections_to_nesting_areas_batch.R
# Clips de-duplicated, masked detections to reviewed nesting-area
# boundary polygons and records the number of candidate nests per
# orthomosaic (pipeline Step 6, second part).
#
# Boundaries are created by create_nesting_boundaries() in
# create_nesting_boundaries_clip.R and reviewed and edited by hand in GIS
# before this script is run. For each orthomosaic of each survey:
#   reads   GIS/<ortho>/masked_labels_cleaned.shp
#           GIS/<ortho>/<ortho>_nesting_area_boundaries.shp
#   writes  GIS/<ortho>/<ortho>_candidate_nests.shp
#   updates CalibratedCounts.CandidateNestTotal for the orthomosaic
#
# Only CandidateNestTotal is changed in CalibratedCounts; other columns
# (written by the calibration step) are left as they are and must be
# recalculated after the candidate nest total changes.
#
# Run from the project root.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(sf)
library(dplyr)
library(RSQLite)
library(stringr)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
db_name    <- "data/UAVSurveys.db"
model_name <- "ADPE_20250804_adult_sit"

# Surveys to process. NULL processes every survey with a ModelPredictions
# row for the model; to process selected surveys, list their IDs, e.g.
# surveys_to_run <- c("royd_adpe_2019-12-04")
surveys_to_run <- NULL

# --------------------------------------------------------------------
# Clip detections for one survey
# --------------------------------------------------------------------
clip_to_nesting_boundaries <- function(db_name, survey, model_name,
                                       boundary_filename_suffix = "_nesting_area_boundaries.shp") {
  db <- dbConnect(SQLite(), dbname = db_name)
  on.exit(dbDisconnect(db), add = TRUE)

  ortho_names <- dbGetQuery(db, "
    SELECT OrthomosaicName FROM SurveyImagery WHERE SurveyId = ?",
    params = list(survey))$OrthomosaicName
  if (length(ortho_names) == 0) {
    stop("No orthomosaics found in SurveyImagery for survey: ", survey)
  }
  cat("Survey:", survey, "-", length(ortho_names), "orthomosaic(s)\n")

  gis_dir <- file.path("data", survey, "predict", "counts", model_name, "GIS")
  all_results <- list()

  for (ortho_name in ortho_names) {
    ortho_dir_name <- tools::file_path_sans_ext(ortho_name)
    ortho_dir <- file.path(gis_dir, ortho_dir_name)
    boundary_path <- file.path(ortho_dir, paste0(ortho_dir_name, boundary_filename_suffix))
    if (!file.exists(boundary_path)) {
      stop("Boundary file not found (run create_nesting_boundaries() and ",
           "review the result first): ", boundary_path)
    }
    cat("\n  Clipping:", ortho_dir_name, "\n")

    boundaries  <- st_read(boundary_path, quiet = TRUE)
    predict_all <- st_read(file.path(ortho_dir, "masked_labels_cleaned.shp"),
                           quiet = TRUE)

    # Detections inside (or on the edge of) any boundary polygon
    inside_idx  <- lengths(st_intersects(predict_all, boundaries)) > 0
    pts_inside  <- predict_all[inside_idx, ]
    n_total <- nrow(predict_all); n_in <- nrow(pts_inside)
    pct_excluded <- if (n_total > 0) round((n_total - n_in) / n_total * 100, 2) else NA
    cat("  Total:", n_total, "| Inside:", n_in, "| Excluded:", n_total - n_in,
        "(", pct_excluded, "%)\n")

    st_write(pts_inside,
             file.path(ortho_dir, paste0(ortho_dir_name, "_candidate_nests.shp")),
             delete_layer = TRUE, quiet = TRUE)

    all_results[[ortho_dir_name]] <- data.frame(
      survey = survey, ortho = ortho_dir_name, total = n_total,
      nesting = n_in, excluded = n_total - n_in, pct_excluded = pct_excluded)

    # Record the candidate nest total. Only this column is changed; a new
    # row is added only if the orthomosaic has none yet.
    predict_id <- dbGetQuery(db, "
      SELECT PredictId FROM ModelPredictions
      WHERE SurveyId = ? AND ModelName = ? AND OrthomosaicName = ?",
      params = list(survey, model_name, ortho_name))$PredictId
    if (length(predict_id) != 1) {
      stop("Expected one ModelPredictions row for ", ortho_dir_name, " and ",
           model_name, "; found ", length(predict_id), ".")
    }
    n_upd <- dbExecute(db, "
      UPDATE CalibratedCounts SET CandidateNestTotal = ?
      WHERE PredictId = ?", params = list(n_in, predict_id))
    if (n_upd == 0) {
      dbExecute(db, "
        INSERT INTO CalibratedCounts
          (PredictId, SurveyId, OrthomosaicName, CandidateNestTotal)
        VALUES (?, ?, ?, ?)",
        params = list(predict_id, survey, ortho_name, n_in))   # name as in SurveyImagery
    } else if (n_upd > 1) {
      warning(n_upd, " CalibratedCounts rows share PredictId ", predict_id, ".")
    }
    cat("  CandidateNestTotal:", n_in, "recorded in CalibratedCounts\n")
  }

  summary_df <- bind_rows(all_results)
  print(summary_df, row.names = FALSE)
  invisible(summary_df)
}

# --------------------------------------------------------------------
# Run
# --------------------------------------------------------------------
con <- dbConnect(SQLite(), dbname = db_name)
surveys <- dbGetQuery(con, "
  SELECT DISTINCT SurveyId FROM ModelPredictions WHERE ModelName = ?
  ORDER BY SurveyId", params = list(model_name))$SurveyId
dbDisconnect(con)
if (!is.null(surveys_to_run)) {
  missing <- setdiff(surveys_to_run, surveys)
  if (length(missing) > 0) stop("Not in ModelPredictions: ", paste(missing, collapse = ", "))
  surveys <- surveys_to_run
}

failures <- character(0)
for (s in surveys) {
  cat("\n============================================================\n")
  result <- tryCatch(clip_to_nesting_boundaries(db_name, s, model_name),
                     error = function(e) {
                       message("Failed for ", s, ": ", conditionMessage(e))
                       failures <<- c(failures, s)
                     })
}
if (length(failures) > 0) {
  stop(length(failures), " survey(s) failed: ", paste(failures, collapse = ", "))
}
