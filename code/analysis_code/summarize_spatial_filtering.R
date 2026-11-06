# --------------------------------------------------------------------
# summarize_spatial_filtering.R
# Summarizes the reduction of raw detections to candidate nests through
# confidence thresholding and spatial filtering (Pipeline Steps 5-6),
# as reported for the 2025 surveys in Results Section 3.4. For each
# survey:
#   raw               all detections from inference (confidence > 0.10)
#   raw_at_threshold  detections with confidence at or above the
#                     survey's selected threshold
#   cleaned           detections after de-duplication and the isolation
#                     filter (MaskedCleaned, ModelPredictions)
#   candidate_nests   detections after clipping to the reviewed
#                     nesting-area boundaries (CandidateNestTotal,
#                     CalibratedCounts)
# and the percent removed at each stage and overall.
#
# Raw detections are read from each orthomosaic's
# combined_predictions.csv and summed across a survey's orthomosaics.
# Surveys with one orthomosaic may store this file at the survey level;
# surveys with more than one must have one file per orthomosaic, since a
# survey-level file there may not reflect the final processing run.
#
# Inputs:  data/UAVSurveys.db
#          data/<survey>/predict/counts/<model>/csv/<ortho>/combined_predictions.csv
# Output:  data/detection_attrition_<report_year>.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")
library(data.table)

report_year <- 2025
conf_col    <- "confidence"

# --------------------------------------------------------------------
# Raw detections for one orthomosaic
# --------------------------------------------------------------------
predictions_file <- function(survey_id, ortho, n_ortho) {
  base <- file.path(counts_dir(survey_id), "csv")
  f <- file.path(base, ortho, "combined_predictions.csv")
  if (file.exists(f)) return(f)
  f_survey <- file.path(base, "combined_predictions.csv")
  if (n_ortho == 1 && file.exists(f_survey)) return(f_survey)
  stop("No combined_predictions.csv for ", ortho, " in ", base)
}

# --------------------------------------------------------------------
# Detection counts at each stage, by survey
# --------------------------------------------------------------------
mp <- model_orthomosaics() %>% filter(year == report_year)
s  <- survey_totals(read_calibrated_counts()) %>% filter(year == report_year)

attrition <- do.call(rbind, lapply(split(mp, mp$SurveyId), function(o) {
  th <- unique(o$Threshold)
  if (length(th) != 1) stop("Orthomosaics of ", o$SurveyId[1], " have different thresholds")
  raw <- sapply(o$ortho, function(x) {
    p <- fread(predictions_file(o$SurveyId[1], x, nrow(o)))
    c(raw = nrow(p), raw_at_threshold = sum(p[[conf_col]] >= th))
  })
  data.frame(SurveyId = o$SurveyId[1], n_ortho = nrow(o), threshold = th,
             raw = sum(raw["raw", ]), raw_at_threshold = sum(raw["raw_at_threshold", ]),
             cleaned = sum(o$MaskedCleaned))
})) %>%
  left_join(s %>% select(SurveyId, Colony, candidate_nests = CandidateNests), by = "SurveyId") %>%
  mutate(pct_removed_threshold = 100 * (raw - raw_at_threshold) / raw,
         pct_removed_dedup_isolation = 100 * (raw_at_threshold - cleaned) / raw_at_threshold,
         pct_removed_clip = 100 * (cleaned - candidate_nests) / cleaned,
         pct_removed_total = 100 * (raw - candidate_nests) / raw) %>%
  relocate(Colony, .after = SurveyId)

attrition %>% mutate(across(starts_with("pct_"), ~ round(.x, 1))) %>%
  print(row.names = FALSE)

out_file <- sprintf("data/detection_attrition_%d.csv", report_year)
write.csv(attrition, out_file, row.names = FALSE)
message("Written: ", out_file)
