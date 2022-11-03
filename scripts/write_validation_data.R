# write validation data to s3 bucket

write_val_dat <-
  function(sheet_url,
           sheet_name,
           bucket = "s3://deju-penguinscience/",
           prefix,
           region = "us-east-2"){

require(tidyverse)
require(aws.s3)

# read in sheet with validation data
sheet_url <-
  sheet_url

labs <-
  googlesheets4::read_sheet(ss = sheet_url,
                            sheet = "label_data")

tiles <- 
  googlesheets4::read_sheet(ss = sheet_url,
                            sheet = "tile_list")


# aws set up
Sys.setenv("AWS_DEFAULT_REGION" = region)

bucket <-
  bucket

#specify the tiles object (needs updating when starting new tileset)
prefix <-
  prefix

s3write_using(
  labs,
  FUN = write_delim,
  delim = ",",
  object = paste0(prefix, sheet_name, "labels.csv"),
  bucket = bucket
)

s3write_using(
  tiles,
  FUN = write_delim,
  delim = ",",
  object = paste0(prefix, sheet_name,"tile_summary.csv"),
  bucket = bucket
)
}

# Run function to write validation data
write_val_dat(
  sheet_url = "https://docs.google.com/spreadsheets/d/1X5wiX5Tw3jpLWJC9sh05_uhKSAQMDJ6pWAgL9y0j4Gk/edit?usp=sharing",
  # sheet name will have "lables.csv" and "tile_summary.csv" pasted on the end
  sheet_name = "croz_20201129_validation_",
  prefix = "PenguinCounting/croz_20201129/validation_data/"
)
