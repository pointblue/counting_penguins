# --------------------------------------------------------------------
# validation_functions.R
# Functions for selecting a survey-specific confidence threshold for
# YOLO detections (pipeline Step 5).
#
# For each survey, a random sample of tiles is reviewed by experts in
# makesense.ai to produce reference ("validation") labels. Model
# detections on the same tiles are matched one-to-one to reference boxes
# at intersection over union (IoU) >= 0.5, and precision, recall, and F1
# score are computed across a range of confidence thresholds. The
# threshold that maximizes F1 is selected.
#
# create_validation_layers() converts reference labels and detections on
# the validation tiles to georeferenced polygons and writes them, with
# the tile footprints, to data/<survey>/validate/<survey>_validation.gpkg.
# compute_threshold_results() reads that file, computes the threshold
# results, writes a CSV and figures, and records the selected threshold
# in the ModelPredictions table of the survey database (all orthomosaic
# rows for the survey).
#
# The full list of sampled validation tiles is needed so that false
# positives on tiles with no penguins are counted. The makesense.ai CSV
# export lists only labeled boxes, so tiles with no reference labels are
# absent from it. The list is taken from the makesense.ai import folder,
# data/<survey>/validate/tiles/, which holds one image per sampled tile.
# A text file with one tile name per line can be supplied instead. If
# neither is available, only tiles with at least one reference label are
# used and a warning is issued; this reproduces the original analysis.
#
# Inputs:
#   data/<survey>/validate/reviewed*.csv    makesense.ai CSV export
#   data/<survey>/predict/counts/<model>/labels/*.txt
#                                           YOLO detections per tile
#   s3://<bucket>/<prefix>/<colony_YYYYmmdd>/tiles/*tilesGeorefTable.csv
#   s3://<bucket>/<prefix>/<colony_YYYYmmdd>/<ortho_name>.tif
#                                           (header metadata only)
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(dplyr)
library(purrr)
library(readr)
library(stringr)
library(sf)
library(RSQLite)
library(ggplot2)

# --------------------------------------------------------------------
# Survey and tile name helpers
# --------------------------------------------------------------------
# Look up a single survey ID in the Surveys table
get_survey_id <- function(db, colony, species, date) {
  ids <- dbGetQuery(db, "SELECT SurveyId FROM Surveys")$SurveyId
  survey <- ids[str_detect(ids, glue::glue("^{colony}_{species}.*_{date}$"))]
  if (length(survey) != 1) {
    stop("Expected one survey matching ", colony, "_", species, "_", date,
         "; found ", length(survey), ": ", paste(survey, collapse = ", "))
  }
  survey
}

# Convert a survey ID "<colony>_<species>_<YYYY-mm-dd>" to the S3 folder
# name "<colony>_<YYYYmmdd>"
survey_name_to_s3_folder <- function(survey_name) {
  m <- str_match(survey_name,
                 "^([a-z]{4})_[a-z]{4}_(\\d{4})-(\\d{2})-(\\d{2})$")
  if (is.na(m[1, 1])) stop("Unexpected survey name format: ", survey_name)
  paste0(m[1, 2], "_", m[1, 3], m[1, 4], m[1, 5])
}

# Convert tile names in older georeference tables (e.g.,
# "bird_middle_20211201_x.jpg") to the current naming convention
# ("bird_mid_adpe_2021-12-01_x"), and drop the .jpg extension. Names
# already in the current convention are returned without the extension.
standardize_tile_name <- function(x) {
  x <- str_replace(
    x, "^(bird)_(middle|north|south)_(\\d{4})(\\d{2})(\\d{2})_(.*)\\.jpg$",
    "\\1_\\2_adpe_\\3-\\4-\\5_\\6")
  x <- str_replace(
    x, "^(croz|royd)_((?:middle|north|south)_)?(\\d{4})(\\d{2})(\\d{2})_(.*)\\.jpg$",
    "\\1_\\2adpe_\\3-\\4-\\5_\\6")
  site <- str_detect(x, "^(bird|croz|royd)")
  x[site] <- gsub("middle", "mid", x[site])
  sub("\\.(jpg|txt)$", "", x)
}

