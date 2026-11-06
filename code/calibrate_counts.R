# --------------------------------------------------------------------
# calibrate_counts.R
# This script computes calibrated population estimates from a UAV-based
# penguin counting pipeline. It compares model detections to manual counts
# in a sample of grid cells to derive correction ratios, then applies those
# to colony-wide candidate nest totals.
#
# WORKFLOW (after observers complete manual counts):
#   1. Read in observer shapefiles and tally manual counts per sampled cell.
#   2. Compute three ratio estimators:
#        R_ManualCN_ModelCN = manual candidate nests / model candidate nests
#        R_Occ_ManCN        = manual occupied territories / manual candidate nests
#        R_TI_ManCN         = manual total individuals / manual candidate nests
#   3. Apply R_ManualCN_ModelCN to the colony's model candidate nest total to get an
#      adjusted candidate nest total (AdjCNTotal). The bias test for R_ManualCN_ModelCN
#      is reported as a diagnostic only; the adjustment is always applied.
#   4. Apply R_Occ_ManCN and R_TI_ManCN to AdjCNTotal to derive occupied territory and
#      total individual estimates (EstOccTotal and EstTITotal).
#   5. Combine with ground count subcolony data to estimate active nests,
#      via two independent pathways (from occupied and from total individuals).
#
# INTER-OBSERVER COMPARISON:
#   For each ratio, the two observers' estimates are compared using a z-test
#   on the linearized ratio estimator variances. Percent difference is also
#   reported. Significant disagreement (p < 0.05) is recorded as ObsDiff_*
#   so problematic surveys can be flagged for review.
#
# ERROR PROPAGATION:
#   - SE for EstOccTotal and EstTITotal uses "direct" ratio variances
#     (manual_n / model_cn, ti_manual / model_cn). These collapse the chained
#     R_ManualCN_ModelCN x R_Occ_ManCN (or R_ManualCN_ModelCN x R_TI_ManCN) into 
#     a single ratio whose variance correctly captures the joint uncertainty.
#   - SE for ActiveFromOcc and ActiveFromTotal uses delta-method propagation
#     combining calibration uncertainty with ground count ratio uncertainty:
#     Var(X * Y) / (X * Y)^2 ~= Var(X)/X^2 + Var(Y)/Y^2 (assuming independence).
#
# INPUTS (data/<survey>/calibration_counts_survey_names/<survey>_*):
#   assessment_grid_all.shp, selected_cells_for_counting.shp and
#   candidate_nests_model_selected_cells.shp (from
#   create_calibration_files_batch.R), and the observers' point layers
#   candidate_nests_, occupied_territories_ and total_individuals_
#   Observer_<1|2>.shp; observer initials and times from
#   data/CalibrationCountTracking.csv; candidate nest totals from
#   CalibratedCounts; ground counts from GroundCounts.
#
# MODEL COUNTS IN SAMPLED CELLS:
#   The model candidate nests in the sampled cells are checked against the
#   current <ortho>_candidate_nests.shp files. If they differ (e.g., after
#   a threshold change and rerun of consolidation and clipping), the
#   script stops; set refresh_snapshot = TRUE to back up the saved layer
#   and replace it with the current candidate nests.
#
# Points are counted in every sampled cell they intersect, so a point on
# a boundary shared by two sampled cells is counted in both.
#
# Run from the project root.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(sf)
library(dplyr)
library(RSQLite)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
db_name    <- "data/UAVSurveys.db"
model_name <- "ADPE_20250804_adult_sit"

# Surveys to process. NULL processes every survey with a ModelPredictions
# row for the model; to process selected surveys, list their IDs, e.g.
# surveys_to_run <- c("royd_adpe_2019-12-04")
surveys_to_run <- NULL

# Replace a saved model-count layer that no longer matches the current
# candidate nests (the previous layer is backed up). See header.
refresh_snapshot <- FALSE


