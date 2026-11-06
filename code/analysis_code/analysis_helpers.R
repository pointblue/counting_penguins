# --------------------------------------------------------------------
# analysis_helpers.R
# Shared configuration, data-loading functions, and figure styling for
# the analysis scripts that produce the results reported in the
# manuscript (Results Sections 3.1-3.8, Tables 2 and S4, Figures 4-6).
# Each analysis script sources this file first.
#
# Contents:
#   - configuration: database, deployed model, helicopter census file
#   - survey identifiers: colony code and survey year from SurveyId
#   - read_calibrated_counts(): CalibratedCounts rows for the deployed
#     model, one row per orthomosaic
#   - survey_totals(): orthomosaics combined into one row per survey
#   - read_helicopter_census(): helicopter census colony totals by year
#   - read_royds_manual(): whole-colony manual counts of occupied
#     territories at Cape Royds
#   - model_orthomosaics(): orthomosaics processed with the deployed
#     model, and the folder holding each one's GIS outputs
#   - pct_diff(), summarize_pct_diff(): percent differences and their
#     summary (mean, 95% confidence interval, range)
#   - figure labels, palette, symbols, theme, and save_figure()
#
# Inputs:  data/UAVSurveys.db
#          data/ross_sea_adelie_penguin_census_record_1981_2025.csv
# Outputs: none (functions and settings only)
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(DBI)
library(RSQLite)
library(dplyr)
library(tidyr)
library(ggplot2)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
db_name    <- "data/UAVSurveys.db"
model_name <- "ADPE_20250804_adult_sit"   # deployed weights (training run v8_g52)

# Helicopter census: "Adélie Penguin (Pygoscelis adeliae) Breeding Pair
# Counts from Aerial Imagery, Ross Sea Region, Antarctica, 1981-2025"
# (Antarctica New Zealand and Manaaki Whenua - Landcare Research,
# https://doi.org/10.7931/kf06-x745), file
# ross_sea_adelie_penguin_census_record_1981_2025.csv, licensed CC BY-NC
# 4.0. One row per colony section and season (columns Colony, Year,
# Count), with seasons labeled by the year they began, matching the UAV
# survey year. The sections listed for each colony are summed to a
# colony total.
heli_file  <- "data/ross_sea_adelie_penguin_census_record_1981_2025.csv"
heli_rows  <- list(croz = c("Cape Crozier West", "Cape Crozier East"),
                   bird = c("Cape Bird South", "Cape Bird Middle", "Cape Bird North"),
                   royd = c("Cape Royds"))

# Colony codes used in SurveyId, their display names, and the panel order
# used in figures (smallest to largest colony, top to bottom)
colony_names <- c(croz = "Cape Crozier", bird = "Cape Bird", royd = "Cape Royds")
colony_order <- c("Cape Royds", "Cape Bird", "Cape Crozier")

# --------------------------------------------------------------------
# Survey identifiers
# --------------------------------------------------------------------
# SurveyId has the form <colony>_adpe_<YYYY-mm-dd>; the colony code is
# the first four characters and the survey year is the year of the date
colony_code <- function(survey_id) substr(survey_id, 1, 4)
survey_year <- function(survey_id) {
  as.integer(sub(".*_(\\d{4})-\\d{2}-\\d{2}$", "\\1", survey_id))
}

