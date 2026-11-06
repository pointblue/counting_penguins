# --------------------------------------------------------------------
# create_table2_population_estimates.R
# Builds Table 2: population estimates for each colony and survey year
# in four census units (adjusted candidate nests, estimated occupied
# territories, estimated active nests, and estimated total individuals
# present), each with its 95% margin of error, alongside the helicopter
# census count where one exists for the same season.
#
# Surveys with more than one orthomosaic (Cape Bird) are combined as
# described in analysis_helpers.R (estimates and margins summed). Active
# nests use the occupied-territory pathway (ActiveFromOcc); the
# total-individual pathway is a check (Methods, Step 7) and is compared
# in compare_census_units.R.
#
# Inputs:  data/UAVSurveys.db
#          data/ross_sea_adelie_penguin_census_record_1981_2025.csv
# Output:  data/table2_population_estimates.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")

out_file <- "data/table2_population_estimates.csv"

# --------------------------------------------------------------------
# Survey-level estimates and helicopter census counts
# --------------------------------------------------------------------
tab <- survey_totals(read_calibrated_counts()) %>%
  left_join(read_helicopter_census(), by = c("colony", "year"))

# --------------------------------------------------------------------
# Format as "estimate ± margin" with thousands separators
# --------------------------------------------------------------------
fmt_n <- function(x) formatC(round(x), format = "d", big.mark = ",")
fmt <- function(est, moe) ifelse(is.na(est), "\u2013",
                                 paste0(fmt_n(est), " \u00B1 ", fmt_n(moe)))

out <- data.frame(
  Colony = tab$Colony,
  Year   = tab$year,
  `Adjusted candidate nests`  = fmt(tab$AdjCN, tab$AdjCN_MoE),
  `Occupied territories`      = fmt(tab$Occ, tab$Occ_MoE),
  `Active nests`              = fmt(tab$Active, tab$Active_MoE),
  `Total individuals present` = fmt(tab$TI, tab$TI_MoE),
  `Helicopter census`         = ifelse(is.na(tab$heli), "\u2013", fmt_n(tab$heli)),
  check.names = FALSE)

write.csv(out, out_file, row.names = FALSE, fileEncoding = "UTF-8")
print(out, row.names = FALSE)
message("Written: ", out_file)