# Orthomosaic name from a tile name "<ortho_name>_<x>_<y>"
tile_ortho_name <- function(tile_name) {
  sub("^(.*?)_\\d+_\\d+$", "\\1", tile_name)
}

# --------------------------------------------------------------------
# Amazon S3 helpers
# --------------------------------------------------------------------
# Orthomosaic resolution, dimensions, and CRS from the GeoTIFF header
# (read through GDAL's /vsis3/ interface; no raster data are downloaded)
get_ortho_meta_s3 <- function(ortho_name, bucket, base_prefix,
                              survey_folder) {
  vsis3_path <- glue::glue(
    "/vsis3/{bucket}/{base_prefix}/{survey_folder}/{ortho_name}.tif")
  info_json <- paste(
    suppressWarnings(capture.output(
      sf::gdal_utils("info", source = vsis3_path, options = "-json"),
      type = "output")),
    collapse = "\n")
  meta <- jsonlite::fromJSON(info_json)
  tibble::tibble(
    ortho_name  = ortho_name,
    xres        = abs(meta$geoTransform[2]),
    yres        = abs(meta$geoTransform[6]),
    ortho_width = meta$size[1],
    ortho_height = meta$size[2],
    crs_wkt     = meta$coordinateSystem$wkt
  )
}

# All tile georeference tables for a survey, with standardized tile names
read_georef_s3 <- function(bucket, base_prefix, survey_folder) {
  tiles_prefix <- glue::glue("{base_prefix}/{survey_folder}/tiles/")
  objs <- aws.s3::get_bucket(bucket = bucket, prefix = tiles_prefix,
                             max = Inf)
  keys <- vapply(objs, function(x) x[["Key"]], character(1))
  keys <- keys[grepl("/tiles/.*tilesGeoref.*\\.csv$", keys,
                     ignore.case = TRUE)]
  if (length(keys) == 0) {
    stop("No tile georeference tables under s3://", bucket, "/",
         tiles_prefix)
  }
  map_dfr(keys, ~ aws.s3::s3read_using(
    FUN = read_csv, object = .x, bucket = bucket,
    show_col_types = FALSE)) |>
    mutate(tileName = standardize_tile_name(tileName))
}

# --------------------------------------------------------------------
# Label readers and conversion to georeferenced polygons
# --------------------------------------------------------------------
# makesense.ai CSV export: one row per box, pixel coordinates of the
# box's upper-left corner and its size
read_makesense_csv <- function(valid_dir) {
  files <- list.files(valid_dir, pattern = "^reviewed.*\\.csv$",
                      full.names = TRUE)
  if (length(files) == 0) stop("No reviewed*.csv files in ", valid_dir)
  # Read without assuming a header row; any header line is dropped below
  labs <- read_csv(files, col_names = FALSE, show_col_types = FALSE,
                   col_types = cols(.default = "c"))
  names(labs) <- c("label_name", "bbox_x", "bbox_y", "bbox_width",
                   "bbox_height", "tileName", "image_width", "image_height")
  labs |>
    filter(!is.na(suppressWarnings(as.numeric(bbox_x)))) |>
    mutate(across(c(bbox_x, bbox_y, bbox_width, bbox_height,
                    image_width, image_height), as.numeric),
           tileName = sub("\\.jpg$", "", tileName))
}

# YOLO detections: one file per tile with at least one detection; each
# line is class, box center and size (normalized to tile dimensions),
# and confidence
read_yolo_labels <- function(label_dir, tile_names) {
  files <- file.path(label_dir, paste0(tile_names, ".txt"))
  files <- files[file.exists(files)]
  map_dfr(files, function(f) {
    read_delim(f, delim = " ", show_col_types = FALSE,
               col_names = c("class", "x_center", "y_center", "width",
                             "height", "conf"),
               col_types = cols(.default = "d")) |>
      mutate(tileName = sub("\\.txt$", "", basename(f)))
  })
}

