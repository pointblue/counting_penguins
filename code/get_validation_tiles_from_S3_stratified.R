# --------------------------------------------------------------------
# get_validation_tiles_from_S3_stratified.R
# Draws the sample of tiles reviewed by experts to select a survey's
# confidence threshold (pipeline Step 5), and stages them for review in
# makesense.ai.
#
# For one orthomosaic, tiles are divided into those with at least one
# model detection (confidence >= 0.10, the inference cutoff) and those
# with none, and a random sample is drawn from each (set.seed(42)). The
# blank stratum is where missed penguins would be found, so sampling it
# separately ensures that false negatives are assessed. Each sampled tile
# is copied with its predicted boxes (confidence column removed), which
# reviewers then correct in makesense.ai rather than labeling from
# scratch; tiles without detections get an empty label file.
#
# Inputs:
#   data/<survey>/predict/counts/<model>/labels/*.txt
#       YOLO detections per tile; downloaded from
#       s3://<bucket>/<prefix>/results/<ortho>/labels/ if not present
#   s3://<bucket>/<prefix>/tiles/<ortho>/*.jpg
# Outputs, in data/<survey>/validate/:
#   tiles/<tile>.jpg, tiles/<tile>.txt   tiles and predicted boxes, the
#                                        makesense.ai import folder read
#                                        by validation_functions.R
#   labels.txt                           class name for makesense.ai
#
# An existing validation folder is not resampled; the script reports its
# contents instead. Run once per orthomosaic, from the project root.
# Requires AWS credentials with read access to the bucket.
#
# Developed with assistance from Gemini (Google) and Claude (Anthropic); 
# reviewed and tested by the authors.
# --------------------------------------------------------------------

library(aws.s3)
library(fs)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
# Survey, orthomosaic, and model names
survey_name <- "royd_adpe_2025-12-02"
ortho_name  <- "royd_adpe_2025-12-02_lcc169"
model_name  <- "ADPE_20250804_adult_sit"

# S3 location of the survey's tiles and inference results
s3_region      <- "us-east-2"
bucket_name    <- "deju-penguinscience"
s3_base_prefix <- "PenguinCounting/royd_20251202"

# Number of tiles to sample with and without detections
target_with_penguins     <- 75
target_blank             <- 125
class_name_for_makesense <- "ADPE_a"

# --------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------
Sys.setenv("AWS_DEFAULT_REGION" = s3_region)

base_data_dir      <- file.path("data", survey_name)
label_source_dir   <- file.path(base_data_dir, "predict/counts", model_name, "labels")
local_validate_dir <- fs::path(base_data_dir, "validate")
local_tiles_dir    <- fs::path(local_validate_dir, "tiles")

# Inference results and tiles as written by the inference launcher and tiler
s3_labels_prefix <- paste0(s3_base_prefix, "/results/", ortho_name, "/labels/")
s3_tiles_prefix  <- paste0(s3_base_prefix, "/tiles/", ortho_name, "/")

# --------------------------------------------------------------------
# Predicted labels: use local copies if present, otherwise download
# --------------------------------------------------------------------
if (!dir_exists(label_source_dir)) {
  dir_create(label_source_dir, recursive = TRUE)
}

existing_labels <- dir_ls(label_source_dir, glob = "*.txt")

if (length(existing_labels) > 0) {
  message("Labels already found in the local directory. Skipping S3 download.")
} else {
  message("Downloading predicted labels from S3...")

  # Full list of label files (max = Inf avoids the 1,000-object default)
  label_bucket_contents <- get_bucket(
    bucket = bucket_name,
    prefix = s3_labels_prefix,
    max = Inf,
    region = s3_region
  )

  label_keys <- vapply(label_bucket_contents, function(x) x$Key, character(1))
  label_keys <- label_keys[grepl("\\.txt$", label_keys, ignore.case = TRUE)]

  if (length(label_keys) == 0) {
    stop("No labels found at the specified S3 path: ", s3_labels_prefix)
  }

  for (l_key in label_keys) {
    local_path <- fs::path(label_source_dir, basename(l_key))
    save_object(
      object = l_key,
      bucket = bucket_name,
      file = local_path,
      region = s3_region
    )
  }
  message(sprintf("Successfully downloaded %d labels.", length(label_keys)))
}

