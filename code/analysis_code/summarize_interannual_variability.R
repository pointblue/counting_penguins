# --------------------------------------------------------------------
# summarize_interannual_variability.R
# Summarizes change in colony size over the study, as reported in
# Results Section 3.7 and the Abstract, and the changes cited in
# Discussion Section 4.2. All values are adjusted candidate nests
# summed across each survey's orthomosaics, unless stated otherwise.
#   - per colony: mean count; year of the minimum; percent and absolute
#     decline from the first survey to the minimum; percent and absolute
#     recovery from the minimum to the last survey; net change from the
#     first to the last survey
#   - year-to-year change: mean absolute percent change and the range of
#     single-year changes, by colony
#   - year-to-year changes compared with the combined 95% uncertainty of
#     the two annual estimates, approximated as the square root of the
#     sum of their squared relative margins of error
#   - Cape Crozier changes from 2020 to 2022 (adjusted candidate nests
#     and estimated occupied territories) and from 2024 to 2025, compared
#     with the combined counts of Cape Bird and Cape Royds
#
# Input:   data/UAVSurveys.db
# Outputs: data/population_summary_by_colony.csv
#          data/year_to_year_change.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")

s <- survey_totals(read_calibrated_counts()) %>%
  mutate(rel_moe = AdjCN_MoE / AdjCN)

# --------------------------------------------------------------------
# Decline, minimum, and recovery by colony
# --------------------------------------------------------------------
colony_summary <- s %>%
  arrange(year) %>%
  group_by(Colony) %>%
  summarise(surveys        = n(),
            first_year     = first(year),
            mean_count     = mean(AdjCN),
            min_year       = year[which.min(AdjCN)],
            decline_pct    = pct_diff(min(AdjCN), first(AdjCN)),
            decline_nests  = min(AdjCN) - first(AdjCN),
            recovery_pct   = pct_diff(last(AdjCN), min(AdjCN)),
            recovery_nests = last(AdjCN) - min(AdjCN),
            net_pct        = pct_diff(last(AdjCN), first(AdjCN)),
            .groups = "drop")

# --------------------------------------------------------------------
# Year-to-year change and combined uncertainty
# --------------------------------------------------------------------
yoy <- s %>%
  arrange(colony, year) %>%
  group_by(Colony) %>%
  mutate(year0 = lag(year),
         pct_change = pct_diff(AdjCN, lag(AdjCN)),
         combined_pct = 100 * sqrt(rel_moe^2 + lag(rel_moe)^2)) %>%
  ungroup() %>%
  filter(!is.na(year0), year - year0 == 1) %>%
  transmute(Colony, interval = paste0(year0, "-", year), pct_change, combined_pct,
            exceeds = abs(pct_change) > combined_pct)

colony_summary <- colony_summary %>%
  left_join(yoy %>% group_by(Colony) %>%
              summarise(mean_abs_change_pct = mean(abs(pct_change)),
                        min_change_pct = min(pct_change),
                        max_change_pct = max(pct_change),
                        changes = n(), exceed_uncertainty = sum(exceeds),
                        .groups = "drop"),
            by = "Colony")

cat("Adjusted candidate nests by colony:\n")
colony_summary %>% mutate(across(where(is.double), ~ round(.x, 1))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nYear-to-year change vs combined 95% uncertainty:\n")
yoy %>% mutate(across(c(pct_change, combined_pct), ~ round(.x, 1))) %>%
  as.data.frame() %>% print(row.names = FALSE)
cat(sprintf("\nChanges exceeding combined uncertainty: %d of %d\n",
            sum(yoy$exceeds), nrow(yoy)))
cat(sprintf("Range of colony means of absolute year-to-year change: %.1f%% to %.1f%%; largest single change %.1f%%\n",
            min(colony_summary$mean_abs_change_pct), max(colony_summary$mean_abs_change_pct),
            yoy$pct_change[which.max(abs(yoy$pct_change))]))

# --------------------------------------------------------------------
# Discussion Section 4.2: Cape Crozier changes in context
# --------------------------------------------------------------------
croz <- s %>% filter(colony == "croz")
val <- function(col, yr) croz[[col]][croz$year == yr]
other <- s %>% filter(colony != "croz") %>% group_by(year) %>%
  summarise(bird_plus_royds = sum(AdjCN), colonies = n(), .groups = "drop")

cat("\nCape Crozier, 2020 to 2022:\n")
cat(sprintf("  adjusted candidate nests: %+.0f; estimated occupied territories: %+.0f\n",
            val("AdjCN", 2022) - val("AdjCN", 2020), val("Occ", 2022) - val("Occ", 2020)))
cat(sprintf("  largest combined Cape Bird + Cape Royds count in a year with both: %.0f\n",
            max(other$bird_plus_royds[other$colonies == 2])))
cat("Cape Crozier, 2024 to 2025:\n")
cat(sprintf("  adjusted candidate nests: %+.0f (%+.1f%%); highest in series: %s\n",
            val("AdjCN", 2025) - val("AdjCN", 2024),
            pct_diff(val("AdjCN", 2025), val("AdjCN", 2024)),
            val("AdjCN", 2025) == max(croz$AdjCN)))

# --------------------------------------------------------------------
# Save
# --------------------------------------------------------------------
write.csv(colony_summary, "data/population_summary_by_colony.csv", row.names = FALSE)
write.csv(yoy, "data/year_to_year_change.csv", row.names = FALSE)
message("Written: data/population_summary_by_colony.csv, data/year_to_year_change.csv")
