# --------------------------------------------------------------------
# compare_census_units.R
# Produces the comparisons among census units reported in Results
# Section 3.6 (Methods Section 2.3). For each survey, the percent
# difference 100 x (a - b) / b is computed between a pipeline estimate
# (a) and a reference count (b), and summarized by colony as a mean with
# a 95% confidence interval (t distribution) and a range:
#   1. estimated active nests vs. adjusted candidate nests, for the
#      occupied-territory pathway (reported with confidence intervals)
#      and the total-individual pathway (means only)
#   2. estimated occupied territories vs. the whole-colony manual count
#      of occupied territories at Cape Royds, and the number of years in
#      which the manual count falls within the estimate's 95% interval
#   3. estimated occupied territories and adjusted candidate nests vs.
#      the helicopter census
#   4. directional agreement with the helicopter census across
#      consecutive-year intervals in which both surveys were flown, with
#      the percent change in each series for every interval
#   5. the interval between the paired UAV and helicopter surveys, and
#      whether the helicopter count was above or below estimated
#      occupied territories according to which survey was flown first
#
# Survey dates are those in Table 1 (data/survey_dates.csv). Survey lag
# is defined as helicopter date minus UAV date, so a positive lag means
# the helicopter survey was flown after the UAV survey.
#
# Inputs:  data/UAVSurveys.db
#          data/ross_sea_adelie_penguin_census_record_1981_2025.csv
#          data/survey_dates.csv (columns colony, year, uav_date,
#            heli_date; dates as YYYY-mm-dd)
# Outputs: data/census_unit_comparisons.csv      summaries by colony
#          data/helicopter_comparison_by_survey.csv
#          data/helicopter_direction_by_interval.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")

dates_file <- "data/survey_dates.csv"

# --------------------------------------------------------------------
# Survey-level estimates joined to the reference counts
# --------------------------------------------------------------------
d <- survey_totals(read_calibrated_counts()) %>%
  left_join(read_helicopter_census(), by = c("colony", "year")) %>%
  left_join(read_royds_manual() %>% select(colony, year, manual_occ),
            by = c("colony", "year"))

cat("Helicopter census seasons matched to UAV surveys:\n")
d %>% filter(!is.na(heli)) %>% group_by(Colony) %>%
  summarise(seasons = paste(year, collapse = ", "), .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)

# Summarize one per-survey percent-difference column by colony
by_colony <- function(data, column, label) {
  data %>%
    filter(!is.na(.data[[column]])) %>%
    group_by(Colony) %>%
    group_modify(~ summarize_pct_diff(.x[[column]])) %>%
    ungroup() %>%
    mutate(comparison = label, .before = 1)
}

d <- d %>%
  mutate(active_vs_adjcn   = pct_diff(Active, AdjCN),
         activeTI_vs_adjcn = pct_diff(ActiveTI, AdjCN),
         occ_vs_manual     = pct_diff(Occ, manual_occ),
         occ_vs_heli       = pct_diff(Occ, heli),
         adjcn_vs_heli     = pct_diff(AdjCN, heli))

summary_tab <- bind_rows(
  by_colony(d, "active_vs_adjcn",   "Active nests (occupied pathway) vs adjusted candidate nests"),
  by_colony(d, "activeTI_vs_adjcn", "Active nests (total-individual pathway) vs adjusted candidate nests"),
  by_colony(d, "occ_vs_manual",     "Occupied territories vs whole-colony manual count"),
  by_colony(d, "occ_vs_heli",       "Occupied territories vs helicopter census"),
  by_colony(d, "adjcn_vs_heli",     "Adjusted candidate nests vs helicopter census"))

cat("\nPercent differences by colony (mean, 95% CI, range):\n")
summary_tab %>% mutate(across(c(mean, lower, upper, min, max), ~ round(.x, 1))) %>%
  as.data.frame() %>% print(row.names = FALSE)

# --------------------------------------------------------------------
# Cape Royds: manual count within the 95% interval of the estimate
# --------------------------------------------------------------------
royds <- d %>%
  filter(colony == "royd", !is.na(manual_occ)) %>%
  mutate(lower_95 = Occ - Occ_MoE, upper_95 = Occ + Occ_MoE,
         manual_in_ci = manual_occ >= lower_95 & manual_occ <= upper_95)
cat("\nCape Royds: estimated occupied territories vs whole-colony manual count\n")
royds %>% transmute(year, Occ = round(Occ), Occ_MoE = round(Occ_MoE), manual_occ,
                    pct_diff = round(occ_vs_manual, 1), manual_in_ci) %>%
  as.data.frame() %>% print(row.names = FALSE)