# --------------------------------------------------------------------
# Sample and stage the validation tiles
# --------------------------------------------------------------------
# An existing sample is kept, because the reviewed labels depend on it
existing_val_tiles <- if (dir_exists(local_tiles_dir)) {
  dir_ls(local_tiles_dir, glob = "*.jpg")
} else {
  character(0)
}

if (length(existing_val_tiles) > 0) {
  message("Validation tiles folder already contains tiles. Skipping sampling and download.")

  # Report the composition of the existing sample: label files with
  # content are tiles with detections
  val_txt_files <- dir_ls(local_tiles_dir, glob = "*.txt")

  tiles_with_detections <- sum(file_info(val_txt_files)$size > 0)
  tiles_blank           <- length(val_txt_files) - tiles_with_detections
  total_tiles           <- length(existing_val_tiles)

} else {
  message("Generating new validation set...")

  # All tiles of the orthomosaic
  tile_bucket_contents <- get_bucket(
    bucket = bucket_name,
    prefix = s3_tiles_prefix,
    max = Inf,
    region = s3_region
  )

  all_jpg_keys <- vapply(tile_bucket_contents, function(x) x$Key, character(1))
  all_jpg_keys <- all_jpg_keys[grepl("\\.jpg$", all_jpg_keys, ignore.case = TRUE)]

  # Strata: tiles with a non-empty label file (at least one detection)
  # and tiles without one
  label_info <- fs::dir_info(label_source_dir, glob = "*.txt")
  positive_label_paths <- label_info[label_info$size > 0, "path"][[1]]
  positive_label_names <- fs::path_ext_remove(fs::path_file(positive_label_paths))
  tile_names           <- fs::path_ext_remove(basename(all_jpg_keys))

  has_label <- tile_names %in% positive_label_names
  positives <- all_jpg_keys[has_label]
  negatives <- all_jpg_keys[!has_label]

  # Random sample from each stratum
  set.seed(42)
  selected_positives <- sample(positives, min(target_with_penguins, length(positives)))
  selected_negatives <- sample(negatives, min(target_blank, length(negatives)))
  selected_keys      <- c(selected_positives, selected_negatives)

  if (!dir_exists(local_tiles_dir)) dir_create(local_tiles_dir, recursive = TRUE)
  writeLines(class_name_for_makesense, fs::path(local_validate_dir, "labels.txt"))

  # Copy each tile and its predicted boxes, dropping the confidence column
  # so that makesense.ai can import them; blank tiles get an empty file
  for (s3_key in selected_keys) {
    file_name  <- basename(s3_key)
    local_tile <- fs::path(local_tiles_dir, file_name)

    save_object(
      object = s3_key,
      bucket = bucket_name,
      file = local_tile,
      overwrite = TRUE,
      region = s3_region
    )

    label_name <- sub("\\.jpg$", ".txt", file_name)
    src        <- fs::path(label_source_dir, label_name)
    dest       <- fs::path(local_tiles_dir, label_name)

    if (file.exists(src) && file.info(src)$size > 0) {
      labels <- read.table(src, header = FALSE)
      if (ncol(labels) >= 6) { labels <- labels[, -6] }
      write.table(labels, file = dest, row.names = FALSE, col.names = FALSE, quote = FALSE, sep = " ")
    } else {
      file_create(dest)
    }
  }

  total_tiles           <- length(selected_keys)
  tiles_with_detections <- length(selected_positives)
  tiles_blank           <- length(selected_negatives)
}

# --------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------
message("\n# --------------------------------------------------------------------")
message("STRATIFIED VALIDATION SET STATUS")
message(sprintf("Survey Name:           %s", survey_name))
message(sprintf("Ortho Name:            %s", ortho_name))
message(sprintf("Model Name:            %s", model_name))
message(sprintf("Total tiles in folder: %d", total_tiles))
message(sprintf("Tiles with detections: %d", tiles_with_detections))
message(sprintf("Blank tiles:           %d", tiles_blank))
message(paste("Output Location:      ", local_tiles_dir))
message("# --------------------------------------------------------------------\n")
