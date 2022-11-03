# write validation data to s3 bucket

library(tidyverse)
library(aws.s3)

# read in sheet with validation data
# 2019-12-02 validation data
sheet_url <-
  "https://docs.google.com/spreadsheets/d/1nc2nd3yIPIvIKgASB-RwPtFwOQ1rUgVEdt2CpLi7LZE/edit?usp=sharing"

labs <-
  googlesheets4::read_sheet(ss = sheet_url,
                            sheet = "label_data")

tiles <- 
  googlesheets4::read_sheet(ss = "https://docs.google.com/spreadsheets/d/1nc2nd3yIPIvIKgASB-RwPtFwOQ1rUgVEdt2CpLi7LZE/edit?usp=sharing",
                            sheet = "tile_list")


# aws set up
Sys.setenv("AWS_DEFAULT_REGION" = "us-east-2")

bucket <-
  "s3://deju-penguinscience/"

#specify the tiles object (needs updating when starting new tileset)
prefix <-
  "PenguinCounting/croz_20191202/validation_data/"

s3write_using(
  labs,
  FUN = write_delim,
  delim = ",",
  object = paste0(prefix, "croz_20191202_validation_labels.csv"),
  bucket = bucket
)

s3write_using(
  tiles,
  FUN = write_delim,
  delim = ",",
  object = paste0(prefix, "croz_20191202_validation_tile_summary.csv"),
  bucket = bucket
)

