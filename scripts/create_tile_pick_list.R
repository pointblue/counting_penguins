# Random tile picker for selecting tiles to create validation data for penguin counting
# First draft A. Schmidt 8/17/2022


# Packages ----------------------------------------------------------------

library(tidyverse)
library(aws.s3)


# create list to pick from ------------------------------------------------
bucket <-
  "s3://pb-adelie/"

prefix <-
  "1920_UAV_survey/orthomosaics/croz/191202/croz_20191202_tiles/"

# set desired name of picklist
pl_name <-
  "croz_20191202_validation_tile_list.csv"

# get file info from bucket location
files <- 
  get_bucket_df(
    bucket = bucket,
    prefix = prefix,
    max = Inf
  )

# filter to remove tiles with low probability of penguins
files_filt <-
  files %>%
  #reads in size as character
  mutate(Size = as.numeric(Size)) %>% 
  # filter to size of tile likely to have penguins
  # from scanning 200 files, looks like it would be pretty safe to select tiles >60kb
  filter(Size > 60000) %>%
  # parse Key to get tile name
  # mutate(tileName = str_replace(Key, pattern = prefix, replacement = "")) %>%
  # remove file extension
  mutate(tileName = str_extract(Key, "(?<=tiles/)(.+)(?=\\.jpg)")) %>%
  # mutate(tileName = str_extract(, "(.+)(?=\\.)")) %>%
  # select desired columns
  select(tileName,size = Size)


# random sampler
set.seed(69)

# tile pick list
pick_list <-
  filter(files_filt,
           !is.na(tileName)) %>%
  slice_sample(n = 1000) %>%
  select(tileName)

# create table with tile name and x y coordinates
pick_list_df <- 
  pick_list %>%
  mutate(
    # add column for whether tile has been processed and by whom
    downloaded = 0,
    tagged = 0,
    initials = NA,
    datetime = NA,
    # add columns to track how many labels of each category on each tile
    ADPE_a = NA,
    ADPE_a_stand = NA,
    ADPE_j = NA,
    no_ADPE = NA
  )

# write picklist to s3
s3write_using(pick_list_df,
              FUN = write_csv, 
              object = paste0(prefix, pl_name),
              bucket = bucket)

# create table with labels for YOLO
# these need to match the labels in the model (except for no_penguin which is not in the model)
yolo_labs = c("ADPE_a", "ADPE_a_stand", "ADPE_j", "no_ADPE")

labs <- 
  data.frame(yolo_labs)
s3write_using(labs,
              FUN = write_delim,
              col_names = FALSE,
              delim = ",",
              object = paste0(prefix,"label_key.txt"),
              bucket = bucket)
              
