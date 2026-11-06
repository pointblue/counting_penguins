# --------------------------------------------------------------------
# summarize_field_survey_metrics.R
# Summarizes the UAV survey effort metrics reported in Results Section
# 3.1 from the per-survey values in Table S2: survey area, number of
# images, and survey execution time by colony; coverage efficiency
# (hectares mapped per hour) of the multi-UAV Cape Crozier surveys
# relative to the single, manually flown UAV survey of 2018; mean
# imaging time at Cape Royds excluding the manually flown 2018 survey;
# and ground sample distance (GSD) in the first and last survey years.
#
# The summary table (by colony) includes the ground sample distance
# range and its values in each colony's first and last survey years.
#
# Input:   data/table_s2_survey_metrics.csv (one row per survey, as in
#            Table S2; area_approximate marks areas given as approximate)
# Output:  data/field_survey_metrics_summary.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")

s2 <- read.csv("data/table_s2_survey_metrics.csv", stringsAsFactors = FALSE) %>%
  mutate(Colony = unname(colony_names[colony]),
         ha_per_hr = survey_area_ha / execution_time_hr)

# --------------------------------------------------------------------
# Area, images, execution time, and number of UAVs by colony
# --------------------------------------------------------------------
by_colony <- s2 %>%
  group_by(Colony) %>%
  summarise(surveys    = n(),
            uavs       = paste(range(n_uavs), collapse = "-"),
            area_ha    = paste(range(survey_area_ha), collapse = "-"),
            images     = paste(range(n_images), collapse = "-"),
            time_hr    = paste(range(execution_time_hr), collapse = "-"),
            min_time_year = year[which.min(execution_time_hr)],
            gsd_cm        = paste(range(ortho_gsd_cm), collapse = "-"),
            gsd_first_year_cm = ortho_gsd_cm[which.min(year)],
            gsd_last_year_cm  = ortho_gsd_cm[which.max(year)],
            .groups = "drop")
cat("Survey metrics by colony (ranges across surveys):\n")
print(as.data.frame(by_colony), row.names = FALSE)

# --------------------------------------------------------------------
# Coverage efficiency of multi-UAV surveys at Cape Crozier
# --------------------------------------------------------------------
# Percent improvement in hectares per hour relative to the 2018 survey
# (one UAV, flown manually; area approximate)
croz <- s2 %>% filter(colony == "croz") %>% arrange(year)
baseline <- croz$ha_per_hr[croz$year == 2018]
croz <- croz %>% mutate(pct_improvement = 100 * (ha_per_hr / baseline - 1))
cat("\nCape Crozier coverage efficiency (ha per hour):\n")
croz %>% transmute(year, n_uavs, ha_per_hr = round(ha_per_hr, 1),
                   pct_improvement = round(pct_improvement)) %>%
  as.data.frame() %>% print(row.names = FALSE)
multi <- croz %>% filter(n_uavs > 1)
cat(sprintf("Multi-UAV surveys: improvement %.0f%% to %.0f%%\n",
            min(multi$pct_improvement), max(multi$pct_improvement)))

# --------------------------------------------------------------------
# Cape Royds imaging time, excluding the manually flown 2018 survey
# --------------------------------------------------------------------
royd_min <- 60 * s2$execution_time_hr[s2$colony == "royd" & s2$year != 2018]
cat(sprintf("\nCape Royds mean imaging time, 2019-2025: %.1f minutes\n", mean(royd_min)))

# --------------------------------------------------------------------
# Ground sample distance in the first and last survey years
# --------------------------------------------------------------------
cat("\nGround sample distance (cm/pixel):\n")
s2 %>% filter(year %in% range(year)) %>% select(Colony, year, ortho_gsd_cm) %>%
  arrange(year, Colony) %>% as.data.frame() %>% print(row.names = FALSE)

# --------------------------------------------------------------------
# Save
# --------------------------------------------------------------------
out <- by_colony %>%
  mutate(croz_multi_uav_improvement_pct =
           ifelse(Colony == "Cape Crozier",
                  sprintf("%.0f-%.0f", min(multi$pct_improvement), max(multi$pct_improvement)),
                  NA),
         royds_mean_minutes_2019_2025 =
           ifelse(Colony == "Cape Royds", round(mean(royd_min), 1), NA))
write.csv(out, "data/field_survey_metrics_summary.csv", row.names = FALSE)
message("Written: data/field_survey_metrics_summary.csv")
