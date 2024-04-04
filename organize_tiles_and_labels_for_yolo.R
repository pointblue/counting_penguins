# move tiles and labels into the correct directory structure for YOLO to be happy
# need to run split_tiles_train_test first

# Required Libraries
library(fs)

# Your source directories - note that in this case (adult_20231024) the only files here are ones with adult (ADPE_a) labels.
image_source_dir <- "training_data/adult_20231024/images"
label_source_dir <- "training_data/adult_20231024/labels"

# Your destination directories
train_image_dest <- "training_data/adult_20231024/train"
val_image_dest <- "training_data/adult_20231024/val"
test_image_dest <- "training_data/adult_20231024/test"

# Create these directories if they do not exist
dir.create(train_image_dest, recursive = TRUE, showWarnings = FALSE)
dir.create(val_image_dest, recursive = TRUE, showWarnings = FALSE)
dir.create(test_image_dest, recursive = TRUE, showWarnings = FALSE)


# Function to copy files
move_files <- function(source_paths, dest_folder) {
  for (file_path in source_paths) {
    file_name <- basename(file_path)
    dest_path <- file.path(dest_folder, file_name)
    file.copy(from = file_path, to = dest_path, overwrite = TRUE)
  }
}

# Function to remove file extensions
remove_extension <- function(files) {
  sapply(strsplit(files, split = "\\."), `[`, 1)
}

# List all the label files in the directory
label_files <- list.files(path = label_source_dir, pattern = "\\.(txt)$", full.names = TRUE, recursive = TRUE)

# Remove file extensions from label and image files
label_files_base <- remove_extension(basename(label_files))
train_image_base <- remove_extension(basename(trainSet)) # made by split_tiles_train_test.R
val_image_base <- remove_extension(basename(valSet))
test_image_base <- remove_extension(basename(testSet))

# Match label files with image files
trainLabelSet <- label_files[label_files_base %in% train_image_base]
valLabelSet <- label_files[label_files_base %in% val_image_base]
testLabelSet <- label_files[label_files_base %in% test_image_base]

# Move image files
move_files(trainSet, train_image_dest)
move_files(valSet, val_image_dest)
move_files(testSet, test_image_dest)

# Move label files
move_files(trainLabelSet, train_image_dest)
move_files(valLabelSet, val_image_dest)
move_files(testLabelSet, test_image_dest)