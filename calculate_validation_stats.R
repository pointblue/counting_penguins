# Script to run validation functions

#1. Source validation function
source("code/validation_functions.R")

#2. Set argument values

db_name = "data/UAVSurveys.db"
colony = "bird"
date = "2022-11"

#3. Call first function to create shapefiles of predictions and validation data

create_validation_shapefiles(db_name = db_name, colony = colony, date = date)

#4. Run next function to calculate threshold to get max F1 Score

compute_threshold_results(db_name = db_name, colony = colony, date = date)

#5. Check threshold, precision and recall values in modelPredictions table in database
# If survey/ortho has an Adult count, move to notes and clear cell