# Axis-aligned rectangles to an sf object
boxes_to_sf <- function(df, crs) {
  geom <- pmap(df[, c("xmin", "xmax", "ymin", "ymax")],
               function(xmin, xmax, ymin, ymax) {
                 st_polygon(list(cbind(c(xmin, xmax, xmax, xmin, xmin),
                                       c(ymin, ymin, ymax, ymax, ymin))))
               })
  st_sf(df, geometry = st_sfc(geom, crs = crs))
}

# --------------------------------------------------------------------
# Build validation layers for a survey
# --------------------------------------------------------------------
create_validation_layers <- function(db_name, colony, species, date,
                                     model_name, bucket, base_prefix,
                                     valid_tiles_source = NULL,
                                     training_tiles = NULL,
                                     tile_width = 512, tile_height = 256) {
  db <- dbConnect(SQLite(), dbname = db_name)
  on.exit(dbDisconnect(db))
  survey <- get_survey_id(db, colony, species, date)
  survey_folder <- survey_name_to_s3_folder(survey)
  valid_dir <- file.path("data", survey, "validate")
  label_dir <- file.path("data", survey, "predict", "counts", model_name,
                         "labels")

  # Reference labels and the set of validation tiles
  valid_labs <- read_makesense_csv(valid_dir)
  labeled_tiles <- unique(valid_labs$tileName)
  # Tile list: the makesense.ai import folder by default, or a text file
  if (is.null(valid_tiles_source)) {
    valid_tiles_source <- file.path(valid_dir, "tiles")
  }
  if (dir.exists(valid_tiles_source)) {
    valid_tiles <- sub("\\.jpg$", "",
                       list.files(valid_tiles_source, pattern = "\\.jpg$",
                                  ignore.case = TRUE), ignore.case = TRUE)
  } else if (file.exists(valid_tiles_source)) {
    valid_tiles <- sub("\\.jpg$", "", trimws(readLines(valid_tiles_source)))
    valid_tiles <- unique(valid_tiles[nzchar(valid_tiles)])
  } else {
    warning("No validation tile list found (", valid_tiles_source, "). ",
            "Using only tiles with reference labels; false positives on ",
            "tiles without penguins will not be counted.", call. = FALSE)
    valid_tiles <- labeled_tiles
  }
  extra <- setdiff(labeled_tiles, valid_tiles)
  if (length(extra) > 0) {
    stop(length(extra), " labeled tiles are not in ", valid_tiles_source)
  }
  message(survey, ": ", length(valid_tiles), " validation tiles (",
          length(valid_tiles) - length(labeled_tiles),
          " with no reference labels), ", nrow(valid_labs), " reference boxes")

  # Validation tiles should not have been used to train the model
  if (!is.null(training_tiles)) {
    reused <- intersect(valid_tiles, standardize_tile_name(training_tiles))
    if (length(reused) > 0) {
      warning(length(reused), " validation tiles were also training tiles, ",
              "e.g.: ", paste(head(reused, 3), collapse = ", "), call. = FALSE)
    }
  }

  # Tile positions and orthomosaic metadata
  georef <- read_georef_s3(bucket, base_prefix, survey_folder) |>
    filter(tileName %in% valid_tiles)
  missing <- setdiff(valid_tiles, georef$tileName)
  if (length(missing) > 0) {
    stop(length(missing), " validation tiles not found in the georeference ",
         "tables, e.g.: ", paste(head(missing, 3), collapse = ", "))
  }
  ortho_info <- map_dfr(unique(tile_ortho_name(georef$tileName)),
                        get_ortho_meta_s3, bucket = bucket,
                        base_prefix = base_prefix,
                        survey_folder = survey_folder)
  if (n_distinct(ortho_info$crs_wkt) > 1) {
    stop("Orthomosaics for this survey use more than one CRS.")
  }
  the_crs <- st_crs(ortho_info$crs_wkt[1])

  # Tile extents; edge tiles are truncated at the orthomosaic boundary
  tiles <- georef |>
    mutate(ortho_name = tile_ortho_name(tileName)) |>
    left_join(select(ortho_info, -crs_wkt), by = "ortho_name") |>
    mutate(tile_w = pmin(tile_width, ortho_width - pixelX),
           tile_h = pmin(tile_height, ortho_height - pixelY),
           labeled = tileName %in% labeled_tiles)
  tile_cols <- c("tileName", "easting", "northing", "xres", "yres",
                 "tile_w", "tile_h")

  # Reference boxes: pixel offsets from the tile's upper-left corner
  valid_boxes <- valid_labs |>
    inner_join(tiles[, tile_cols], by = "tileName") |>
    mutate(xmin = easting + bbox_x * xres,
           xmax = xmin + bbox_width * xres,
           ymax = northing - bbox_y * yres,
           ymin = ymax - bbox_height * yres)

  # Detections: normalized centers and sizes, scaled by each tile's
  # actual dimensions
  pred_boxes <- read_yolo_labels(label_dir, valid_tiles) |>
    inner_join(tiles[, tile_cols], by = "tileName") |>
    mutate(cx = easting + x_center * tile_w * xres,
           cy = northing - y_center * tile_h * yres,
           half_w = width * tile_w * xres / 2,
           half_h = height * tile_h * yres / 2,
           xmin = cx - half_w, xmax = cx + half_w,
           ymin = cy - half_h, ymax = cy + half_h) |>
    select(-cx, -cy, -half_w, -half_h)

  tile_boxes <- tiles |>
    mutate(xmin = easting, xmax = easting + tile_w * xres,
           ymax = northing, ymin = northing - tile_h * yres)

  # Write a GeoPackage (no 10-character field name limit, one file)
  gpkg <- file.path(valid_dir, paste0(survey, "_validation.gpkg"))
  if (file.exists(gpkg)) file.remove(gpkg)
  st_write(boxes_to_sf(tile_boxes, the_crs), gpkg, layer = "tiles",
           quiet = TRUE)
  st_write(boxes_to_sf(valid_boxes, the_crs), gpkg, layer = "validation",
           quiet = TRUE)
  st_write(boxes_to_sf(pred_boxes, the_crs), gpkg, layer = "predictions",
           quiet = TRUE)
  message("Wrote ", gpkg, " (", nrow(pred_boxes), " detections)")
  invisible(gpkg)
}

