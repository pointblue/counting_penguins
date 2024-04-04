# rename files to new naming convention


# Define the directory containing the files
directory <- "data/croz_adpe_2023-11-27/validate"

# note that there is some variability in whether the "lcc169" was included...
# List all jpg and txt files that match the pattern
file_paths <- list.files(directory, pattern = "croz_\\d{8}_lcc169_\\d+_\\d+\\.(jpg|txt)$", full.names = TRUE)

# Function to construct the new filename
construct_new_filename <- function(old_name) {
  parts <- strsplit(old_name, "_")[[1]]
  
  # Reformat the date
  date <- substr(parts[2], 1, 4) # Year
  date <- paste0(date, "-", substr(parts[2], 5, 6)) # Month
  date <- paste0(date, "-", substr(parts[2], 7, 8)) # Day
  
  # Construct new filename
  new_name <- paste0(parts[1], "_adpe_", date, "_", parts[3], "_", parts[4], "_", parts[5])
  
  return(new_name)
}

# Rename files
for (file_path in file_paths) {
  # Extract the directory and original filename
  dir_name <- dirname(file_path)
  file_name <- basename(file_path)
  
  # Construct the new filename
  new_file_name <- construct_new_filename(file_name)
  
  # Full path for the new file
  new_file_path <- file.path(dir_name, new_file_name)
  
  # Rename the file
  file.rename(file_path, new_file_path)
}

