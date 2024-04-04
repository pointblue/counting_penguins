# Install necessary packages if not already installed
if (!requireNamespace("DBI", quietly = TRUE)) install.packages("DBI")
if (!requireNamespace("RSQLite", quietly = TRUE)) install.packages("RSQLite")

# Load packages
library(DBI)
library(RSQLite)

# Connect to the database
# Replace 'path_to_your_database.db' with the actual path to your UAVSurveys database
con <- dbConnect(RSQLite::SQLite(), dbname = "data/UAVSurveys.db")

# Retrieve SurveyIds
# This SQL query assumes 'SurveyId' is a column in your 'Surveys' table
query <- "SELECT DISTINCT SurveyId FROM Surveys"
survey_ids <- dbGetQuery(con, query)

# Close the database connection
dbDisconnect(con)

# Create directories for each SurveyId in a specified parent directory
# Replace 'path_to_parent_directory' with your desired path
parent_directory <- "data"
if (!dir.exists(parent_directory)) {
  dir.create(parent_directory)
}

subdirectories <- c("predict", "validate")

for (survey_id in survey_ids$SurveyId) {
  # Create the main directory for each SurveyId
  survey_dir_path <- file.path(parent_directory, as.character(survey_id))
  if (!dir.exists(survey_dir_path)) {
    dir.create(survey_dir_path)
  }
  
  # Create subdirectories within each SurveyId directory
  for (subdir in subdirectories) {
    subdir_path <- file.path(survey_dir_path, subdir)
    if (!dir.exists(subdir_path)) {
      dir.create(subdir_path)
    }
  }
}