# choose a tile-set to use for post-prediction validation
# code makes an individual label file and matches to the appropriate tile image
# and copies both into a new directory

library(dplyr)

# read in the consolidated labels file you want to work from:
labels <- read.csv("validation/croz_20191202_validation_labels.csv")


# image_dir <- "validation/tiles/croz_20191202/"
image_dir <- "E:/PenguinCounting/croz_20191202/tiles"

# filter out only the label(s) of interest:
labels <- subset(labels, label == "ADPE_a")

labels$label <- 0 # needs to be the integer value of the label(s) in question

# 'output_directory' is the path to the directory where you want to save the .txt files
output_directory <- "validation/croz_20191202/"

# Ensure the output directory exists
if(!dir.exists(output_directory)) {
  dir.create(output_directory)
}

# Set the number of unique tiles you want to sample
n_tiles <- 200

# Sample tileNames
unique_tiles <- labels %>% distinct(tileName) %>% sample_n(n_tiles)

# Filter labels for only the sampled tileNames
sampled_labels <- labels %>%
  semi_join(unique_tiles, by = "tileName")

# Split by tileName
split_labels <- split(sampled_labels, sampled_labels$tileName)

# Write each subset to a .txt file and copy corresponding image file
sapply(names(split_labels), function(name) {
  # Write the label file without the tileName column
  write.table(split_labels[[name]][, -which(names(split_labels[[name]]) == "tileName")], 
              file = file.path(output_directory, paste0(name, ".txt")), 
              row.names = FALSE, col.names = FALSE, quote = FALSE, sep = " ")
  
  # Copy the corresponding image file
  file.copy(from = file.path(image_dir, paste0(name, ".jpg")), 
            to = file.path(output_directory, paste0(name, ".jpg")))
})
