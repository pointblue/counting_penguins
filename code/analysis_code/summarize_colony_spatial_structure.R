# --------------------------------------------------------------------
# summarize_colony_spatial_structure.R
# Summarizes colony spatial structure for each survey, as described in
# Methods Section 2.4 and reported in Results Section 3.8 and Discussion
# Section 4.3:
#   - subcolonies: number of polygons in the nesting-area boundary layer
#     from Pipeline Step 6, summed across a survey's orthomosaics
#   - nest spacing: distance from each candidate nest to its nearest
#     other candidate nest, averaged across all candidate nests in the
#     survey. Distances are calculated within each orthomosaic and
#     pooled across a survey's orthomosaics. The same quantity is also
#     calculated with neighbors restricted to the same subcolony polygon,
#     and the two are reported side by side so that the definition used
#     in Methods Section 2.4 can be confirmed.
#   - per colony: subcolony mean and range, the year of widest spacing
#     and of most subcolonies, the year of the lowest count, and the
#     Pearson correlation between mean nearest-neighbor distance and the
#     number of subcolonies across survey years
#   - Cape Crozier: the percent increase in mean nearest-neighbor
#     distance from 2018 to the year of widest spacing, and the
#     corresponding change in nests per unit area, assuming the
#     arrangement of nests otherwise remained similar (density scales
#     with the inverse square of spacing)
#   - isolation filter check: for each survey, the share of de-duplicated
#     detections removed by the isolation filter and the median
#     nearest-neighbor distance among detections with and without the
#     filter, and the year of widest median spacing with and without it.
#     Medians are used because the filter removes detections whose
#     nearest neighbor is more than 3 m away, which dominate the mean of
#     the unfiltered layer. Neighbors are not restricted to subcolonies
#     here, since the unfiltered layer has no boundaries.
# Where an orthomosaic folder holds more than one de-duplicated layer,
# the most recent is used and its name is reported.
#
# Inputs:  data/UAVSurveys.db
#          data/<survey>/predict/counts/<model>/GIS/<ortho>/
#            <ortho>_nesting_area_boundaries.shp
#            <ortho>_candidate_nests.shp
#            de_duplicated_labels_par<N>.shp
#            masked_labels_cleaned.shp
# Outputs: data/colony_spatial_structure.csv
#          data/isolation_filter_sensitivity.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")
library(sf)
library(RANN)

# --------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------
# Distance from each point to its nearest other point (the first
# neighbor returned by nn2 is the point itself)
nn_dist <- function(xy) {
  if (nrow(xy) < 2) return(numeric(0))
  nn2(xy, k = 2)$nn.dists[, 2]
}

# Most recent file in a folder whose name matches a pattern
latest_file <- function(dir, pattern) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) == 0) return(NA_character_)
  f[which.max(file.mtime(f))]
}

read_xy <- function(f) st_coordinates(st_read(f, quiet = TRUE))[, 1:2, drop = FALSE]

# --------------------------------------------------------------------
# Per-orthomosaic measurements
# --------------------------------------------------------------------
mp <- model_orthomosaics()

per_ortho <- lapply(seq_len(nrow(mp)), function(i) {
  g <- gis_dir(mp$SurveyId[i], mp$ortho[i])
  f_bound <- file.path(g, paste0(mp$ortho[i], "_nesting_area_boundaries.shp"))
  f_nests <- file.path(g, paste0(mp$ortho[i], "_candidate_nests.shp"))
  f_dedup <- latest_file(g, "^de_duplicated_labels_par\\d+\\.shp$")
  f_clean <- file.path(g, "masked_labels_cleaned.shp")
  missing <- c(f_bound, f_nests, f_dedup, f_clean)[!file.exists(c(f_bound, f_nests, f_dedup, f_clean))]
  if (length(missing) > 0) stop("Missing for ", mp$ortho[i], ": ", paste(missing, collapse = ", "))

  bounds <- st_read(f_bound, quiet = TRUE)
  nests  <- st_read(f_nests, quiet = TRUE)
  xy     <- st_coordinates(nests)[, 1:2, drop = FALSE]

  # Nearest neighbor within the same subcolony polygon; nests outside
  # every polygon are counted and excluded from this version
  poly_id <- st_intersects(nests, st_make_valid(st_geometry(bounds)))
  poly_id <- vapply(poly_id, function(j) if (length(j)) j[1] else NA_integer_, integer(1))
  nn_sub  <- unlist(lapply(split(seq_len(nrow(xy)), poly_id),
                           function(k) nn_dist(xy[k, , drop = FALSE])))

  # Detections before and after the isolation filter
  xy_dedup <- read_xy(f_dedup)
  xy_clean <- read_xy(f_clean)

  list(SurveyId      = mp$SurveyId[i],
       subcolonies   = nrow(bounds),
       n_nests       = nrow(xy),
       nests_outside = sum(is.na(poly_id)),
       nn            = nn_dist(xy),
       nn_subcolony  = nn_sub,
       dedup_file    = basename(f_dedup),
       n_dedup       = nrow(xy_dedup),
       n_clean       = nrow(xy_clean),
       nn_dedup      = nn_dist(xy_dedup),
       nn_clean      = nn_dist(xy_clean))
})

