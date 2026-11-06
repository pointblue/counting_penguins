# --------------------------------------------------------------------
# create_nesting_boundaries_clip.R
# Creates draft nesting-area boundary polygons for each orthomosaic of a
# survey from its de-duplicated, masked detections (pipeline Step 6,
# second part). The drafts are reviewed and edited by hand in GIS before
# clip_detections_to_nesting_areas_batch.R clips detections to them.
#
# Method, for each orthomosaic:
#   1. Cluster detections with DBSCAN (eps = 1.5 m, minPts = 3); points
#      not assigned to a cluster are excluded.
#   2. Draw a concave hull around each cluster (ratio = 0.001, holes
#      allowed).
#   3. Buffer the hulls by 2.5 m, simplify (tolerance 0.5 m), and merge
#      overlapping polygons.
#
#   reads  data/<survey>/predict/counts/<model>/GIS/<ortho>/masked_labels_cleaned.shp
#   writes data/<survey>/predict/counts/<model>/GIS/<ortho>/<ortho>_nesting_area_boundaries.shp
#
# Reviewed boundaries are not overwritten: orthomosaics that already have
# a boundary file are skipped unless overwrite = TRUE, in which case the
# existing files are first moved to a time-stamped "previous_boundaries_"
# folder.
#
# Requires sf with GEOS 3.11 or later (for st_concave_hull) and dbscan.
# Run from the project root.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(sf)
library(dbscan)
library(dplyr)
library(RSQLite)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
db_name    <- "data/UAVSurveys.db"
model_name <- "ADPE_20250804_adult_sit"

# Surveys to process. NULL processes every survey with a ModelPredictions
# row for the model; orthomosaics that already have boundaries are
# skipped. To process selected surveys, list their IDs, e.g.
# surveys_to_run <- c("royd_adpe_2019-12-04")
surveys_to_run <- NULL

# Replace existing boundary files (the previous files are kept in a
# time-stamped folder). Leave FALSE to protect reviewed boundaries.
overwrite <- FALSE

# --------------------------------------------------------------------
# Create boundary polygons for one survey
# --------------------------------------------------------------------
create_nesting_boundaries <- function(db_name, survey, model_name,
                                      eps = 1.5, minPts = 3, buffer_dist = 2.5,
                                      hull_ratio = 0.001, simplify_tol = 0.5,
                                      overwrite = FALSE) {
  db <- dbConnect(SQLite(), dbname = db_name)
  on.exit(dbDisconnect(db), add = TRUE)

  ortho_names <- dbGetQuery(db, "
    SELECT OrthomosaicName FROM SurveyImagery WHERE SurveyId = ?",
    params = list(survey))$OrthomosaicName
  if (length(ortho_names) == 0) {
    stop("No orthomosaics found in SurveyImagery for survey: ", survey)
  }
  cat("Survey:", survey, "-", length(ortho_names), "orthomosaic(s)\n")

  gis_dir <- file.path("data", survey, "predict", "counts", model_name, "GIS")

  for (ortho_name in ortho_names) {
    ortho_dir_name <- tools::file_path_sans_ext(ortho_name)
    ortho_dir <- file.path(gis_dir, ortho_dir_name)
    if (!dir.exists(ortho_dir)) {
      warning("Directory not found, skipping: ", ortho_dir)
      next
    }
    out_name <- paste0(ortho_dir_name, "_nesting_area_boundaries")
    out_path <- file.path(ortho_dir, paste0(out_name, ".shp"))

    # Protect existing (reviewed) boundaries
    if (file.exists(out_path)) {
      if (!overwrite) {
        cat("\n  Boundaries exist, skipping:", ortho_dir_name, "\n")
        next
      }
      old <- list.files(ortho_dir, pattern = paste0("^", out_name, "\\."),
                        full.names = TRUE)
      bak <- file.path(ortho_dir, paste0("previous_boundaries_",
                                         format(Sys.time(), "%Y%m%d_%H%M%S")))
      dir.create(bak)
      file.rename(old, file.path(bak, basename(old)))
      cat("\n  Existing boundaries moved to", bak, "\n")
    }

    cat("\n  Creating boundaries for:", ortho_dir_name, "\n")
    predict_shapefile <- st_read(file.path(ortho_dir, "masked_labels_cleaned.shp"),
                                 quiet = TRUE)
    if (is.na(st_crs(predict_shapefile))) {
      stop("No CRS defined: ", ortho_dir)
    }
    if (st_is_longlat(predict_shapefile)) {
      stop("Geographic coordinates; reproject first: ", ortho_dir)
    }

    # DBSCAN clustering; points not in a cluster (cluster 0) are excluded
    predict_coords <- st_coordinates(predict_shapefile)
    dbscan_result <- dbscan(predict_coords, eps = eps, minPts = minPts,
                            splitRule = "MIDPT")
    predict_shapefile$cluster <- dbscan_result$cluster
    predict_shapefile <- predict_shapefile %>% filter(cluster != 0)
    cat("  Clusters found:", max(predict_shapefile$cluster), "\n")
    cat("  Points not in a cluster:", sum(dbscan_result$cluster == 0), "\n")

    # Concave hull around each cluster
    cluster_geoms <- predict_shapefile %>%
      group_by(cluster) %>%
      summarise(geometry = st_union(geometry))
    cluster_geoms$geometry <- st_sfc(
      lapply(st_geometry(cluster_geoms), function(g) {
        st_concave_hull(g, ratio = hull_ratio, allow_holes = TRUE)
      }),
      crs = st_crs(cluster_geoms)
    )

    # Buffer, simplify, and merge overlapping polygons
    clump_polygons <- cluster_geoms %>%
      st_buffer(dist = buffer_dist) %>%
      st_simplify(dTolerance = simplify_tol) %>%
      st_as_sf() %>%
      st_union() %>%
      st_cast("POLYGON") %>%
      st_as_sf() %>%
      mutate(subcol_id = row_number())

    st_write(clump_polygons, out_path, quiet = TRUE)
    cat("  Boundary polygons:", nrow(clump_polygons), "\n")
    cat("  Written to:", out_path, "\n")
    cat("  Review and edit in GIS before running",
        "clip_detections_to_nesting_areas_batch.R\n")
  }
}

# --------------------------------------------------------------------
# Run
# --------------------------------------------------------------------
con <- dbConnect(SQLite(), dbname = db_name)
surveys <- dbGetQuery(con, "
  SELECT DISTINCT SurveyId FROM ModelPredictions WHERE ModelName = ?
  ORDER BY SurveyId", params = list(model_name))$SurveyId
dbDisconnect(con)
if (!is.null(surveys_to_run)) {
  missing <- setdiff(surveys_to_run, surveys)
  if (length(missing) > 0) stop("Not in ModelPredictions: ", paste(missing, collapse = ", "))
  surveys <- surveys_to_run
}

for (s in surveys) {
  cat("\n============================================================\n")
  create_nesting_boundaries(db_name, s, model_name, overwrite = overwrite)
}