# --------------------------------------------------------------------
# Function; runs the full calibration workflow for one survey
# Arguments:
#    survey_name : SurveyId string, e.g. "croz_adpe_2024-11-27"
#    model_name  : model identifier matching ModelPredictions.ModelName
#    db_name     : path to the SQLite database
# --------------------------------------------------------------------
calibrate_counts <- function(survey_name, model_name, db_name,
                             refresh_snapshot = FALSE) {
  
  cat("\n============================================================\n")
  cat("Processing:", survey_name, "|", model_name, "\n")
  cat("============================================================\n")
  
  # --------------------------------------------------------------------
  # Pull setup info from the database
  # --------------------------------------------------------------------
  con <- dbConnect(SQLite(), dbname = db_name)
  
  # Orthomosaics that make up this survey (Cape Bird has two or three)
  ortho_names <- dbGetQuery(con, "
    SELECT OrthomosaicName FROM SurveyImagery WHERE SurveyId = ?",
    params = list(survey_name))$OrthomosaicName %>% tools::file_path_sans_ext()

  # total_clipped is the survey-wide model candidate nest count for this
  # model, stored per orthomosaic in CalibratedCounts.CandidateNestTotal
  # by clip_detections_to_nesting_areas_batch.R
  total_clipped <- dbGetQuery(con, "
    SELECT SUM(cc.CandidateNestTotal)
    FROM CalibratedCounts cc
    JOIN ModelPredictions mp ON mp.PredictId = cc.PredictId
    WHERE cc.SurveyId = ? AND mp.ModelName = ?",
    params = list(survey_name, model_name))[[1]]
  
  dbDisconnect(con)
  
  output_dir <- paste0("data/", survey_name, "/calibration_counts_survey_names")
  gis_dir    <- paste0("data/", survey_name, "/predict/counts/", model_name, "/GIS/")
  
  # Read the full assessment grid only for the cell count N, used as the
  # population size in finite population corrections below.
  grid <- st_read(file.path(output_dir, paste0(survey_name, "_assessment_grid_all.shp")),
                  quiet = TRUE)
  
  if (is.na(total_clipped) || total_clipped == 0) {
    stop("CandidateNestTotal is 0 or missing in CalibratedCounts for survey '", survey_name,
         "'; run clip_detections_to_nesting_areas_batch.R first.")
  }
  cat("Candidate nest total (from CalibratedCounts):", total_clipped, "\n")
  
  # --------------------------------------------------------------------
  # Observer initials and counting times from the tracking CSV
  # --------------------------------------------------------------------
  tracking <- read.csv("data/CalibrationCountTracking.csv", stringsAsFactors = FALSE)
  tracking_row <- tracking[tracking$SurveyId == survey_name, ]
  
  if (nrow(tracking_row) == 0) {
    stop("No row found in CalibrationCountTracking.csv for SurveyId '", survey_name, "'")
  }
  if (nrow(tracking_row) > 1) {
    warning("Multiple rows found in CalibrationCountTracking.csv for SurveyId '", survey_name,
            "' — using the first.")
    tracking_row <- tracking_row[1, ]
  }
  
  observer1_initials    <- tracking_row$Observer1
  observer2_initials    <- tracking_row$Observer2
  obs1_time_to_complete <- tracking_row$Obs1TimeToComplete
  obs2_time_to_complete <- tracking_row$Obs2TimeToComplete
  
  cat("Observers:", observer1_initials, "/", observer2_initials, "\n")
  
  
  # --------------------------------------------------------------------
  # Read in all observer layers and compute manual counts per cell
  # --------------------------------------------------------------------
  # We tally points per sampled cell for four quantities:
  #    model_cn  : model candidate nests in cell (from updated detections)
  #    cn_manual : observer-marked candidate nests
  #    manual_n  : observer-marked occupied territories
  #    ti_manual : observer-marked total individuals
  # --------------------------------------------------------------------
  
  # Sampled cells (deterministic per-survey cell selection from create_calibration_files).
  sampled_counted <- st_read(file.path(output_dir, paste0(survey_name, "_selected_cells_for_counting.shp")),
                             quiet = TRUE)
  
  # Model candidate nests within the sampled cells. The saved layer is
  # checked against the current candidate nests so that counts made at an
  # earlier threshold are not used by mistake.
  snapshot_path <- file.path(output_dir, paste0(survey_name, "_candidate_nests_model_selected_cells.shp"))
  model_cn_points <- st_read(snapshot_path, quiet = TRUE)
  current_cn <- do.call(rbind, lapply(ortho_names, function(o) {
    st_read(file.path(gis_dir, o, paste0(o, "_candidate_nests.shp")), quiet = TRUE)
  }))
  current_in_cells <- current_cn[lengths(st_intersects(current_cn, sampled_counted)) > 0, ]
  same_points <- nrow(current_in_cells) == nrow(model_cn_points) &&
    isTRUE(all.equal(sort(st_coordinates(current_in_cells)[, 1]),
                     sort(st_coordinates(model_cn_points)[, 1])))
  if (!same_points) {
    if (!refresh_snapshot) {
      stop("Saved model candidate nests in the sampled cells (", nrow(model_cn_points),
           ") do not match the current candidate nests (", nrow(current_in_cells),
           "). Set refresh_snapshot = TRUE to update the saved layer.")
    }
    bak <- file.path(output_dir, paste0("previous_model_selected_cells_",
                                        format(Sys.time(), "%Y%m%d_%H%M%S")))
    dir.create(bak)
    old_files <- list.files(output_dir, full.names = TRUE, pattern = paste0(
      "^", survey_name, "_candidate_nests_model_selected_cells\\."))
    file.copy(old_files, bak)
    st_write(current_in_cells, snapshot_path, delete_layer = TRUE, quiet = TRUE)
    model_cn_points <- current_in_cells
    cat("Saved model candidate nests updated (", nrow(model_cn_points),
        " points); previous layer kept in ", bak, "\n", sep = "")
  }
  sampled_counted$model_cn <- lengths(st_intersects(sampled_counted, model_cn_points))
  
  cat("Model candidate nests in sampled cells:", sum(sampled_counted$model_cn), "\n")
  
  # Manual candidate nests (combined across both observers; each observer
  # counts a disjoint subset of cells, so binding rows then intersecting works).
  cn_obs1_pts <- st_read(file.path(output_dir, paste0(survey_name, "_candidate_nests_Observer_1.shp")), quiet = TRUE)
  cn_obs2_pts <- st_read(file.path(output_dir, paste0(survey_name, "_candidate_nests_Observer_2.shp")), quiet = TRUE)
  cn_manual_points <- bind_rows(cn_obs1_pts, cn_obs2_pts)
  sampled_counted$cn_manual <- lengths(st_intersects(sampled_counted, cn_manual_points))
  
  # Manual occupied territories
  obs1_pts <- st_read(file.path(output_dir, paste0(survey_name, "_occupied_territories_Observer_1.shp")), quiet = TRUE)
  obs2_pts <- st_read(file.path(output_dir, paste0(survey_name, "_occupied_territories_Observer_2.shp")), quiet = TRUE)
  manual_points <- bind_rows(obs1_pts, obs2_pts)
  sampled_counted$manual_n <- lengths(st_intersects(sampled_counted, manual_points))
  
  # Manual total individuals
  ti_obs1_pts <- st_read(file.path(output_dir, paste0(survey_name, "_total_individuals_Observer_1.shp")), quiet = TRUE)
  ti_obs2_pts <- st_read(file.path(output_dir, paste0(survey_name, "_total_individuals_Observer_2.shp")), quiet = TRUE)
  ti_manual_points <- bind_rows(ti_obs1_pts, ti_obs2_pts)
  sampled_counted$ti_manual <- lengths(st_intersects(sampled_counted, ti_manual_points))
  
  cat("Manual counts per observer:\n")
  cat("   Total candidate nests:     ", nrow(cn_manual_points), "\n")
  cat("   Total occupied territories:", nrow(manual_points), "\n")
  cat("   Total individuals:         ", nrow(ti_manual_points), "\n")
  
  # Biological sanity: candidate nests <= occupied territories <= total individuals.
  if (any(sampled_counted$cn_manual > sampled_counted$manual_n)) {
    warning("Some cells have more candidate nests than occupied territories — check data.")
  }
  if (any(sampled_counted$ti_manual < sampled_counted$manual_n)) {
    warning("Some cells have fewer total individuals than occupied territories — check data.")
  }
  
  # Zero-occupied cells check
  n_zero_occ <- sum(sampled_counted$manual_n == 0)
  if (n_zero_occ > 0) {
    cat("Warning:", n_zero_occ, "cells have 0 occupied territory points — verify these were counted.\n")
  }
  
  # Population and sample sizes used for finite population correction below.
  N   <- nrow(grid)
  n   <- nrow(sampled_counted)
  fpc <- 1 - (n / N)
  
  
  # --------------------------------------------------------------------
  # COMPARISON 1: Model candidate nests vs manual candidate nests
  # --------------------------------------------------------------------
  # R_ManualCN_ModelCN = sum(cn_manual) / sum(model_cn) over sampled cells.
  # --------------------------------------------------------------------
  
  cat("\n\n========== COMPARISON 1: Candidate Nest Detection ==========\n")
  
  cat("Manual candidate nests:", sum(sampled_counted$cn_manual), "\n")
  cat("Model candidate nests in sampled cells:", sum(sampled_counted$model_cn), "\n")
  
  sampled_counted <- sampled_counted %>%
    mutate(ratio_cn = case_when(
      cn_manual == 0 & model_cn == 0 ~ 1,
      model_cn == 0                  ~ NA_real_,
      TRUE                           ~ cn_manual / model_cn
    ))  
  
  # --------------------------------------------------------------------
  # Inter-observer comparison: z-test on per-observer ratio estimators
  # --------------------------------------------------------------------
  cn_obs1 <- sampled_counted %>% filter(observer == "Observer_1")
  cn_obs2 <- sampled_counted %>% filter(observer == "Observer_2")
  
  R_cn1 <- sum(cn_obs1$cn_manual) / sum(cn_obs1$model_cn)
  R_cn2 <- sum(cn_obs2$cn_manual) / sum(cn_obs2$model_cn)
  
  n1   <- nrow(cn_obs1); n2   <- nrow(cn_obs2)
  fpc1 <- 1 - (n1 / N);  fpc2 <- 1 - (n2 / N)
  e_cn1 <- cn_obs1$cn_manual - R_cn1 * cn_obs1$model_cn
  e_cn2 <- cn_obs2$cn_manual - R_cn2 * cn_obs2$model_cn
  var_R_cn1 <- (fpc1 / (n1 * mean(cn_obs1$model_cn)^2)) * sum(e_cn1^2) / (n1 - 1)
  var_R_cn2 <- (fpc2 / (n2 * mean(cn_obs2$model_cn)^2)) * sum(e_cn2^2) / (n2 - 1)
  
  cn_obs_z        <- (R_cn1 - R_cn2) / sqrt(var_R_cn1 + var_R_cn2)
  cn_obs_p        <- 2 * pnorm(-abs(cn_obs_z))
  cn_obs_pct_diff <- (R_cn1 - R_cn2) / ((R_cn1 + R_cn2) / 2) * 100
  
  cat("\nInter-observer comparison (R_ManualCN_ModelCN):\n")
  cat("  Observer_1 R_cn:", round(R_cn1, 4), "\n")
  cat("  Observer_2 R_cn:", round(R_cn2, 4), "\n")
  cat("  % difference:", round(cn_obs_pct_diff, 2), "%\n")
  cat("  Z-test: z =", round(cn_obs_z, 3), ", p =", round(cn_obs_p, 4), "\n")
  if (cn_obs_p < 0.05) {
    cat("  => Observers are significantly different (p < 0.05) — investigate before proceeding.\n")
  } else {
    cat("  => No significant difference between observers (p >= 0.05).\n")
  }
  
  # --------------------------------------------------------------------
  # Combined R_ManualCN_ModelCN and its variance (used for AdjCNTotal and CN margin)
  # --------------------------------------------------------------------
  R_ManualCN_ModelCN <- sum(sampled_counted$cn_manual) / sum(sampled_counted$model_cn)
  cn_adj_total <- R_ManualCN_ModelCN * total_clipped
  
  sampled_counted$e_cn <- sampled_counted$cn_manual - R_ManualCN_ModelCN * sampled_counted$model_cn
  var_R_cn <- (fpc / (n * mean(sampled_counted$model_cn)^2)) *
    sum(sampled_counted$e_cn^2) / (n - 1)
  se_cn_total <- sqrt(var_R_cn) * total_clipped
  
  cat("\n--- R_ManualCN_ModelCN Ratio Estimator ---\n")
  cat("R_ManualCN_ModelCN (manual / model candidate nests):", round(R_ManualCN_ModelCN, 4), "\n")
  cat("Adjusted candidate nest total (AdjCNTotal):", round(cn_adj_total), "\n")
  cat("SE:", round(se_cn_total), "\n")
  cat("95% CI:", round(cn_adj_total - 1.96 * se_cn_total), "-",
      round(cn_adj_total + 1.96 * se_cn_total), "\n")
  
  # --------------------------------------------------------------------
  # Bias test: is R_ManualCN_ModelCN significantly different from 1?
  # --------------------------------------------------------------------
  z_cn <- (R_ManualCN_ModelCN - 1) / sqrt(var_R_cn)
  p_cn <- 2 * pnorm(-abs(z_cn))
  cat("\nBias test (H0: R_ManualCN_ModelCN = 1): z =", round(z_cn, 3), ", p =", round(p_cn, 4), "\n")
  if (p_cn < 0.05) {
    cat("  => Bias is statistically significant — recorded as CNBiasSig = 1.\n")
  } else {
    cat("  => Bias is NOT statistically significant — recorded as CNBiasSig = 0.\n")
  }
  
  cn_final_estimate <- cn_adj_total
  cn_pct_margin <- 1.96 * se_cn_total / cn_final_estimate * 100
  cat("\nFinal AdjCNTotal estimate: ", round(cn_final_estimate), " ± ",
      round(cn_pct_margin, 1), "% (95% CI)\n", sep = "")
  
  
  # --------------------------------------------------------------------
  # COMPARISON 2: Manual occupied territories per manual candidate nest
  # --------------------------------------------------------------------
  # R_Occ_ManCN converts candidate nests to occupied territories.
  # --------------------------------------------------------------------
  
  cat("\n\n========== COMPARISON 2: Occupied Territory Conversion ==========\n")
  
  sampled_counted <- sampled_counted %>%
    mutate(ratio_occ = case_when(
      manual_n == 0 & cn_manual == 0 ~ 1,
      cn_manual == 0                 ~ NA_real_,
      TRUE                           ~ manual_n / cn_manual
    ))
  
  # --------------------------------------------------------------------
  # Inter-observer comparison: z-test on per-observer ratio estimators
  # --------------------------------------------------------------------
  obs1 <- sampled_counted %>% filter(observer == "Observer_1")
  obs2 <- sampled_counted %>% filter(observer == "Observer_2")
  
  R_occ1 <- sum(obs1$manual_n) / sum(obs1$cn_manual)
  R_occ2 <- sum(obs2$manual_n) / sum(obs2$cn_manual)
  
  n1   <- nrow(obs1); n2   <- nrow(obs2)
  fpc1 <- 1 - (n1 / N); fpc2 <- 1 - (n2 / N)
  e_occ1 <- obs1$manual_n - R_occ1 * obs1$cn_manual
  e_occ2 <- obs2$manual_n - R_occ2 * obs2$cn_manual
  var_R_occ1 <- (fpc1 / (n1 * mean(obs1$cn_manual)^2)) * sum(e_occ1^2) / (n1 - 1)
  var_R_occ2 <- (fpc2 / (n2 * mean(obs2$cn_manual)^2)) * sum(e_occ2^2) / (n2 - 1)
  
  obs_z        <- (R_occ1 - R_occ2) / sqrt(var_R_occ1 + var_R_occ2)
  obs_p        <- 2 * pnorm(-abs(obs_z))
  obs_pct_diff <- (R_occ1 - R_occ2) / ((R_occ1 + R_occ2) / 2) * 100
  
  cat("\nInter-observer comparison (R_Occ_ManCN):\n")
  cat("  Observer_1 R_occ:", round(R_occ1, 4), "\n")
  cat("  Observer_2 R_occ:", round(R_occ2, 4), "\n")
  cat("  % difference:", round(obs_pct_diff, 2), "%\n")
  cat("  Z-test: z =", round(obs_z, 3), ", p =", round(obs_p, 4), "\n")
  if (obs_p < 0.05) {
    cat("  => Observers are significantly different (p < 0.05) — investigate before proceeding.\n")
  } else {
    cat("  => No significant difference between observers (p >= 0.05).\n")
  }
  
  # --------------------------------------------------------------------
  # Conversion-factor ratio (manual occ / manual CN); used for reporting
  # --------------------------------------------------------------------
  R_Occ_ManCN <- sum(sampled_counted$manual_n) / sum(sampled_counted$cn_manual)
  occ_total <- R_Occ_ManCN * cn_final_estimate
  
  sampled_counted$e_occ <- sampled_counted$manual_n - R_Occ_ManCN * sampled_counted$cn_manual
  var_R_occ <- (fpc / (n * mean(sampled_counted$cn_manual)^2)) *
    sum(sampled_counted$e_occ^2) / (n - 1)
  
  # --------------------------------------------------------------------
  # Direct ratio (manual occ / model CN); used for SE propagation
  # --------------------------------------------------------------------
  R_occ_direct <- sum(sampled_counted$manual_n) / sum(sampled_counted$model_cn)
  e_occ_direct <- sampled_counted$manual_n - R_occ_direct * sampled_counted$model_cn
  var_R_occ_direct <- (fpc / (n * mean(sampled_counted$model_cn)^2)) *
    sum(e_occ_direct^2) / (n - 1)
  se_occ_total <- sqrt(var_R_occ_direct) * total_clipped
  
  cat("\n--- R_Occ_ManCN Ratio Estimator ---\n")
  cat("R_Occ_ManCN (occupied territories / manual candidate nests):", round(R_Occ_ManCN, 4), "\n")
  cat("R_occ_direct (occupied territories / model CN, used for SE):",
      round(R_occ_direct, 4), "\n")
  cat("Occupied territory total (EstOccTotal):", round(occ_total), "\n")
  cat("SE (propagated through R_ManualCN_ModelCN × R_Occ_ManCN):", round(se_occ_total), "\n")
  cat("95% CI:", round(occ_total - 1.96 * se_occ_total), "-",
      round(occ_total + 1.96 * se_occ_total), "\n")
  
  final_estimate <- occ_total
  pct_margin_occ <- 1.96 * se_occ_total / final_estimate * 100
  cat("\nEstOccTotal: ", round(final_estimate), " ± ",
      round(pct_margin_occ, 1), "% (95% CI)\n", sep = "")
  cat("R_Occ_ManCN: ", round(R_Occ_ManCN, 4), " (95% CI: ",
      round(R_Occ_ManCN - 1.96 * sqrt(var_R_occ), 4), " - ",
      round(R_Occ_ManCN + 1.96 * sqrt(var_R_occ), 4), ")\n", sep = "")
  
  
  # --------------------------------------------------------------------
  # COMPARISON 3: Manual total individuals per manual candidate nest
  # --------------------------------------------------------------------
  # R_TI_ManCN is a biological conversion factor (manual total / manual CN)
  # --------------------------------------------------------------------
  
  cat("\n\n========== COMPARISON 3: Total Individual Conversion ==========\n")
  
  # --------------------------------------------------------------------
  # Inter-observer comparison: z-test on per-observer ratio estimators
  # --------------------------------------------------------------------
  ti_obs1 <- sampled_counted %>% filter(observer == "Observer_1")
  ti_obs2 <- sampled_counted %>% filter(observer == "Observer_2")
  
  R_ti1 <- sum(ti_obs1$ti_manual) / sum(ti_obs1$cn_manual)
  R_ti2 <- sum(ti_obs2$ti_manual) / sum(ti_obs2$cn_manual)
  
  n1   <- nrow(ti_obs1); n2   <- nrow(ti_obs2)
  fpc1 <- 1 - (n1 / N); fpc2 <- 1 - (n2 / N)
  e_ti1 <- ti_obs1$ti_manual - R_ti1 * ti_obs1$cn_manual
  e_ti2 <- ti_obs2$ti_manual - R_ti2 * ti_obs2$cn_manual
  var_R_ti1 <- (fpc1 / (n1 * mean(ti_obs1$cn_manual)^2)) * sum(e_ti1^2) / (n1 - 1)
  var_R_ti2 <- (fpc2 / (n2 * mean(ti_obs2$cn_manual)^2)) * sum(e_ti2^2) / (n2 - 1)
  
  ti_obs_z        <- (R_ti1 - R_ti2) / sqrt(var_R_ti1 + var_R_ti2)
  ti_obs_p        <- 2 * pnorm(-abs(ti_obs_z))
  ti_obs_pct_diff <- (R_ti1 - R_ti2) / ((R_ti1 + R_ti2) / 2) * 100
  
  cat("\nInter-observer comparison (R_TI_ManCN):\n")
  cat("  Observer_1 R_ti:", round(R_ti1, 4), "\n")
  cat("  Observer_2 R_ti:", round(R_ti2, 4), "\n")
  cat("  % difference:", round(ti_obs_pct_diff, 2), "%\n")
  cat("  Z-test: z =", round(ti_obs_z, 3), ", p =", round(ti_obs_p, 4), "\n")
  if (ti_obs_p < 0.05) {
    cat("  => Observers are significantly different (p < 0.05) — investigate before proceeding.\n")
  } else {
    cat("  => No significant difference between observers (p >= 0.05).\n")
  }
  
  # --------------------------------------------------------------------
  # Conversion-factor ratio (manual total / manual CN); for reporting
  # --------------------------------------------------------------------
  R_TI_ManCN <- sum(sampled_counted$ti_manual) / sum(sampled_counted$cn_manual)
  ti_estimate_total <- R_TI_ManCN * cn_final_estimate
  
  sampled_counted$e_ti <- sampled_counted$ti_manual - R_TI_ManCN * sampled_counted$cn_manual
  var_R_total <- (fpc / (n * mean(sampled_counted$cn_manual)^2)) *
    sum(sampled_counted$e_ti^2) / (n - 1)
  
  # --------------------------------------------------------------------
  # Direct ratio (manual total / model CN); used for SE propagation
  # --------------------------------------------------------------------
  R_ti_direct <- sum(sampled_counted$ti_manual) / sum(sampled_counted$model_cn)
  e_ti_direct <- sampled_counted$ti_manual - R_ti_direct * sampled_counted$model_cn
  var_R_ti_direct <- (fpc / (n * mean(sampled_counted$model_cn)^2)) *
    sum(e_ti_direct^2) / (n - 1)
  se_ti_total <- sqrt(var_R_ti_direct) * total_clipped
  
  cat("\n--- R_TI_ManCN Ratio Estimator ---\n")
  cat("R_TI_ManCN (total individuals / manual candidate nests):", round(R_TI_ManCN, 4), "\n")
  cat("R_ti_direct (total individuals / model CN, used for SE):", round(R_ti_direct, 4), "\n")
  cat("Estimated total individuals (EstTITotal):", round(ti_estimate_total), "\n")
  cat("SE (propagated through R_ManualCN_ModelCN × R_TI_ManCN):", round(se_ti_total), "\n")
  cat("95% CI:", round(ti_estimate_total - 1.96 * se_ti_total), "-",
      round(ti_estimate_total + 1.96 * se_ti_total), "\n")
  
  ti_final_estimate <- ti_estimate_total
  ti_pct_margin <- 1.96 * se_ti_total / ti_final_estimate * 100
  cat("\nEstTITotal: ", round(ti_final_estimate), " ± ",
      round(ti_pct_margin, 1), "% (95% CI)\n", sep = "")
  cat("R_TI_ManCN: ", round(R_TI_ManCN, 4), " (95% CI: ",
      round(R_TI_ManCN - 1.96 * sqrt(var_R_total), 4), " - ",
      round(R_TI_ManCN + 1.96 * sqrt(var_R_total), 4), ")\n", sep = "")
  
  
  # --------------------------------------------------------------------
  # Save calibration results to CalibratedCounts
  # --------------------------------------------------------------------
  
  con <- dbConnect(SQLite(), dbname = db_name)
  
  calibration_cols <- list(
    NCells               = "INTEGER",
    Observer1            = "TEXT",
    Observer2            = "TEXT",
    R_CN_Obs1            = "REAL",
    R_CN_Obs2            = "REAL",
    ObsPctDiff_CN     = "REAL",
    ObsDiff_CN        = "INTEGER",
    R_ManualCN_ModelCN   = "REAL",
    AdjCNTotal           = "INTEGER",
    AdjCNMoE             = "INTEGER",
    AdjCNCIPct           = "REAL",
    CNBiasSig            = "INTEGER",
    R_Occ_Obs1           = "REAL",
    R_Occ_Obs2           = "REAL",
    ObsDiff_Occ          = "INTEGER",
    ObsPctDiff_Occ       = "REAL",
    R_Occ_ManCN          = "REAL",
    EstOccTotal          = "INTEGER",
    OccMoE               = "INTEGER",
    OccCIPct             = "REAL",
    R_TI_Obs1            = "REAL",
    R_TI_Obs2            = "REAL",
    ObsDiff_TI           = "INTEGER",
    ObsPctDiff_TI        = "REAL",
    R_TI_ManCN           = "REAL",
    EstTITotal           = "INTEGER",
    TIMoE                = "INTEGER",
    TICIPct              = "REAL",
    Obs1Time             = "REAL",
    Obs2Time             = "REAL"
  )
  
  existing_cols <- dbGetQuery(con, "PRAGMA table_info(CalibratedCounts)") %>%
    pull(name)
  
  for (col in names(calibration_cols)) {
    if (!col %in% existing_cols) {
      dbExecute(con, paste("ALTER TABLE CalibratedCounts ADD COLUMN", col,
                           calibration_cols[[col]]))
    }
  }
  
  ortho_rows <- dbGetQuery(con, "
    SELECT cc.PredictId, cc.OrthomosaicName, cc.CandidateNestTotal
    FROM CalibratedCounts cc
    JOIN ModelPredictions mp ON mp.PredictId = cc.PredictId
    WHERE cc.SurveyId = ? AND mp.ModelName = ?",
    params = list(survey_name, model_name))
  
  if (nrow(ortho_rows) == 0) {
    warning("No rows found in CalibratedCounts for survey '", survey_name,
            "'; run clip_detections_to_nesting_areas_batch.R first.")
  } else {
    for (i in seq_len(nrow(ortho_rows))) {
      ortho_cn    <- ortho_rows$CandidateNestTotal[i]
      predict_id  <- ortho_rows$PredictId[i]
      ortho_name  <- ortho_rows$OrthomosaicName[i]
      
      ortho_cn_total <- round(R_ManualCN_ModelCN * ortho_cn)
      ortho_cn_final <- ortho_cn_total
      
      ortho_occ_total <- round(R_Occ_ManCN * ortho_cn_final)
      ortho_ti_total  <- round(R_TI_ManCN * ortho_cn_final)
      
      ortho_cn_moe  <- round(1.96 * sqrt(var_R_cn)         * ortho_cn)
      ortho_occ_moe <- round(1.96 * sqrt(var_R_occ_direct) * ortho_cn)
      ortho_ti_moe  <- round(1.96 * sqrt(var_R_ti_direct)  * ortho_cn)
      
      dbExecute(con, "
    UPDATE CalibratedCounts
    SET NCells              = ?,
        Observer1           = ?,
        Observer2           = ?,
        R_CN_Obs1           = ?,
        R_CN_Obs2           = ?,
        ObsPctDiff_CN       = ?,
        ObsDiff_CN          = ?,
        R_ManualCN_ModelCN  = ?,
        AdjCNTotal          = ?,
        AdjCNMoE            = ?,
        AdjCNCIPct          = ?,
        CNBiasSig           = ?,
        R_Occ_Obs1          = ?,
        R_Occ_Obs2          = ?,
        ObsDiff_Occ         = ?,
        ObsPctDiff_Occ      = ?,
        R_Occ_ManCN         = ?,
        EstOccTotal         = ?,
        OccMoE              = ?,
        OccCIPct            = ?,
        R_TI_Obs1           = ?,
        R_TI_Obs2           = ?,
        ObsDiff_TI          = ?,
        ObsPctDiff_TI       = ?,
        R_TI_ManCN          = ?,
        EstTITotal          = ?,
        TIMoE               = ?,
        TICIPct             = ?,
        Obs1Time            = ?,
        Obs2Time            = ?
    WHERE PredictId = ?
  ", params = list(
    n,
    observer1_initials,
    observer2_initials,
    round(R_cn1, 4),
    round(R_cn2, 4),
    round(cn_obs_pct_diff, 2),
    as.integer(cn_obs_p < 0.05),
    round(R_ManualCN_ModelCN, 4),
    ortho_cn_final,
    ortho_cn_moe,
    round(cn_pct_margin, 2),
    as.integer(p_cn < 0.05),
    round(R_occ1, 4),
    round(R_occ2, 4),
    as.integer(obs_p < 0.05),
    round(obs_pct_diff, 2),
    round(R_Occ_ManCN, 4),
    ortho_occ_total,
    ortho_occ_moe,
    round(pct_margin_occ, 2),
    round(R_ti1, 4),
    round(R_ti2, 4),
    as.integer(ti_obs_p < 0.05),
    round(ti_obs_pct_diff, 2),
    round(R_TI_ManCN, 4),
    ortho_ti_total,
    ortho_ti_moe,
    round(ti_pct_margin, 2),
    obs1_time_to_complete,
    obs2_time_to_complete,
    predict_id
  ))
      
      cat("  Written to CalibratedCounts:", ortho_name,
          "| EstOccTotal:", ortho_occ_total,
          "| AdjCNTotal:", ortho_cn_final, "\n")
    }
    cat("\nCalibration count results written to CalibratedCounts for survey:", survey_name, "\n")
  }
  
  dbDisconnect(con)
  
  
  # --------------------------------------------------------------------
  # ACTIVE NEST ESTIMATE
  # --------------------------------------------------------------------
  # Derives an active nest estimate from ground count data:
  #    R_Act_Occ = sum(active_ct) / sum(occ_ct)   across subcols
  #    R_Act_TI  = sum(active_ct) / sum(total_ct) across subcols
  # These are then applied to EstOccTotal and EstTITotal respectively,
  # giving two independent pathways to an active nest count. Their SEs are
  # propagated via the delta method:
  #    Var(X * Y) / (X * Y)^2 ~= Var(X)/X^2 + Var(Y)/Y^2
  # which assumes X (calibration estimate) and Y (ground count ratio) are independent.
  # --------------------------------------------------------------------
  
  con <- dbConnect(SQLite(), dbname = db_name)
  
  # Colony code and season year from the survey name (e.g., croz_adpe_2024-11-27)
  survey_parts <- strsplit(survey_name, "_")[[1]]
  colony_code  <- survey_parts[1]
  season_yr    <- as.integer(substr(survey_parts[3], 1, 4))
  
  # Ground counts at the index subcolonies for this colony and season
  ground_counts <- dbGetQuery(con, "
    SELECT subcol, active_ct, occ_ct, total_ct
    FROM GroundCounts
    WHERE col = ? AND season_yr = ?
      AND active_ct IS NOT NULL AND occ_ct IS NOT NULL AND occ_ct > 0",
    params = list(colony_code, season_yr))
  
  if (nrow(ground_counts) == 0) {
    warning("No ground count data found in GroundCounts for colony '", colony_code,
            "', season_yr ", season_yr, " — Active counts not calculated.")
  } else {
    # Ratio of active nests to occupied territories across subcolonies, with
    # its ratio-estimator variance (requires at least two subcolonies)
    r_active_occ <- sum(ground_counts$active_ct) / sum(ground_counts$occ_ct)
    m <- nrow(ground_counts)
    if (m > 1) {
      e_r_active_occ <- ground_counts$active_ct - r_active_occ * ground_counts$occ_ct
      var_r_active_occ <- sum(e_r_active_occ^2) /
        (m * (m - 1) * mean(ground_counts$occ_ct)^2)
      se_r_active_occ <- sqrt(var_r_active_occ)
    } else {
      var_r_active_occ <- NA_real_
      se_r_active_occ <- NA_real_
    }
    
    cat("\n--- Active Nest Estimate ---\n")
    cat("Colony:", colony_code, "| Season:", season_yr, "\n")
    cat("Subcolonies used:", m, "\n")
    cat("Total active_ct:", sum(ground_counts$active_ct), "\n")
    cat("Total occ_ct:   ", sum(ground_counts$occ_ct), "\n")
    
    # Ratio of active nests to total individuals, from subcolonies with a
    # total count; NA if none were counted
    ground_counts_with_total <- ground_counts[!is.na(ground_counts$total_ct) & ground_counts$total_ct > 0, ]
    if (nrow(ground_counts_with_total) > 1) {
      r_active_total <- sum(ground_counts_with_total$active_ct) / sum(ground_counts_with_total$total_ct)
      m_t <- nrow(ground_counts_with_total)
      e_r_active_total <- ground_counts_with_total$active_ct - r_active_total * ground_counts_with_total$total_ct
      var_r_active_total <- sum(e_r_active_total^2) / (m_t * (m_t - 1) * mean(ground_counts_with_total$total_ct)^2)
      se_r_active_total <- sqrt(var_r_active_total)
      cat("Total total_ct:", sum(ground_counts_with_total$total_ct), "\n")
    } else if (nrow(ground_counts_with_total) == 1) {
      r_active_total <- ground_counts_with_total$active_ct / ground_counts_with_total$total_ct
      var_r_active_total <- NA_real_
      se_r_active_total <- NA_real_
    } else {
      r_active_total <- NA_real_
      var_r_active_total <- NA_real_
      se_r_active_total <- NA_real_
      cat("No total_ct data available in GroundCounts for this colony/season — R_Act_TI will be NA\n")
    }
    
    cat("R_Act_Occ (active/occupied):  ", round(r_active_occ, 4),
        if (!is.na(se_r_active_occ)) paste0(" ± ", round(1.96 * se_r_active_occ, 4)) else "", "\n")
    cat("R_Act_TI (active/total):   ", round(r_active_total, 4),
        if (!is.na(se_r_active_total)) paste0(" ± ", round(1.96 * se_r_active_total, 4)) else "", "\n")
    
    # Add the active-nest columns to CalibratedCounts if they do not exist
    existing_cols <- dbGetQuery(con, "PRAGMA table_info(CalibratedCounts)") %>% pull(name)
    for (col_name in c("ActiveFromOcc", "ActiveFromTotal", "ActiveFromOccMoE", "ActiveFromTotalMoE")) {
      if (!col_name %in% existing_cols)
        dbExecute(con, paste("ALTER TABLE CalibratedCounts ADD COLUMN", col_name, "INTEGER"))
    }
    for (col_name in c("R_Act_Occ", "R_Act_TI", "R_Act_Occ_SE", "R_Act_TI_SE",
                       "ActiveFromOccCIPct", "ActiveFromTotalCIPct", "R_AdjCN_ActOcc", "R_AdjCN_ActTI")) {
      if (!col_name %in% existing_cols)
        dbExecute(con, paste("ALTER TABLE CalibratedCounts ADD COLUMN", col_name, "REAL"))
    }
    
    # Calibrated estimates for each orthomosaic of the survey (deployed model only)
    ortho_rows <- dbGetQuery(con, "
      SELECT cc.PredictId, cc.OrthomosaicName, cc.EstOccTotal, cc.EstTITotal, cc.AdjCNTotal
      FROM CalibratedCounts cc
      JOIN ModelPredictions mp ON mp.PredictId = cc.PredictId
      WHERE cc.SurveyId = ? AND mp.ModelName = ?",
      params = list(survey_name, model_name))
    
    cat("\n--- Active Nest Estimates ---\n")
    
    for (i in seq_len(nrow(ortho_rows))) {
      est_occ <- ortho_rows$EstOccTotal[i]
      est_ti  <- ortho_rows$EstTITotal[i]
      adj_cn  <- ortho_rows$AdjCNTotal[i]
      
      # Pathway 1: active nests from estimated occupied territories. The
      # relative variances of the calibration estimate and the ground-count
      # ratio are summed (delta method) to give the margin of error.
      active_from_occ <- round(est_occ * r_active_occ)
      
      rel_var_occ_est <- if (R_occ_direct > 0) var_R_occ_direct / R_occ_direct^2 else NA_real_
      rel_var_r_active_occ <- if (!is.na(var_r_active_occ) && r_active_occ > 0) var_r_active_occ / r_active_occ^2 else NA_real_
      
      if (!is.na(rel_var_occ_est) && !is.na(rel_var_r_active_occ)) {
        rel_var_active_from_occ <- rel_var_occ_est + rel_var_r_active_occ
        se_active_from_occ <- sqrt(rel_var_active_from_occ) * active_from_occ
        moe_active_from_occ <- round(1.96 * se_active_from_occ)
        ci_pct_active_from_occ <- round(1.96 * se_active_from_occ / active_from_occ * 100, 2)
      } else {
        moe_active_from_occ <- NA_integer_
        ci_pct_active_from_occ <- NA_real_
      }
      
      # Pathway 2: active nests from estimated total individuals, as a check
      # on pathway 1, with its margin of error calculated the same way
      active_from_total <- if (!is.na(r_active_total) && !is.na(est_ti)) round(est_ti * r_active_total) else NA_integer_
      
      rel_var_ti_est <- if (R_ti_direct > 0) var_R_ti_direct / R_ti_direct^2 else NA_real_
      rel_var_r_active_total <- if (!is.na(var_r_active_total) && !is.na(r_active_total) && r_active_total > 0) var_r_active_total / r_active_total^2 else NA_real_
      
      if (!is.na(active_from_total) && !is.na(rel_var_ti_est) && !is.na(rel_var_r_active_total)) {
        rel_var_active_from_total <- rel_var_ti_est + rel_var_r_active_total
        se_active_from_total <- sqrt(rel_var_active_from_total) * active_from_total
        moe_active_from_total <- round(1.96 * se_active_from_total)
        ci_pct_active_from_total <- round(1.96 * se_active_from_total / active_from_total * 100, 2)
      } else {
        moe_active_from_total <- NA_integer_
        ci_pct_active_from_total <- NA_real_
      }
      
      # Ratio of adjusted candidate nests to each active-nest estimate
      cn_active_ratio_from_occ   <- round(adj_cn / ifelse(active_from_occ == 0, NA, active_from_occ), 4)
      cn_active_ratio_from_total <- round(adj_cn / ifelse(is.na(active_from_total) | active_from_total == 0, NA, active_from_total), 4)
      
      # Record the active-nest estimates and ratios for this orthomosaic
      dbExecute(con, "
      UPDATE CalibratedCounts
      SET ActiveFromOcc        = ?,
          ActiveFromOccMoE     = ?,
          ActiveFromOccCIPct   = ?,
          R_Act_Occ            = ?,
          R_Act_Occ_SE         = ?,
          ActiveFromTotal      = ?,
          ActiveFromTotalMoE   = ?,
          ActiveFromTotalCIPct = ?,
          R_Act_TI             = ?,
          R_Act_TI_SE          = ?,
          R_AdjCN_ActOcc       = ?,
          R_AdjCN_ActTI        = ?
      WHERE PredictId = ?
    ", params = list(
      active_from_occ,
      moe_active_from_occ,
      ci_pct_active_from_occ,
      round(r_active_occ, 4),
      if (!is.na(se_r_active_occ)) round(se_r_active_occ, 6) else NA_real_,
      active_from_total,
      moe_active_from_total,
      ci_pct_active_from_total,
      round(r_active_total, 4),
      if (!is.na(se_r_active_total)) round(se_r_active_total, 6) else NA_real_,
      cn_active_ratio_from_occ,
      cn_active_ratio_from_total,
      ortho_rows$PredictId[i]
    ))
      
      cat("  ", ortho_rows$OrthomosaicName[i],
          "\n    EstOccTotal:", est_occ, " | ActiveFromOcc:", active_from_occ,
          if (!is.na(moe_active_from_occ)) paste0(" ± ", moe_active_from_occ, " (", ci_pct_active_from_occ, "%)") else "",
          "\n    EstTITotal:", est_ti, " | ActiveFromTotal:", active_from_total,
          if (!is.na(moe_active_from_total)) paste0(" ± ", moe_active_from_total, " (", ci_pct_active_from_total, "%)") else "",
          "\n    R_AdjCN_ActOcc:", cn_active_ratio_from_occ, " | R_AdjCN_ActTI:", cn_active_ratio_from_total, "\n")
    }
    cat("Active nest estimates written to CalibratedCounts for survey:", survey_name, "\n")
  }
  
  dbDisconnect(con)
  invisible(TRUE)
}

