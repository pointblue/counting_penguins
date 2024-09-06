# Select a random set of 200 tiles for validating labels
# from each survey that is listed in the SurveyId column of the SurveyImagery 
# table in the UAVSurveys database (SQLite) and which were conducted in November 
# or December and which contains "adpe" in the SurveyId. Also need the matching
# YOLO labels for those tiles as a starting point. 
# The tiles are .jpg format and are stored on S3 within the bucket:
# deju-penguinscience/PenguinCounting.
# The YOLO labels are stored locally in the "predict" folder for each survey
# Grant - March 2024

library(DBI)
library(RSQLite)
library(aws.s3)
library(stringr)
library(data.table)

# Set up to loop through all the surveys - make a list of the surveys and
# the paths to their tiles on S3

# Connect to the SQLite database
conn <- dbConnect(RSQLite::SQLite(), "data/UAVSurveys.db")

# Set the correct AWS region and bucket_name where the tiles are stored
Sys.setenv("AWS_DEFAULT_REGION" = "us-east-2") 
bucket_name <- "deju-penguinscience" 

# Query to select surveys based on your criteria (e.g., nov/dec only?)
# query <- "
# SELECT DISTINCT SurveyId, TilesLoc
# FROM SurveyImagery
# WHERE (SurveyId like('%-11-%') OR SurveyId like('%-12-%'))
# AND SurveyId like('%adpe%')
# AND TilesLoc > ''
# "

# for testing or pulling a single survey:
query <- "
SELECT DISTINCT SurveyId, TilesLoc
FROM SurveyImagery
WHERE (SurveyId = 'bird_adpe_2021-12-02')
AND SurveyId like('%adpe%')
AND TilesLoc > ''
"

surveys <- dbGetQuery(conn, query)

# Close the database connection
dbDisconnect(conn)

for (i in 1:nrow(surveys)) {
  survey_id <- surveys$SurveyId[i]
  folder_name <- surveys$TilesLoc[i]  # S3 folder path
  
  # List all files in the S3 directory
  all_files <- rbindlist(get_bucket(bucket = bucket_name, prefix = folder_name, max = Inf))$Key
  file_names <- basename(all_files)
  jpg_files <- file_names[grepl("\\.jpg$", file_names, ignore.case = TRUE)]
  
  # Randomly select 200 tiles (or fewer if not enough are available)
  selected_files <- sample(jpg_files, min(200, length(jpg_files)))
  
  # Define the local directory path based on the SurveyId
  local_dir <- paste0("data/", survey_id, "/validate/tiles/")
  
  # Then create the directory (note that this doesn't work if you already have the directory!)
  dir.create(local_dir, recursive = TRUE)
  
  # Download each selected file
  downloaded_tiles <- c() # Keep track of successfully downloaded tiles
  for (file_name in selected_files) {
    # Construct the full S3 key for the file
    s3_key <- paste0(folder_name, file_name)
    
    # Define the local file path
    local_file_path <- paste0(local_dir, file_name)
    
    # Download the file from S3
    save_object(object = s3_key, bucket = bucket_name, file = local_file_path)
    downloaded_tiles <- c(downloaded_tiles, local_file_path)
    cat("Downloaded ", file_name, " to ", local_file_path, "\n")
  }
  # Match and copy label files for downloaded tiles
  for (tile_path in downloaded_tiles) {
    # Assuming label naming convention and structure, adjust paths accordingly
    label_file_name <- gsub("tiles", "labels", basename(tile_path))
    label_file_name <- sub("\\.jpg$", ".txt", label_file_name)
    local_label_source_path <- gsub("/validate/tiles/", "/predict/counts/ADPE_20231024_adult_sit/labels/", tile_path)
    local_label_source_path <- sub("\\.jpg$", ".txt", local_label_source_path)
    
    local_label_dest_path <- paste0(local_dir, label_file_name)
    
    if (file.exists(local_label_source_path)) {
      # Read the label file, assuming it's space-separated with no header
      labels <- read.table(local_label_source_path, header = FALSE)
      
      # Remove the 6th column
      if (ncol(labels) >= 6) {
        labels <- labels[,-6]
      }
      
      # Write the modified labels back to the destination path
      write.table(labels, file = local_label_dest_path, row.names = FALSE, col.names = FALSE, quote = FALSE, sep = " ")
      cat("Processed and copied label: ", label_file_name, "\n")
    } else {
      cat("Label file does not exist: ", local_label_source_path, "\n")
    }
  }
}


