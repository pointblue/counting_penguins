# --------------------------------------------------------------------
# yolo_dataset_splitter.R
# Randomly assigns annotated image tiles to training, validation, and test
# subsets for YOLO model training, and writes the assignments to train.txt,
# val.txt, and test.txt in the training data directory.
#
# Expected layout of base_dir:
#   images/   Image tiles (.jpg, .jpeg, or .png); subdirectories allowed.
#   labels/   One YOLO-format .txt label file per image, mirroring the
#             structure of images/. Tiles with no objects must have an
#             empty label file.
#
# Each output file lists image paths relative to base_dir, one per line.
# Files are sorted in a locale-independent order before shuffling, so a
# given seed produces the same split on any operating system.
#
# If all three split files already exist, the script does not overwrite
# them. It regenerates the split in memory and reports whether it matches
# the existing files, which allows an archived split to be checked against
# this code. Set overwrite_existing to TRUE to replace existing files.
#
# Run yolo_file_organizer.R afterward to copy files into the directory
# structure expected by YOLO.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(fs)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
# Directory containing the images/ and labels/ subdirectories; output
# files are written here
base_dir <- "training_data/adult_20250804"

# Split proportions; the test set receives the remainder
train_ratio <- 0.70
val_ratio   <- 0.15

# Random seed for a reproducible split
random_seed <- 123

# Replace existing split files instead of comparing against them
overwrite_existing <- FALSE

# --------------------------------------------------------------------
# Locate images and confirm that each has a label file
# --------------------------------------------------------------------
images_dir <- path(base_dir, "images")
labels_dir <- path(base_dir, "labels")

if (!dir_exists(images_dir)) stop("Images directory not found: ", images_dir)
if (!dir_exists(labels_dir)) stop("Labels directory not found: ", labels_dir)
if (train_ratio + val_ratio > 1) stop("train_ratio + val_ratio exceeds 1.")

# Image paths relative to images/, sorted in C-locale (byte) order so the
# input to sample() does not depend on platform or locale
image_rel <- path_rel(
  dir_ls(images_dir, regexp = "\\.(jpg|jpeg|png)$",
         recurse = TRUE, ignore.case = TRUE),
  images_dir)
image_rel <- sort(as.character(image_rel), method = "radix")

total_files <- length(image_rel)
if (total_files == 0) stop("No image files found in ", images_dir)
message("Found ", total_files, " image files.")

# The organizer copies all files into flat directories, so file names
# must be unique across subdirectories
dup_names <- unique(path_file(image_rel)[duplicated(path_file(image_rel))])
if (length(dup_names) > 0) {
  stop(length(dup_names), " image file names occur more than once, e.g.: ",
       paste(head(dup_names, 5), collapse = ", "))
}

# YOLO treats an image with no label file as containing no objects, so a
# missing label would silently become a false background example
label_paths <- path(labels_dir, path_ext_set(image_rel, "txt"))
missing_labels <- image_rel[!file_exists(label_paths)]
if (length(missing_labels) > 0) {
  stop(length(missing_labels), " images have no label file, e.g.: ",
       paste(head(missing_labels, 5), collapse = ", "),
       "\nCreate empty label files for tiles that contain no objects.")
}

# --------------------------------------------------------------------
# Shuffle and split
# --------------------------------------------------------------------
set.seed(random_seed)
shuffled <- sample(image_rel)

n_train <- floor(train_ratio * total_files)
n_val   <- floor(val_ratio * total_files)
n_test  <- total_files - n_train - n_val

# Store paths relative to base_dir (e.g., "images/tile.jpg")
split_sets <- list(
  train = path("images", shuffled[seq_len(n_train)]),
  val   = path("images", shuffled[n_train + seq_len(n_val)]),
  test  = path("images", shuffled[n_train + n_val + seq_len(n_test)])
)

message(sprintf("Split (seed %d): train %d, validation %d, test %d",
                random_seed, n_train, n_val, n_test))

# --------------------------------------------------------------------
# Write split files, or compare against existing ones
# --------------------------------------------------------------------
split_files <- path(base_dir, paste0(names(split_sets), ".txt"))
names(split_files) <- names(split_sets)

if (all(file_exists(split_files)) && !overwrite_existing) {
  # Compare by file name, so files written with a different path prefix
  # by earlier versions of this script can still be checked
  message("Split files already exist; comparing without overwriting.")
  all_match <- TRUE
  for (s in names(split_sets)) {
    existing <- path_file(readLines(split_files[[s]]))
    current  <- path_file(split_sets[[s]])
    same <- setequal(existing, current) && length(existing) == length(current)
    all_match <- all_match && same
    message(sprintf("  %-5s existing %d, regenerated %d, %s", s,
                    length(existing), length(current),
                    if (same) "identical" else "DIFFERENT"))
  }
  if (all_match) {
    message("Existing split matches the split generated by this script.")
  } else {
    warning("Existing split differs from the regenerated split. ",
            "Retain the existing files as the record of the split used.")
  }
} else {
  for (s in names(split_sets)) {
    writeLines(as.character(split_sets[[s]]), split_files[[s]])
    message("Wrote ", split_files[[s]])
  }
}
