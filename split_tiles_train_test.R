# for identifying which files will be used for training, testing, and evaluating YOLO models
# note that there needs to be a label file for each of the tiles that are being trained/tested/validated
# and these need to be organized in a specific way

# for identifying which files will be used for training, validating, and testing, YOLO models

library(caret)

# Function to check if a label file contains one of the target labels
check_labels <- function(label_file, target_labels = c(0)) {
  if (!file.exists(label_file)) return(FALSE)
  lines <- readLines(label_file)
  for (line in lines) {
    class_id <- as.integer(strsplit(line, " ")[[1]][1])
    if (class_id %in% target_labels) {
      return(TRUE)
    }
  }
  return(FALSE)
}

# Specify the directory containing the tile files
tile_directory <- "training_data/adult_20231024/images"

# List all the tile files in the directory, including subdirectories
tile_files <- list.files(path = tile_directory, pattern = "\\.(jpg|JPG)$", full.names = TRUE, recursive = TRUE)

# Remove the 200 files that were moved to the evaluation directory
tile_files <- setdiff(tile_files, selected_images)

# Validate each tile file based on its label
valid_files <- sapply(tile_files, function(image_file) {
  relative_path <- gsub(tile_directory, "", image_file)
  label_file <- paste0("training_data/adult_20231024/labels", relative_path)
  label_file <- tools::file_path_sans_ext(label_file)
  label_file <- paste0(label_file, ".txt")
  check_labels(label_file)
})

# Filter valid tile files
valid_tile_files <- tile_files[valid_files]

# Count the number of valid tile files
num_valid_tiles <- length(valid_tile_files)

# Create random indices for partitioning
set.seed(123)
all_indices <- sample(1:num_valid_tiles)

# Create indices for the training set (70%)
train_indices <- all_indices[1:round(0.7 * num_valid_tiles)]

# Create indices for the validation set (15%)
val_indices <- all_indices[(length(train_indices) + 1):(length(train_indices) + round(0.15 * num_valid_tiles))]

# Create indices for the test set (remaining 15%)
test_indices <- all_indices[(length(train_indices) + length(val_indices) + 1):num_valid_tiles]

# Subset file names based on indices
trainSet <- valid_tile_files[train_indices]
valSet <- valid_tile_files[val_indices]
testSet <- valid_tile_files[test_indices]

# Write the partitioned file names to text files
writeLines(trainSet, "training_data/adult_20231024/train.txt")
writeLines(valSet, "training_data/adult_20231024/val.txt")
writeLines(testSet, "training_data/adult_20231024/test.txt")