cat(sprintf("Manual count within the 95%% interval in %d of %d years\n",
            sum(royds$manual_in_ci), nrow(royds)))

# --------------------------------------------------------------------
# Directional agreement with the helicopter census
# --------------------------------------------------------------------
# An interval is a pair of consecutive seasons in which both the UAV
# survey and the helicopter census were made
intervals <- d %>%
  filter(!is.na(heli)) %>%
  arrange(colony, year) %>%
  group_by(Colony) %>%
  mutate(year0 = lag(year),
         heli_pct  = pct_diff(heli, lag(heli)),
         occ_pct   = pct_diff(Occ, lag(Occ)),
         adjcn_pct = pct_diff(AdjCN, lag(AdjCN))) %>%
  ungroup() %>%
  filter(!is.na(year0), year - year0 == 1) %>%
  transmute(Colony, interval = paste0(year0, "-", year),
            heli_pct, occ_pct, adjcn_pct,
            occ_same_direction   = sign(occ_pct)   == sign(heli_pct),
            adjcn_same_direction = sign(adjcn_pct) == sign(heli_pct))

cat("\nPercent change per consecutive-year interval:\n")
intervals %>% mutate(across(ends_with("_pct"), ~ round(.x, 1))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nIntervals in which the UAV series changed in the same direction as the helicopter census:\n")
intervals %>% group_by(Colony) %>%
  summarise(intervals = n(),
            occupied_territories = sum(occ_same_direction),
            adjusted_candidate_nests = sum(adjcn_same_direction), .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)

# --------------------------------------------------------------------
# Timing of paired UAV and helicopter surveys
# --------------------------------------------------------------------
dates <- read.csv(dates_file, stringsAsFactors = FALSE) %>%
  mutate(uav_date = as.Date(uav_date), heli_date = as.Date(heli_date))

paired <- d %>%
  filter(!is.na(heli)) %>%
  left_join(dates, by = c("colony", "year")) %>%
  mutate(lag_days   = as.numeric(heli_date - uav_date),
         heli_order = case_when(lag_days < 0  ~ "helicopter first",
                                lag_days == 0 ~ "same day",
                                lag_days > 0  ~ "helicopter later"),
         heli_above_occ = heli > Occ,
         # Expected pattern: helicopter above occupied territories when
         # flown first or on the same day, below when flown later
         follows_pattern = ifelse(lag_days <= 0, heli_above_occ, !heli_above_occ))
if (anyNA(paired$lag_days)) {
  stop("Survey dates missing in ", dates_file, " for: ",
       paste(paired$SurveyId[is.na(paired$lag_days)], collapse = ", "))
}

cat("\nPaired surveys (lag = helicopter date minus UAV date, days):\n")
paired %>% transmute(Colony, year, uav_date, heli_date, lag_days, heli_order,
                     occ_vs_heli = round(occ_vs_heli, 1), heli_above_occ,
                     follows_pattern) %>%
  as.data.frame() %>% print(row.names = FALSE)
cat(sprintf("\nDays between paired surveys: %d to %d (mean %.1f, n = %d)\n",
            min(abs(paired$lag_days)), max(abs(paired$lag_days)),
            mean(abs(paired$lag_days)), nrow(paired)))

cat("\nSurveys following the survey-order pattern, by colony and gap between surveys:\n")
paired %>%
  mutate(gap = ifelse(abs(lag_days) <= 2, "0-2 days apart", "more than 2 days apart")) %>%
  group_by(Colony, gap) %>%
  summarise(surveys = n(), follow_pattern = sum(follows_pattern), .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)

# --------------------------------------------------------------------
# Save
# --------------------------------------------------------------------
write.csv(summary_tab, "data/census_unit_comparisons.csv", row.names = FALSE)
write.csv(paired %>% select(SurveyId, Colony, year, AdjCN, Occ, heli, occ_vs_heli,
                            adjcn_vs_heli, uav_date, heli_date, lag_days,
                            heli_above_occ, follows_pattern),
          "data/helicopter_comparison_by_survey.csv", row.names = FALSE)
write.csv(intervals, "data/helicopter_direction_by_interval.csv", row.names = FALSE)
message("Written: data/census_unit_comparisons.csv, ",
        "data/helicopter_comparison_by_survey.csv, ",
        "data/helicopter_direction_by_interval.csv")
