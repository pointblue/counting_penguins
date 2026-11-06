# --------------------------------------------------------------------
# summarize_threshold_performance.R
# Summarizes the survey-specific confidence thresholds and detection
# performance reported in Results Section 3.3 and Table S4 (Pipeline
# Step 5). For each survey processed with the deployed model, the
# script recomputes precision, recall, and F1 score on the
# expert-reviewed threshold-selection tiles at confidence thresholds
# from 0.10 to 1.00, using every tile sampled for review (including
# tiles with no penguins, so that false positives on them are counted),
# and selects the F1-maximizing threshold (ties go to the highest
# threshold). Matching follows Pipeline Step 5 (functions in
# validation_functions.R): one-to-one greedy assignment at IoU >= 0.5.
# Matching is done in each tile's pixel coordinates, so no
# georeferencing or cloud storage access is needed.
#
# The recomputed threshold is compared with the threshold recorded in
# the ModelPredictions table, which is the one applied in spatial
# filtering (Step 6); any survey where the two differ is listed.
#
# Reported:
#   - number of tiles reviewed per survey and in total
#   - selected thresholds: range, mean, and standard error
#   - F1 at the selected threshold: range, mean, and standard error
#   - Table S4: F1 for surveys from training years (2018-2023) and
#     later surveys (2024-2025): number of surveys, mean, and range
#
# Inputs:  data/UAVSurveys.db
#          data/<survey>/validate/reviewed*.csv     makesense.ai export
#          data/<survey>/validate/tiles/*.jpg       tiles sampled for review
#          data/<survey>/predict/counts/<model>/labels/<tile>.txt
#          code/validation_functions.R
# Outputs: data/threshold_performance_by_survey.csv
#          data/threshold_performance_curves.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")
source("code/validation_functions.R")   # read_makesense_csv(), threshold_counts()

thresholds  <- round(seq(0.10, 1, by = 0.01), 2)
last_training_year <- 2023   # training tiles were drawn from 2018-2023 surveys

# --------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------
# YOLO detections for the given tiles as pixel boxes, using each tile's
# dimensions from the review export (edge tiles can be smaller)
read_pred_px <- function(label_dir, tiles, dims) {
  files <- file.path(label_dir, paste0(tiles, ".txt"))
  out <- lapply(which(file.exists(files)), function(i) {
    x <- readLines(files[i], warn = FALSE)
    x <- x[nzchar(trimws(x))]
    if (length(x) == 0) return(NULL)
    m <- matrix(as.numeric(unlist(strsplit(trimws(x), "\\s+"))), ncol = 6, byrow = TRUE)
    data.frame(tileName = tiles[i], x = m[, 2], y = m[, 3], w = m[, 4], h = m[, 5],
               conf = m[, 6])
  })
  p <- do.call(rbind, out)
  if (is.null(p)) return(NULL)
  p %>%
    left_join(dims, by = "tileName") %>%
    mutate(tile_w = coalesce(tile_w, 512), tile_h = coalesce(tile_h, 256),
           xmin = (x - w / 2) * tile_w, xmax = (x + w / 2) * tile_w,
           ymin = (y - h / 2) * tile_h, ymax = (y + h / 2) * tile_h) %>%
    select(tileName, conf, xmin, xmax, ymin, ymax)
}

# Precision, recall, and F1 at each threshold, and the F1-optimal row
select_threshold <- function(counts) {
  curve <- counts %>%
    mutate(precision = tp_all / (tp_all + fp_all),
           recall    = tp_all / (tp_all + fn_all),
           F1        = 2 * precision * recall / (precision + recall))
  best <- curve %>% filter(!is.na(F1), F1 == max(F1, na.rm = TRUE)) %>%
    slice_max(conf_thresh, n = 1)
  list(curve = curve, best = best)
}