# --------------------------------------------------------------------
# Matching and threshold selection
# --------------------------------------------------------------------
# IoU for all detection-reference pairs on the same tile, computed from
# box coordinates (all boxes are axis-aligned rectangles)
pair_iou <- function(preds, valids, min_iou) {
  p <- mutate(preds, PredictId = row_number())
  v <- mutate(valids, ValidId = row_number())
  inner_join(p, v, by = "tileName", suffix = c("_p", "_v"),
             relationship = "many-to-many") |>
    mutate(inter = pmax(0, pmin(xmax_p, xmax_v) - pmax(xmin_p, xmin_v)) *
                   pmax(0, pmin(ymax_p, ymax_v) - pmax(ymin_p, ymin_v)),
           union = (xmax_p - xmin_p) * (ymax_p - ymin_p) +
                   (xmax_v - xmin_v) * (ymax_v - ymin_v) - inter,
           iou = ifelse(union > 0, inter / union, 0)) |>
    filter(iou >= min_iou) |>
    select(tileName, PredictId, ValidId, conf, iou)
}

# Greedy one-to-one matching in order of decreasing IoU; returns the
# number of matched pairs
greedy_match_count <- function(pid, vid, iou) {
  o <- order(iou, decreasing = TRUE)
  used_p <- used_v <- integer(0)
  for (i in o) {
    if (!(pid[i] %in% used_p) && !(vid[i] %in% used_v)) {
      used_p <- c(used_p, pid[i])
      used_v <- c(used_v, vid[i])
    }
  }
  length(used_p)
}

# True positives, false positives, and false negatives at each threshold.
# Detections are retained when confidence > threshold.
threshold_counts <- function(preds, valids, thresholds, min_iou = 0.5) {
  pairs <- pair_iou(preds, valids, min_iou)
  n_valid <- nrow(valids)
  map_dfr(thresholds, function(t) {
    pt <- pairs[pairs$conf > t, ]
    tp <- sum(vapply(split(pt, pt$tileName), function(d)
      greedy_match_count(d$PredictId, d$ValidId, d$iou), integer(1)))
    n_pred <- sum(preds$conf > t)
    tibble::tibble(conf_thresh = t, tp_all = tp, fp_all = n_pred - tp,
                   fn_all = n_valid - tp)
  })
}

