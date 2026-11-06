# --------------------------------------------------------------------
# summarize_training_data.R
# Summarizes the annotated YOLO dataset used to train and evaluate the
# detection model (Methods, Pipeline Step 4; Results Section 3.2):
#   1. for each subset (train, validation, test) and in total: image
#      tiles, label files, tiles with at least one labeled penguin,
#      tiles without penguins (empty label files), and labeled
#      individuals, with a check that image and label files correspond
#   2. potential overlap between training and evaluation tiles. Tiles
#      overlap their grid neighbors by a fixed band, so a bird near the
#      edge of an evaluation tile can also appear in an adjacent training
#      tile from the same orthomosaic. For each validation and test tile,
#      the script finds training tiles among its eight grid neighbors and
#      records the largest shared area (side, top or bottom, or corner).
#      The upper bound on affected labels assumes every label in an
#      adjacent occupied tile lies in proportion to that shared area.
# Tile file names encode the orthomosaic name and the tile's column and
# row in the tiling grid (<ortho>_<column>_<row>); no image data are
# read.
#
# Inputs:  data/training_data/adult_20250804/
#            train.txt, val.txt, test.txt   (image paths in each subset)
#            <subset>/images/, <subset>/labels/
# Outputs: data/training_label_summary.csv
#          data/tile_adjacency_assessment.csv
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
base_dir <- "training_data/adult_20250804"
subsets  <- c("train", "val", "test")
image_exts <- c("jpg", "jpeg", "png")
class_def_file <- "labels.txt"   # class names, not a tile label file

# Tile geometry from the tiling step (Pipeline Step 3)
tile_width  <- 512
tile_height <- 256
overlap     <- 20
tile_area   <- tile_width * tile_height
frac_side   <- overlap * tile_height / tile_area   # left or right neighbor
frac_updown <- tile_width * overlap / tile_area    # top or bottom neighbor
frac_corner <- overlap * overlap / tile_area       # diagonal neighbor

# Stop early if the dataset is not where expected; list.files() would
# otherwise return nothing and the summary would show zero counts
needed <- c(file.path(base_dir, paste0(subsets, ".txt")),
            file.path(base_dir, subsets, "images"), file.path(base_dir, subsets, "labels"))
if (!all(file.exists(needed))) {
  stop("Training dataset not found or incomplete under ", base_dir, "; missing: ",
       paste(needed[!file.exists(needed)], collapse = ", "))
}

# Number of labeled individuals in a YOLO label file (non-blank lines)
count_labels <- function(f) {
  if (!file.exists(f)) return(NA_integer_)
  sum(nzchar(trimws(readLines(f, warn = FALSE))))
}

# --------------------------------------------------------------------
# 1. Tiles and labels by subset
# --------------------------------------------------------------------
subset_summary <- do.call(rbind, lapply(subsets, function(s) {
  label_files <- list.files(file.path(base_dir, s, "labels"), pattern = "\\.txt$",
                            full.names = TRUE)
  label_files <- label_files[basename(label_files) != class_def_file]
  image_files <- list.files(file.path(base_dir, s, "images"), full.names = TRUE,
                            pattern = paste0("\\.(", paste(image_exts, collapse = "|"), ")$"),
                            ignore.case = TRUE)
  n <- vapply(label_files, count_labels, integer(1))
  label_stems <- tools::file_path_sans_ext(basename(label_files))
  image_stems <- tools::file_path_sans_ext(basename(image_files))
  data.frame(subset = s,
             images = length(image_files),
             label_files = length(label_files),
             tiles_with_penguins = sum(n > 0),
             tiles_without_penguins = sum(n == 0),
             labeled_individuals = sum(n),
             images_without_label = length(setdiff(image_stems, label_stems)),
             labels_without_image = length(setdiff(label_stems, image_stems)))
}))
total <- cbind(subset = "total", as.data.frame(lapply(subset_summary[-1], sum)))
subset_summary <- rbind(subset_summary, total)
print(subset_summary, row.names = FALSE)
if (total$images_without_label + total$labels_without_image > 0) {
  warning("Image and label files do not correspond one-to-one; see the last two columns")
}

# --------------------------------------------------------------------
# 2. Adjacency of evaluation tiles to training tiles
# --------------------------------------------------------------------
# Orthomosaic names contain underscores, so the two grid indices are
# taken from the end of the file name
read_split <- function(s) {
  paths <- readLines(file.path(base_dir, paste0(s, ".txt")), warn = FALSE)
  paths <- paths[nzchar(trimws(paths))]
  stem  <- tools::file_path_sans_ext(basename(paths))
  parts <- strsplit(stem, "_", fixed = TRUE)
  data.frame(stem  = stem,
             ortho = vapply(parts, function(p) paste(head(p, -2), collapse = "_"), ""),
             x     = vapply(parts, function(p) as.integer(p[length(p) - 1]), 1L),
             y     = vapply(parts, function(p) as.integer(p[length(p)]), 1L))
}

train <- read_split("train")
train_by_ortho <- split(train[, c("x", "y")], train$ortho)

assess_split <- function(s) {
  d <- read_split(s)
  d$n_labels <- vapply(file.path(base_dir, s, "labels", paste0(d$stem, ".txt")),
                       count_labels, integer(1))
  d$edge_frac <- vapply(seq_len(nrow(d)), function(i) {
    tk <- train_by_ortho[[d$ortho[i]]]
    if (is.null(tk)) return(0)
    dx <- tk$x - d$x[i]; dy <- tk$y - d$y[i]
    nb <- abs(dx) <= 1 & abs(dy) <= 1 & !(dx == 0 & dy == 0)
    if (!any(nb)) return(0)
    max(ifelse(dy[nb] == 0, frac_side, ifelse(dx[nb] == 0, frac_updown, frac_corner)))
  }, numeric(1))
  occupied <- d$n_labels > 0
  adjacent <- d$edge_frac > 0
  data.frame(subset = s,
             tiles = nrow(d),
             labels = sum(d$n_labels),
             adjacent_tiles = sum(adjacent),
             adjacent_occupied_tiles = sum(adjacent & occupied),
             labels_in_adjacent_occupied = sum(d$n_labels[adjacent & occupied]),
             affected_labels_upper = sum(d$n_labels * d$edge_frac))
}

adjacency <- rbind(assess_split("val"), assess_split("test"))
adjacency <- rbind(adjacency, cbind(subset = "total", as.data.frame(lapply(adjacency[-1], sum))))
adjacency$adjacent_pct_tiles <- 100 * adjacency$adjacent_tiles / adjacency$tiles
adjacency$affected_pct_labels <- 100 * adjacency$affected_labels_upper / adjacency$labels
print(adjacency, row.names = FALSE, digits = 3)

# --------------------------------------------------------------------
# Save
# --------------------------------------------------------------------
write.csv(subset_summary, "data/training_label_summary.csv", row.names = FALSE)
write.csv(adjacency, "data/tile_adjacency_assessment.csv", row.names = FALSE)
message("Written: data/training_label_summary.csv, data/tile_adjacency_assessment.csv")