# --------------------------------------------------------------------
# Combine orthomosaics within each survey
# --------------------------------------------------------------------
pool <- function(s, field) unlist(lapply(s, `[[`, field))
ids <- vapply(per_ortho, `[[`, character(1), "SurveyId")
survey <- do.call(rbind, lapply(split(per_ortho, ids), function(s) {
  data.frame(SurveyId              = s[[1]]$SurveyId,
             subcolonies           = sum(pool(s, "subcolonies")),
             candidate_nests       = sum(pool(s, "n_nests")),
             nests_outside_polygons = sum(pool(s, "nests_outside")),
             nn_mean_m             = mean(pool(s, "nn")),
             nn_mean_subcolony_m   = mean(pool(s, "nn_subcolony")),
             n_dedup               = sum(pool(s, "n_dedup")),
             n_clean               = sum(pool(s, "n_clean")),
             median_nn_with_filter_m    = median(pool(s, "nn_clean")),
             median_nn_without_filter_m = median(pool(s, "nn_dedup")),
             dedup_files           = paste(unique(pool(s, "dedup_file")), collapse = "; "))
}))
survey <- survey %>%
  mutate(colony = colony_code(SurveyId), year = survey_year(SurveyId),
         Colony = unname(colony_names[colony]),
         pct_removed_by_filter = 100 * (1 - n_clean / n_dedup)) %>%
  arrange(match(colony, names(colony_names)), year)

cat("Spatial structure by survey:\n")
survey %>% transmute(Colony, year, subcolonies, candidate_nests, nests_outside_polygons,
                     nn_mean_m = round(nn_mean_m, 3),
                     nn_mean_subcolony_m = round(nn_mean_subcolony_m, 3)) %>%
  print(row.names = FALSE)
cat(sprintf("\nLargest difference between the two spacing definitions: %.4f m\n",
            max(abs(survey$nn_mean_m - survey$nn_mean_subcolony_m))))

# --------------------------------------------------------------------
# Colony summaries
# --------------------------------------------------------------------
colony_summary <- survey %>%
  group_by(Colony) %>%
  summarise(surveys          = n(),
            subcolonies_mean = mean(subcolonies),
            subcolonies_min  = min(subcolonies),
            subcolonies_max  = max(subcolonies),
            nn_min_m         = min(nn_mean_m),
            nn_max_m         = max(nn_mean_m),
            widest_year      = year[which.max(nn_mean_m)],
            most_subcolonies_year = year[which.max(subcolonies)],
            lowest_count_year = year[which.min(candidate_nests)],
            r_nn_subcolonies = cor(nn_mean_m, subcolonies),
            .groups = "drop")
cat("\nColony summaries:\n")
colony_summary %>% mutate(across(where(is.double), ~ round(.x, 2))) %>%
  as.data.frame() %>% print(row.names = FALSE)

# --------------------------------------------------------------------
# Cape Crozier: change in spacing and implied nest density
# --------------------------------------------------------------------
croz <- survey %>% filter(colony == "croz")
nn_2018  <- croz$nn_mean_m[croz$year == 2018]
nn_widest <- max(croz$nn_mean_m)
cat(sprintf(paste0("\nCape Crozier mean nearest-neighbor distance: %.3f m (2018), %.3f m (%d); ",
                   "increase %.1f%%; implied change in nests per unit area %.1f%%\n"),
            nn_2018, nn_widest, croz$year[which.max(croz$nn_mean_m)],
            pct_diff(nn_widest, nn_2018), 100 * ((nn_2018 / nn_widest)^2 - 1)))

# --------------------------------------------------------------------
# Isolation filter check
# --------------------------------------------------------------------
cat("\nShare of de-duplicated detections removed by the isolation filter (%):\n")
survey %>% group_by(Colony) %>%
  summarise(min = round(min(pct_removed_by_filter), 1),
            max = round(max(pct_removed_by_filter), 1),
            lowest_count_year = year[which.min(n_clean)],
            removed_in_lowest_count_year = round(pct_removed_by_filter[which.min(n_clean)], 1),
            widest_median_with_filter = year[which.max(median_nn_with_filter_m)],
            widest_median_without_filter = year[which.max(median_nn_without_filter_m)],
            .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)

# --------------------------------------------------------------------
# Save
# --------------------------------------------------------------------
write.csv(survey %>% select(SurveyId, Colony, year, subcolonies, candidate_nests,
                            nests_outside_polygons, nn_mean_m, nn_mean_subcolony_m),
          "data/colony_spatial_structure.csv", row.names = FALSE)
write.csv(survey %>% select(SurveyId, Colony, year, n_dedup, n_clean, pct_removed_by_filter,
                            median_nn_with_filter_m, median_nn_without_filter_m, dedup_files),
          "data/isolation_filter_sensitivity.csv", row.names = FALSE)
message("Written: data/colony_spatial_structure.csv, data/isolation_filter_sensitivity.csv")
