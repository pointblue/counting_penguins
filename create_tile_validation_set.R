# Functions to create validation data set

# First step is to create a list of tiles to annotate for validation
# Move tiles to P drive
# select tiles for each session and track which ones are done

# tile_pick_list <-
#   function(files, pl_name) {
#     # Packages ----------------------------------------------------------------
library(tidyverse)
library(fs)
#     require(data.table) #for rbindlist
#     
# create list to pick from ------------------------------------------------
tile_path <-
  r"(D:\PenguinCounting\tiles\croz_20231127_lcc169\)"

validation_path <-
  r"(P:\S031\analyses\RI_penguin_count_UAV\validation\croz_adpe_20231127\)"

surveyId <-
  "croz_adpe_20231127"

files <-
  data.frame(tilepaths = list.files(
    tile_path,
    full.names = TRUE)) %>% 
  mutate(tileName = list.files(tile_path))

# change to df?
# filter to remove tiles with low probability of penguins

# files$Size <-
#   file.size(files$tilepaths)

files_filt <-
  files %>%
  # filter to size of tile likely to have penguins
  # from scanning 200 files, looks like it would be pretty safe to select tiles >19kb
  filter(Size > 19000) %>%
  # select desired columns
  select(tileName, size = Size)

# random sampler
set.seed(69)

# tile pick list
pick_list <-
  filter(files_filt, !is.na(tileName)) %>%
  slice_sample(n = 200) %>%
  select(tileName)

# write pick list to disk
write_csv(pick_list, paste0("validation/", surveyId,"/",surveyId,"_tile_pick_list.csv"))

# copy files to P drive
pick_list_paths <-
  paste0(tile_path, pick_list_df$tileName)
  
new_pick_list_paths <-
  paste0(validation_path,pick_list_df$tileName)



# lapply(pick_list_paths,
file_copy(pick_list_paths, new_pick_list_paths)

