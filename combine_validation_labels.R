# -----------------------------------------
# combine validation labels after they have been verified
# -----------------------------------------

library(dplyr)
library(tidyr)
library(foreach)
library(doParallel)
library(readr)
library(stringr)

labels_path = "data/croz_adpe_2019-12-02/validate/"

# Get a list of all label file names in the labels directory
label_files <- list.files(path = labels_path, pattern = "croz_adpe_\\d{4}-\\d{2}-\\d{2}_\\d+_\\d+\\.txt$", full.names = TRUE)

# Function to process a label file and return its data frame
process_label_file <- function(file) {
  # Extract tile name from the file name
  tile_name <- gsub("\\.txt$", "", basename(file))
  tile_name <- paste0(tile_name, ".jpg")
  
  # Read the label file
  labels <- read_delim(file, delim = " ", col_names = FALSE, show_col_types = FALSE)
  
  # Create a data frame for the current file's data
  # Note that these don't have the sixth "confidence" column
  file_data <- data.frame(
    tileName = rep(tile_name, nrow(labels)),
    label = labels$X1,
    box_center_w = labels$X2,
    box_center_h = labels$X3,
    box_width = labels$X4,
    box_height = labels$X5
  )
  
  return(file_data)
}

# Register the parallel backend in order to speed this up (takes a long time otherwise)
cl <- makeCluster(detectCores() - 1)  # Leaving one core free for other tasks
registerDoParallel(cl)

# Process label files in parallel
combined_data <- foreach(file=label_files, .combine='rbind', .packages=c("dplyr", "readr", "stringr")) %dopar% {
  process_label_file(file)
}

# Stop the parallel backend
stopCluster(cl)

# Write the combined data to a CSV file
write_csv(combined_data, paste0(labels_path,"/croz_adpe_2019-12-02_validation_labels.csv"))