# --------------------------------------------------------------------
# Recompute the selected threshold for each survey
# --------------------------------------------------------------------
con <- dbConnect(SQLite(), db_name)
recorded <- dbGetQuery(con, "
  SELECT DISTINCT SurveyId, Threshold FROM ModelPredictions
  WHERE ModelName = ? ORDER BY SurveyId", params = list(model_name))
dbDisconnect(con)
if (any(duplicated(recorded$SurveyId))) stop("More than one recorded threshold for a survey")

curves <- list()
by_survey <- do.call(rbind, lapply(recorded$SurveyId, function(s) {
  message("Processing ", s)
  vdir <- file.path("data", s, "validate")
  tile_dir <- file.path(vdir, "tiles")
  if (!dir.exists(tile_dir)) stop("Folder of sampled tiles not found: ", tile_dir)

  # Reviewed boxes in tile pixel coordinates
  valids <- read_makesense_csv(vdir) %>%
    transmute(tileName, xmin = bbox_x, xmax = bbox_x + bbox_width,
              ymin = bbox_y, ymax = bbox_y + bbox_height,
              tile_w = image_width, tile_h = image_height)
  dims <- distinct(valids, tileName, tile_w, tile_h)

  # Every tile sampled for review, including tiles with no penguins
  sampled <- sub("\\.jpg$", "", list.files(tile_dir, pattern = "\\.jpg$", ignore.case = TRUE),
                 ignore.case = TRUE)
  not_in_sample <- setdiff(unique(valids$tileName), sampled)
  if (length(not_in_sample) > 0) {
    warning(s, ": ", length(not_in_sample), " reviewed tiles not in the sampled-tile folder")
  }
  tiles <- union(sampled, unique(valids$tileName))

  preds <- read_pred_px(file.path(counts_dir(s), "labels"), tiles, dims)
  sel <- select_threshold(threshold_counts(preds, valids, thresholds))
  curves[[s]] <<- mutate(sel$curve, SurveyId = s)

  data.frame(SurveyId = s,
             tiles_reviewed = length(tiles),
             tiles_with_penguins = length(unique(valids$tileName)),
             reviewed_boxes = nrow(valids),
             threshold = sel$best$conf_thresh,
             precision = sel$best$precision,
             recall = sel$best$recall,
             F1 = sel$best$F1)
})) %>%
  left_join(rename(recorded, threshold_recorded = Threshold), by = "SurveyId") %>%
  mutate(colony = colony_code(SurveyId), year = survey_year(SurveyId),
         Colony = unname(colony_names[colony]),
         period = ifelse(year <= last_training_year, "2018-2023 (training years)",
                         "2024-2025 (not in training)"),
         matches_recorded = abs(threshold - threshold_recorded) < 1e-9)

by_survey %>% select(Colony, year, tiles_reviewed, threshold, threshold_recorded,
                     precision, recall, F1) %>%
  mutate(across(c(precision, recall, F1), ~ round(.x, 3))) %>%
  print(row.names = FALSE)

if (!all(by_survey$matches_recorded)) {
  warning("Recomputed threshold differs from the recorded threshold for: ",
          paste(by_survey$SurveyId[!by_survey$matches_recorded], collapse = ", "))
}

# --------------------------------------------------------------------
# Summaries
# --------------------------------------------------------------------
se <- function(x) sd(x) / sqrt(length(x))
cat(sprintf("\nTiles reviewed: %d in total (%d to %d per survey) across %d surveys\n",
            sum(by_survey$tiles_reviewed), min(by_survey$tiles_reviewed),
            max(by_survey$tiles_reviewed), nrow(by_survey)))
cat(sprintf("Selected threshold: %.2f to %.2f (mean %.2f, SE %.2f)\n",
            min(by_survey$threshold), max(by_survey$threshold),
            mean(by_survey$threshold), se(by_survey$threshold)))
cat(sprintf("F1 at selected threshold: %.3f to %.3f (mean %.3f, SE %.3f)\n",
            min(by_survey$F1), max(by_survey$F1), mean(by_survey$F1), se(by_survey$F1)))

cat("\nTable S4: F1 at the selected threshold by period\n")
by_survey %>% group_by(period) %>%
  summarise(surveys = n(),
            F1 = sprintf("%.3f (%.3f-%.3f)", mean(F1), min(F1), max(F1)),
            .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)

# --------------------------------------------------------------------
# Save
# --------------------------------------------------------------------
write.csv(by_survey, "data/threshold_performance_by_survey.csv", row.names = FALSE)
write.csv(do.call(rbind, curves), "data/threshold_performance_curves.csv", row.names = FALSE)
message("Written: data/threshold_performance_by_survey.csv, data/threshold_performance_curves.csv")
