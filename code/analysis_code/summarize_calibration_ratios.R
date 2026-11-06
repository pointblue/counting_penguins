# --------------------------------------------------------------------
# summarize_calibration_ratios.R
# Summarizes the grid-cell calibration ratios and the ground-count
# ratios reported in Results Sections 3.5 and 3.6 (Methods, Step 7):
#   - detection correction R_manual:model (manual / model candidate
#     nests): mean across surveys, and the percent undercount by the
#     model (100 x (R - 1)) by colony
#   - 95% margin of error of adjusted candidate nests as a percent of
#     the colony total, by colony
#   - occupied-territory conversion R_occ:CN (manual occupied
#     territories / manual candidate nests) and total-individual
#     conversion R_total:CN, by colony and overall
#   - ratio of active nests to occupied territories from ground counts
#     (R_active:occ): range, colony means, the percent of occupied
#     territories that were inactive, and the variation among surveys
#     compared with the mean within-survey standard error
#
# The ratios are survey-level, so one value per survey is used. Margins
# of error are survey totals (analysis_helpers.R), as in Table 2.
#
# Input:   data/UAVSurveys.db
# Output:  data/calibration_ratios_by_survey.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")

s <- survey_totals(read_calibrated_counts()) %>%
  mutate(adjcn_moe_pct = 100 * AdjCN_MoE / AdjCN,
         undercount_pct = 100 * (R_detect - 1),
         occ_above_cn_pct = 100 * (R_occ - 1),
         inactive_pct = 100 * (1 - R_act_occ))

# Mean, SD, and range of a column by colony, with an "All" row
describe <- function(data, column) {
  f <- function(x) data.frame(n = length(x), mean = mean(x), sd = sd(x),
                              min = min(x), max = max(x))
  x <- data[!is.na(data[[column]]), ]
  bind_rows(x %>% group_by(Colony) %>% group_modify(~ f(.x[[column]])) %>% ungroup(),
            cbind(Colony = "All", f(x[[column]]))) %>%
    mutate(across(c(mean, sd, min, max), ~ round(.x, 4)))
}

# --------------------------------------------------------------------
# Section 3.5: detection correction and margins of error
# --------------------------------------------------------------------
cat("Detection correction R_manual:model:\n")
print(as.data.frame(describe(s, "R_detect")), row.names = FALSE)
cat("\nPercent undercount by the model, 100 x (R_manual:model - 1):\n")
print(as.data.frame(describe(s, "undercount_pct")), row.names = FALSE)
cat("\n95% margin of error of adjusted candidate nests, % of colony total:\n")
print(as.data.frame(describe(s, "adjcn_moe_pct")), row.names = FALSE)

# --------------------------------------------------------------------
# Section 3.6: conversions between census units
# --------------------------------------------------------------------
cat("\nOccupied-territory conversion R_occ:CN:\n")
print(as.data.frame(describe(s, "R_occ")), row.names = FALSE)
cat("\nTotal-individual conversion R_total:CN:\n")
print(as.data.frame(describe(s, "R_total")), row.names = FALSE)

cat("\nActive nests / occupied territories from ground counts, R_active:occ:\n")
print(as.data.frame(describe(s, "R_act_occ")), row.names = FALSE)
cat("\nPercent of occupied territories inactive, 100 x (1 - R_active:occ):\n")
print(as.data.frame(describe(s, "inactive_pct")), row.names = FALSE)

a <- s %>% filter(!is.na(R_act_occ))
cat(sprintf(paste0("\nR_active:occ variation: SD among surveys %.3f; mean within-survey ",
                   "SE %.3f; ratio %.1f\n"),
            sd(a$R_act_occ), mean(a$R_act_occ_SE),
            sd(a$R_act_occ) / mean(a$R_act_occ_SE)))

# --------------------------------------------------------------------
# Save
# --------------------------------------------------------------------
out <- s %>% select(SurveyId, Colony, year, R_detect, undercount_pct, adjcn_moe_pct,
                    R_occ, R_total, R_act_occ, R_act_occ_SE, R_act_total, inactive_pct)
write.csv(out, "data/calibration_ratios_by_survey.csv", row.names = FALSE)
message("Written: data/calibration_ratios_by_survey.csv")