# --------------------------------------------------------------------
# Run
# --------------------------------------------------------------------
# Surveys with predictions from the deployed model, or those listed in
# surveys_to_run; failures are collected and reported at the end
con <- dbConnect(SQLite(), dbname = db_name)
surveys <- dbGetQuery(con, "
  SELECT DISTINCT SurveyId FROM ModelPredictions
  WHERE PredictId IS NOT NULL AND ModelName = ?
  ORDER BY SurveyId", params = list(model_name))$SurveyId
dbDisconnect(con)

if (!is.null(surveys_to_run)) {
  missing <- setdiff(surveys_to_run, surveys)
  if (length(missing) > 0) stop("Not in ModelPredictions: ", paste(missing, collapse = ", "))
  surveys <- surveys_to_run
}

cat("Surveys to process:", length(surveys), "\n")
failures <- character(0)
for (s in surveys) {
  tryCatch(
    calibrate_counts(s, model_name, db_name, refresh_snapshot = refresh_snapshot),
    error = function(e) {
      message("Failed for survey '", s, "': ", conditionMessage(e))
      failures <<- c(failures, s)
    })
}
if (length(failures) > 0) {
  stop(length(failures), " survey(s) failed: ", paste(failures, collapse = ", "))
}
cat("\nAll done.\n")
