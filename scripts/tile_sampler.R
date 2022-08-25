# Random tile picker for selecting tiles to create validation data for penguin counting
# First draft A. Schmidt 8/17/2022


# Packages ----------------------------------------------------------------

library(tidyverse)
library(aws.s3)


# create list to pick from ------------------------------------------------
bucket = "s3://pb-adelie/"
prefix = "1920_UAV_survey/orthomosaics/croz/191202/croz_20191202_tiles/"

files <- 
  get_bucket_df(
    bucket = bucket,
    prefix = prefix,
    max = Inf
  )

# 
# files <-
#   files %>%
#   mutate(tile_name = str_replace(Key, patter = prefix, replacement = ""),
#     x = str_extract(tile_name, pattern  = "(?<=^.{14})(\\d{1,3})"),
#          y = str_extract(tile_name, pattern  = "(\\d{1,3})(?=\\.jpg)"))

# plot(files$x, files$y, pch = 19, cex=0.1, xlim = c(0,10),ylim = c(0,10))
#

# filter to remove tiles with low probability of penguins
files_filt <-
  files %>%
  #reads in size as character
  mutate(Size = as.numeric(Size)) %>% 
  # filter to size of tile likely to have penguins
  # from scanning 200 files, looks like it would be pretty safe to select tiles >60kb
  filter(Size > 60000) %>%
  # parse Key to get tile name
  mutate(tileName = str_replace(Key, pattern = prefix, replacement = "")) %>%
  # select desired columns
  select(tileName,size = Size)


# random sampler
set.seed(69)
samp <- sample(files_filt$tileName,size = 1000)

# tile pick list
pick_list <-
  filter(files_filt,tileName %in% samp) %>%
  select(tileName)

# # make a copy of files in new location in s3
# for(i in 1:nrow(pick_list)) {
#   copy_object(
#     from_object = paste0(prefix,pick_list[i,1]),
#                          to_object = paste0(prefix,"validation_set/",pick_list[i,1]),
#                         from_bucket = bucket,
#                        to_bucket = bucket
#               )
# }


# create table with tile name and x y coordinates
pick_list_df <- 
  pick_list %>%
  # add columns for coordinates
  mutate(
    # x = str_extract(tile_name, pattern  = "(?<=^.{14})(\\d{1,3})"),
    #      y = str_extract(tile_name, pattern  = "(\\d{1,3})(?=\\.jpg)"),
         # add column for whether tile has been processed and by whom
         tagged = NA,
         initials = NA,
         datetime = NA
  )
# write picklist to s3
s3write_using(pick_list_df,
              FUN = write_csv, 
              object = paste0(prefix,"validation_set/croz_20191202_pick_list.csv"),
              bucket = bucket)

# create table with labels for YOLO
yolo_labs = c("ADPE_a", "ADPE_a_stand", "ADPE_j")

labs <- 
  data.frame(yolo_labs)
s3write_using(labs,
              FUN = write_delim,
              col_names = FALSE,
              delim = ",",
              object = paste0(prefix,"validation_set/label_key.txt"),
              bucket = bucket)
              



plot(pick_list_df$x, pick_list_df$y)
