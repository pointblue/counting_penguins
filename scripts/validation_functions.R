# Functions to select tiles to tag and track which ones still need to be done

# accessing files in s3 and google

# Function 1:
# read in pick list
# filter to files not processed
# input number of files want to download
# download files
# update list with files that have been downloaded
# update list in google
# also downloads label file for use in makesense.ai based on user input


# Function to download set of tiles and update pick list
# bucket <-
# "s3://pb-adelie/"

# prefix <-
# "1920_UAV_survey/orthomosaics/croz/191202/croz_20191202_tiles/"

# <-
#  "Antarctica/counting_penguins/croz_20191202_validation_tile_list.csv"

# set name of google sheet where tracking validation data
# data_tab <-
# "croz_20191202_validation_data"
# 
# 
# wd = "C:/Users/aschmidt/Desktop/test_images/"
# 
# Sys.setenv("AWS_DEFAULT_REGION" = "us-west-2")
# 
# id <- drive_get(data_tab)$id

tile_picker <-
  function(bucket,
           prefix,
           tile_list,
           initials,
           n,
           wd,
           file_id) {
    # required libraries
    require(tidyverse)
    require(googledrive)
    require(googlesheets4)
    require(aws.s3)
    
    # set up
    init = initials
    setwd(wd)
    
    # first need to load most current version of picklist and what is not yet tagged
    # pl <- s3read_using(
    #   read_csv,
    #   object = paste0(prefix, tile_list),
    #   bucket = bucket,
    #   col_types = cols(.default = "n", tileName = "c", initials = "c", datetime_down = "T")
    # )
    # find google sheet
    id <- 
      file_id
    pl <-
      read_sheet(ss = id,
                 sheet = "tile_list",
                 col_types = "cnncTnnnn")
    # pl <-
    #   drive_download(
    #     tile_list,
    #     path = path,
    #     overwrite = TRUE)
    
    # then select next set
    # do this randomly so aren't processing tiles sequentially
    # first filter pl to tiles that haven't yet been tagged
    set <-
      filter(pl,!downloaded == 1 &
               !tagged == 1) %>%
      slice_sample(n = n) %>%
      mutate(
        downloaded = 1,
        initials = init,
        datetime_down = Sys.time()
      )
    
    # update picklist
    pl_update <- rows_update(pl, set, by = "tileName")
    
    
    # update google sheet
    sheet_write(pl_update, ss = id, sheet = "tile_list")
    
    # # write file to s3
    # s3write_using(
    #   pl_update,
    #   FUN = write_csv,
    #   object = paste0(prefix, tile_list),
    #   bucket = bucket
    # )
    
    # download tiles
    message(paste(
      "Downloading",
      as.character(n),
      "tiles from:",
      paste0(bucket, prefix),
      "to:",
      getwd()
    ))
    
    for (i in 1:nrow(set)) {
      tile_name <-
        set$tileName[i]
      
      object <-
        paste0(prefix, tile_name, ".jpg")
      
      save_object(
        object = object,
        bucket = bucket,
        file = paste0(wd, tile_name, ".jpg")
      )
      
      # also download label file
      save_object(
        object = paste0(prefix, "label_key.txt"),
        bucket = bucket,
        file = paste0(wd, "label_key.txt")
      )
      
    }
  }

# tile_picker(
#   tile_list = data_tab,
#   bucket = bucket,
#   prefix = prefix,
#   initials = "AS",
#   wd = "C:/Users/aschmidt/Desktop/test_images/",
#   n = 5,
#   file_id = id
# )


# Function2:
# run when done with tagging session
# read in tables just created by tagging tiles
# add column with tile name and who tagged
# read in existing table in s3
# combine tables
# write updated table to s3
# update picklist with tagged

update_labs <-
  function(bucket,
           prefix,
           file_id) {
    require(tidyverse)
    require(aws.s3)
    require(googledrive)
    require(googlesheets4)
    # wd = getwd()
    id = file_id
    
    # read in label key file
    labs <-
      read_delim(
        "label_key.txt",
        delim = ",",
        col_names = "label",
        show_col_types = FALSE
      ) %>%
      mutate(lab_key = c(0, 1, 2, 3))
    
    # read in tables with annotations in file_location
    lab_tab <-
      file.choose()
    
    # unzip files to local directory
    unzip(lab_tab, exdir = getwd())
    files <- list.files(pattern = "(\\d{1,3}.txt)$")
    
    new_labs <-
      map(.x = files, ~ read_delim(.x, col_names = FALSE, show_col_types = FALSE)) %>%
      map2(.y = files, ~ mutate(.x, tileName = .y)) %>%
      bind_rows() %>%
      rename(
        lab_key = X1,
        x = X2,
        y = X3,
        width = X4,
        height = X5
      ) %>%
      # remove .txt from tileName
      mutate(tileName = str_extract(tileName, "(.+)(?=.txt)")) %>%
      left_join(labs, by = "lab_key") %>%
      select (tileName, label, x, y, width, height)
    
    
    # check if table of labels already exists
    # get google drive id for validation data sheet
    existing_labs <-
      read_sheet(ss = id,
                 sheet = "label_data",
                 col_types = "ccnnnn")
    
    # s3read_using(
    #  read_csv,
    #  object = paste0(prefix, label_tab),
    #  bucket = bucket,
    #  show_col_types = FALSE,
    #  )
    comb_labs <-
      full_join(existing_labs,
                new_labs,
                by = c("tileName", "label", "x", "y", "width", "height"))
    
    # s3write_using(
    # comb_labs,
    # FUN = write_csv,
    # object = paste0(prefix,label_tab),
    # bucket = bucket
    
    write_sheet(comb_labs, ss = id, sheet = "label_data")
    
    # update tagged column in pick list
    message("Updating tile list with tiles tagged")
    
    # create summary table of tiles tagged
    tagged <-
      comb_labs %>%
      group_by(tileName, label) %>%
      tally() %>%
      pivot_wider(names_from = label, values_from = n) %>%
      mutate(tagged = 1)
    
    # first need to load most current version of picklist and what is not yet tagged
    # pl <- s3read_using(
    #   read_csv,
    #   object = paste0(prefix, tile_list),
    #   bucket = bucket,
    #   show_col_types = FALSE
    # )
    
    pl <-
      read_sheet(ss = id,
                 sheet = "tile_list",
                 col_types = "cnncTnnnn")
    
    # update picklist
    pl_update <-
      rows_update(pl, tagged, copy = TRUE, by = "tileName")
    
    sheet_write(pl_update, ss = id, sheet = "label_data")
    
    # write file to s3
    # s3write_using(
    #   pl_update,
    #   FUN = write_csv,
    #   object = paste0(prefix, tile_list),
    #   bucket = bucket
    # )
    
    message('Ready to clear working directory? (enter [y] to clear)')
    var <- readline()
    # clear working directory
    if (var == "y") {
      file.remove(list.files())
    }
    
  }
# }


# update_labs(bucket, 
#             prefix,
#           tile_list = data_tab,
#           file_id = id)