# --------------------------------------------------------------------
# CalibratedCounts for the deployed model
# --------------------------------------------------------------------
# One row per orthomosaic. Cape Bird surveys have two or three
# orthomosaics; the other colonies have one. The selected confidence
# threshold, its F1 score, and the post-filtering detection count are
# taken from ModelPredictions.
read_calibrated_counts <- function() {
  con <- dbConnect(SQLite(), db_name)
  on.exit(dbDisconnect(con))
  cc <- dbGetQuery(con, "
    SELECT c.*, m.Threshold AS Threshold, m.F1Score AS F1Score,
           m.MaskedCleaned AS MaskedCleaned
    FROM CalibratedCounts c
    JOIN ModelPredictions m ON m.PredictId = c.PredictId
    WHERE m.ModelName = ?", params = list(model_name))
  if (nrow(cc) == 0) stop("No CalibratedCounts rows for model ", model_name)
  cc$colony <- colony_code(cc$SurveyId)
  cc$year   <- survey_year(cc$SurveyId)
  cc
}

# --------------------------------------------------------------------
# Survey-level totals
# --------------------------------------------------------------------
# Counts and margins of error are summed across a survey's
# orthomosaics. Margins are summed rather than combined in quadrature
# because the orthomosaics share one calibration sample of grid cells,
# so error in the shared ratios affects every orthomosaic in the same
# direction. Active-nest estimates are reported only when every
# orthomosaic has one, so that a partial sum is never reported. The
# calibration ratios are survey-level (identical on every orthomosaic
# row), so the first non-missing value is used.
total_or_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
complete_total <- function(x) if (anyNA(x)) NA_real_ else sum(x)
first_value <- function(x) if (all(is.na(x))) NA_real_ else x[!is.na(x)][1]

survey_totals <- function(cc) {
  cc %>%
    group_by(SurveyId, colony, year) %>%
    summarise(
      n_ortho          = n(),
      Threshold        = first_value(Threshold),
      F1Score          = first_value(F1Score),
      MaskedCleaned    = total_or_na(MaskedCleaned),
      CandidateNests   = total_or_na(CandidateNestTotal),
      AdjCN            = total_or_na(AdjCNTotal),
      AdjCN_MoE        = total_or_na(AdjCNMoE),
      Occ              = total_or_na(EstOccTotal),
      Occ_MoE          = total_or_na(OccMoE),
      TI               = total_or_na(EstTITotal),
      TI_MoE           = total_or_na(TIMoE),
      Active           = complete_total(ActiveFromOcc),
      Active_MoE       = complete_total(ActiveFromOccMoE),
      ActiveTI         = complete_total(ActiveFromTotal),
      R_detect         = first_value(R_ManualCN_ModelCN),
      R_occ            = first_value(R_Occ_ManCN),
      R_total          = first_value(R_TI_ManCN),
      R_act_occ        = first_value(R_Act_Occ),
      R_act_occ_SE     = first_value(R_Act_Occ_SE),
      R_act_total      = first_value(R_Act_TI),
      .groups = "drop") %>%
    mutate(Colony = unname(colony_names[colony])) %>%
    arrange(match(colony, names(colony_names)), year)
}

# --------------------------------------------------------------------
# Helicopter census colony totals
# --------------------------------------------------------------------
# A colony total is missing for any season in which one of its sections
# was not counted, so that a partial total is never used.
read_helicopter_census <- function(path = heli_file, rows = heli_rows) {
  if (!file.exists(path)) stop("Helicopter census file not found: ", path)
  x <- read.csv(path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  missing_rows <- setdiff(unlist(rows), unique(x$Colony))
  if (length(missing_rows) > 0) {
    stop("Sections not found in ", path, ": ", paste(missing_rows, collapse = ", "))
  }
  heli <- do.call(rbind, lapply(names(rows), function(k) {
    s <- x[x$Colony %in% rows[[k]], ]
    if (anyDuplicated(s[, c("Colony", "Year")])) stop("Duplicate section-season rows for ", k)
    tot <- tapply(seq_len(nrow(s)), s$Year, function(i) {
      if (length(i) == length(rows[[k]])) sum(s$Count[i]) else NA_real_
    })
    data.frame(colony = k, year = as.integer(names(tot)), heli = as.numeric(tot))
  }))
  heli <- heli[!is.na(heli$heli), ]
  message("Helicopter census read for seasons ", min(heli$year), "-", max(heli$year))
  heli
}

# --------------------------------------------------------------------
# Whole-colony manual counts of occupied territories (Cape Royds)
# --------------------------------------------------------------------
# Made by observers from the complete Cape Royds orthomosaic each year
# (final count after review). Cape Crozier rows in this table are
# subcolony counts and are not used.
read_royds_manual <- function() {
  con <- dbConnect(SQLite(), db_name)
  on.exit(dbDisconnect(con))
  m <- dbGetQuery(con, "
    SELECT SurveyId, FinalOccupiedCt AS manual_occ
    FROM ManualCountsOccupied
    WHERE Colony = 'royd' AND FinalOccupiedCt IS NOT NULL")
  m$colony <- colony_code(m$SurveyId)
  m$year   <- survey_year(m$SurveyId)
  m
}

# --------------------------------------------------------------------
# Orthomosaics processed with the deployed model
# --------------------------------------------------------------------
# Pipeline outputs for each orthomosaic are stored under
# data/<SurveyId>/predict/counts/<model>/. The survey folder is named
# by SurveyId, so orthomosaics whose own date differs from the survey
# date (e.g., the Cape Bird 2021 mid-south section) are still found.
model_orthomosaics <- function() {
  con <- dbConnect(SQLite(), db_name)
  on.exit(dbDisconnect(con))
  mp <- dbGetQuery(con, "
    SELECT SurveyId, OrthomosaicName, Threshold, MaskedCleaned
    FROM ModelPredictions WHERE ModelName = ?", params = list(model_name))
  if (nrow(mp) == 0) stop("No ModelPredictions rows for model ", model_name)
  mp$ortho  <- sub("\\.tif$", "", mp$OrthomosaicName)
  mp$colony <- colony_code(mp$SurveyId)
  mp$year   <- survey_year(mp$SurveyId)
  mp[order(match(mp$colony, names(colony_names)), mp$year, mp$ortho), ]
}

counts_dir <- function(survey_id) {
  file.path("data", survey_id, "predict", "counts", model_name)
}
gis_dir <- function(survey_id, ortho) file.path(counts_dir(survey_id), "GIS", ortho)

# --------------------------------------------------------------------
# Percent differences
# --------------------------------------------------------------------
# Percent difference of a from the reference count b: 100 x (a - b) / b
pct_diff <- function(a, b) 100 * (a - b) / b

# Mean with a 95% confidence interval based on the t distribution, and
# the range, of a set of per-survey percent differences
summarize_pct_diff <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 2) {
    return(data.frame(n = length(x), mean = mean(x), lower = NA, upper = NA,
                      min = suppressWarnings(min(x)), max = suppressWarnings(max(x))))
  }
  ci <- t.test(x)$conf.int
  data.frame(n = length(x), mean = mean(x), lower = ci[1], upper = ci[2],
             min = min(x), max = max(x))
}

# --------------------------------------------------------------------
# Figure styling
# --------------------------------------------------------------------
# Metric labels used in figure legends
lab_cn     <- "Candidate Nests (Adj.)"
lab_occ    <- "Est. Occ. Terr."
lab_ti     <- "Est. Total Indiv."
lab_actocc <- "Est. Active (from Occ)"
lab_mocc   <- "Manual Occ. Count"
lab_aerial <- "Helicopter Census"

# Palette chosen to remain distinguishable under common forms of color
# vision deficiency, and plotting symbols matching the figure captions
# (circles, squares, crosses, triangles, asterisks, diamonds)
metric_cols <- c("#002e37",   # Est. Active (from Occ): dark teal
                 "#006C84",   # Est. Occ. Terr.: deep teal
                 "#a8d4ce",   # Est. Total Indiv.: light lagoon teal
                 "#ff8324",   # Candidate Nests (Adj.): orange
                 "#8c2e25",   # Helicopter Census: deep red
                 "grey10")    # Manual Occ. Count: near black
names(metric_cols) <- c(lab_actocc, lab_occ, lab_ti, lab_cn, lab_aerial, lab_mocc)
metric_shapes <- c(17, 15, 3, 19, 8, 18)
names(metric_shapes) <- names(metric_cols)

uav_theme <- function() {
  theme_classic() %+replace%
    theme(axis.title.y = element_text(size = 12, margin = margin(r = 15), angle = 90),
          axis.title.x = element_text(size = 12, margin = margin(t = 15)),
          axis.text    = element_text(size = 8),
          legend.text  = element_text(size = 8),
          legend.title = element_text(size = 12))
}

# Save a figure to figs/ as both JPG and PDF
save_figure <- function(plot, name, width, height, dpi = 300) {
  dir.create("figs", showWarnings = FALSE)
  for (ext in c("jpg", "pdf")) {
    ggsave(file.path("figs", paste0(name, ".", ext)), plot,
           width = width, height = height, units = "in", dpi = dpi)
  }
  message("Saved figs/", name, ".jpg and .pdf")
}
