# --------------------------------------------------------------------
# yolo_file_organizer.R
# Copies image tiles and their YOLO label files into the directory
# structure expected for YOLO training, using the train.txt, val.txt, and
# test.txt files produced by yolo_dataset_splitter.R:
#
#   base_dir/train/images, base_dir/train/labels
#   base_dir/val/images,   base_dir/val/labels
#   base_dir/test/images,  base_dir/test/labels
#
# Paths in the split files may be relative to base_dir (current format)
# or include base_dir as a prefix (format written by earlier versions).
#
# The script stops if any listed image or label file is missing, if a file
# appears in more than one subset, or if a destination directory already
# contains files. Leftover files from an earlier split could otherwise mix
# test tiles into training. Set clear_existing to TRUE to empty the
# destination directories before copying.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(fs)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
# Directory containing images/, labels/, and the split files
base_dir <- "training_data/adult_20250804"

# Subsets to organize; each must have a matching <name>.txt in base_dir
set_names <- c("train", "val", "test")

# Empty existing destination directories before copying
clear_existing <- FALSE

images_dir <- path(base_dir, "images")
labels_dir <- path(base_dir, "labels")

# --------------------------------------------------------------------
# Read split files and resolve image and label paths
# --------------------------------------------------------------------
read_split <- function(set_name) {
  list_file <- path(base_dir, paste0(set_name, ".txt"))
  if (!file_exists(list_file)) stop("Split file not found: ", list_file)
  lines <- readLines(list_file)
  lines <- lines[nzchar(trimws(lines))]

  # Accept paths relative to base_dir or already prefixed with it
  img <- ifelse(file_exists(path(base_dir, lines)),
                path(base_dir, lines), lines)
  img <- path(img)

  # Label path mirrors the image path under labels/ with a .txt extension
  lbl <- path(labels_dir, path_ext_set(path_rel(img, images_dir), "txt"))

  missing <- c(img[!file_exists(img)], lbl[!file_exists(lbl)])
  if (length(missing) > 0) {
    stop(set_name, ": ", length(missing), " listed files not found, e.g.: ",
         paste(head(missing, 5), collapse = ", "))
  }
  list(images = img, labels = lbl)
}

splits <- lapply(set_names, read_split)
names(splits) <- set_names

# Confirm that no tile is assigned to more than one subset
all_names <- unlist(lapply(splits, function(x) path_file(x$images)))
if (anyDuplicated(all_names)) {
  stop("Some tiles appear in more than one subset, e.g.: ",
       paste(head(unique(all_names[duplicated(all_names)]), 5),
             collapse = ", "))
}

# --------------------------------------------------------------------
# Prepare destination directories
# --------------------------------------------------------------------
dest_dirs <- as.vector(outer(path(base_dir, set_names),
                             c("images", "labels"), path))
nonempty <- dest_dirs[dir_exists(dest_dirs) &
                        vapply(dest_dirs, function(d) {
                          dir_exists(d) && length(dir_ls(d)) > 0
                        }, logical(1))]

if (length(nonempty) > 0) {
  if (!clear_existing) {
    stop("Destination directories already contain files: ",
         paste(nonempty, collapse = ", "),
         "\nSet clear_existing to TRUE to empty them before copying.")
  }
  for (d in nonempty) file_delete(dir_ls(d))
  message("Emptied ", length(nonempty), " existing destination directories.")
}
dir_create(dest_dirs)

# --------------------------------------------------------------------
# Copy files
# --------------------------------------------------------------------
for (s in set_names) {
  img_dest <- path(base_dir, s, "images")
  lbl_dest <- path(base_dir, s, "labels")
  file_copy(splits[[s]]$images, path(img_dest, path_file(splits[[s]]$images)))
  file_copy(splits[[s]]$labels, path(lbl_dest, path_file(splits[[s]]$labels)))
  message(sprintf("%-5s %d images, %d labels copied", s,
                  length(dir_ls(img_dest)), length(dir_ls(lbl_dest))))
}