compute_threshold_results <- function(db_name, colony, species, date,
                                      model_name, min_thresh = 0.10,
                                      step = 0.01, min_iou = 0.5,
                                      update_db = TRUE) {
  db <- dbConnect(SQLite(), dbname = db_name)
  on.exit(dbDisconnect(db))
  survey <- get_survey_id(db, colony, species, date)
  valid_dir <- file.path("data", survey, "validate")
  gpkg <- file.path(valid_dir, paste0(survey, "_validation.gpkg"))

  preds  <- st_drop_geometry(st_read(gpkg, layer = "predictions", quiet = TRUE))
  valids <- st_drop_geometry(st_read(gpkg, layer = "validation", quiet = TRUE))

  thresholds <- round(seq(min_thresh, 1, by = step), 6)
  results_summ <- threshold_counts(preds, valids, thresholds, min_iou) |>
    mutate(actual_positive = tp_all + fn_all,
           total_positive  = tp_all + fp_all,
           precision = tp_all / total_positive,
           recall    = tp_all / actual_positive,
           # Thresholded count ratio: reference count / detection count
           TCR    = actual_positive / total_positive,
           FScore = 2 * precision * recall / (precision + recall))
  write_csv(results_summ,
            file.path(valid_dir, paste0(survey, "_threshold_results.csv")))

  # Threshold maximizing F1; ties go to the highest threshold, and all
  # reported values are taken at the selected threshold
  best_f <- max(results_summ$FScore, na.rm = TRUE)
  sel <- results_summ |>
    filter(!is.na(FScore), FScore == best_f) |>
    slice_max(conf_thresh, n = 1)
  if (sel$conf_thresh <= min_thresh) {
    warning("Selected threshold equals the minimum evaluated (", min_thresh,
            "); the optimum may lie below it.", call. = FALSE)
  }

  # Figures
  fig_dir <- file.path("figs", "validation")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  pr_plot <- ggplot(results_summ, aes(recall, precision, col = conf_thresh)) +
    geom_point(na.rm = TRUE) +
    geom_label(aes(label = conf_thresh), na.rm = TRUE, size = 2.5) +
    theme(legend.position = "none")
  f_plot <- ggplot(results_summ, aes(conf_thresh, FScore)) +
    geom_point(na.rm = TRUE) +
    geom_vline(xintercept = sel$conf_thresh, linetype = 2) +
    labs(x = "Confidence threshold", y = "F1 score",
         subtitle = paste("Selected threshold =", sel$conf_thresh))
  ggsave(file.path(fig_dir, paste0(survey, "_precision_recall.jpg")),
         pr_plot, width = 8, height = 6, units = "in", dpi = 150)
  ggsave(file.path(fig_dir, paste0(survey, "_FScores.jpg")),
         f_plot, width = 8, height = 4, units = "in", dpi = 150)

  # Record selected values in the ModelPredictions table
  if (update_db) {
    n <- dbExecute(db, "
      UPDATE ModelPredictions
      SET F1Score = ?, Precision = ?, Recall = ?, Threshold = ?, TCR = ?
      WHERE SurveyId = ? AND ModelName = ?",
      params = list(round(sel$FScore, 4), round(sel$precision, 4),
                    round(sel$recall, 4), sel$conf_thresh,
                    round(sel$TCR, 4), survey, model_name))
    # One row per orthomosaic; surveys split into several orthomosaics
    # share one threshold
    if (n == 0) {
      warning("No ModelPredictions rows updated for ", survey, " / ",
              model_name, ".", call. = FALSE)
    } else {
      message(n, " ModelPredictions row(s) updated")
    }
  }

  message(sprintf(
    "%s: threshold %.2f, F1 %.4f, precision %.4f, recall %.4f, TCR %.4f",
    survey, sel$conf_thresh, sel$FScore, sel$precision, sel$recall, sel$TCR))
  invisible(results_summ)
}
