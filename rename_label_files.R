# Set the path to your directory
dir_path <- "Z:/Informatics/S031/analyses/RI_penguin_count_UAV/data/croz_adpe_2022-12-02/predict/counts/ADPE_20231024_adult_sit/labels"

# List all .txt files in the directory
files <- list.files(dir_path, pattern = "\\.txt$", full.names = TRUE)
# files <- files[grep("south", files, ignore.case = TRUE)]

# Loop through the files to rename them
for (file_path in files) {
  # file_path <- files[1]
  # Extract the filename from the path
  file_name <- basename(file_path)
  # Construct the new filename based on your specified pattern
  # Using gsub to capture and reformat the specific parts of the filename
  new_file_name <- gsub("croz_([0-9]{4})([0-9]{2})([0-9]{2})_lcc169_([0-9]{1,4})_([0-9]{1,4})\\.txt",
                         "croz_adpe_\\1-\\2-\\3_lcc169_\\4_\\5.txt", file_name)
  
  # new_file_name <- gsub("croz_([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{1,4})_([0-9]{1,4})\\.txt",
  #                      "croz_adpe_\\1-\\2-\\3_lcc169_\\4_\\5.txt", file_name)  
  # Construct the new full file path
  new_file_path <- file.path(dirname(file_path), new_file_name)
  
  # Rename the file
  file.rename(from = file_path, to = new_file_path)
  
  # cat(sprintf("Renamed '%s' to '%s'\n", file_name, new_file_name))
}
