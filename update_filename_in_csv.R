# rename the files in a csv assuming first column is the filename

library(dplyr)

# note that there may or may not be "lcc_169" in the filenames you are working with
# double check and modify function as needed.
# Function to convert old filenames to new convention
convert_filename <- function(old_name) {
  parts <- strsplit(old_name, "_")[[1]]
  if (length(parts) == 4) {
    # Extract and reformat the date
    date <- substr(parts[2], 1, 4) # Year
    date <- paste0(date, "-", substr(parts[2], 5, 6)) # Month
    date <- paste0(date, "-", substr(parts[2], 7, 8)) # Day
    
    # Construct new filename
    new_name <- paste0(parts[1], "_adpe_", date, "_", parts[3], "_", parts[4])
    return(new_name)
  } else {
    # Return the original name if it doesn't match the expected pattern
    return(old_name)
  }
}


# Define the path to the directory containing your CSV files
csv_directory <- "data/croz_adpe_2021-11-27/validate/"

# List all CSV files in the directory
csv_files <- list.files(csv_directory, pattern = "\\.csv$", full.names = TRUE)

# Loop through each CSV file to update the filenames
for (csv_file in csv_files) {
  # Read the CSV file into R
  data <- read.csv(csv_file)
  
  # Apply the conversion to the first column (assuming filenames are in the first column)
  data[[1]] <- sapply(data[[1]], convert_filename)
  
  # Write the updated dataset back to the file (or to a new file if preferred)
  write.csv(data, csv_file, row.names = FALSE, quote = FALSE)
}
