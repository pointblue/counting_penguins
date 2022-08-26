# Functions to select tiles to tag and track which ones still need to be done

# accessing files in s3

# Function 1:
# read in pick list
# filter to files not processed
# input number of files want to download
# download files
# update list with files that have been downloaded
# update list in s3
# also downloads label file for use in makesense.ai based on user input 


# Function to download set of tiles and update pick list
# bucket <-
#   "s3://pb-adelie/"
# 
# prefix <-
#   "1920_UAV_survey/orthomosaics/croz/191202/croz_20191202_tiles/"
# 
# # set desired name of picklist
# tile_list <-
#   "croz_20191202_validation_tile_list.csv"
# 
# wd = "C:/Users/aschmidt/Desktop/test_images/"

tile_picker <-
  function(bucket,
           prefix,
           tile_list,
           initials,
           n,
           wd) {
    
    # required libraries
    require(tidyverse)
    require(aws.s3)
    
    # set up
    init = initials
    setwd(wd)
    
    # first need to load most current version of picklist and what is not yet tagged
    pl <- s3read_using(
      read_csv,
      object = paste0(prefix, tile_list),
      bucket = bucket,
      show_col_types = FALSE
    )
    
    # then select next set
    # do this randomly so aren't processing tiles sequentially
    # first filter pl to tiles that haven't yet been tagged
    set <-
      filter(pl,
             !downloaded ==1 &
               ! tagged == 1) %>%
      slice_sample(n = n) %>%
      mutate(downloaded = 1,
             initials = init,
             datetime = Sys.time())
    
    # update picklist
    pl <- rows_update(pl, set, by = "tileName")
    
    # write file to s3
    s3write_using(
      pl,
      FUN = write_csv,
      object = paste0(prefix, tile_list),
      bucket = bucket
    )
    
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
#   tile_list = "croz_20191202_validation_tile_list.csv",
#   bucket = bucket,
#   prefix = prefix,
#   initials = "AS",
#   wd = "C:/Users/aschmidt/Desktop/test_images/",
#   n = 5)


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
           tile_list){
    
    
    require(tidyverse)
    require(aws.s3)
    # wd = getwd()
    
    # read in label key file
    labs <- read_delim("label_key.txt", delim = ",", col_names = "label", show_col_types = FALSE) %>%
      mutate(lab_key = c(0,1,2,3))
    
    # read in tables with annotations in file_location
    lab_tab <- 
      file.choose()
      
# unzip files to local directory
    unzip(lab_tab, exdir = getwd())
    files <- list.files(pattern = "(\\d{1,3}.txt)$")
    
    new_labs <-
      map(.x = files, ~read_delim(.x, col_names = FALSE, show_col_types = FALSE)) %>%
      map2(.y = files, ~mutate(.x, tileName = .y)) %>%
      bind_rows() %>%
      rename(lab_key = X1, x = X2, y = X3, width = X4, height = X5) %>%
      # remove .txt from tileName
      mutate(tileName = str_extract(tileName, "(.+)(?=.txt)")) %>%
      left_join(labs, by = "lab_key") %>%
      select (tileName, label, x, y, width, height)
      
      
  # check if table of labels already exists
    try(
     existing_labs <-
       s3read_using(
        read_csv,
        object = paste0(prefix, label_tab), 
        bucket = bucket,
        show_col_types = FALSE,
        )
    )
    if(exists("existing_labs")){
      comb_labs <- 
        full_join(
          existing_labs,
          new_labs,
          by = c("tileName", "label", "x", "y", "width", "height"))
    }else{
      comb_labs <- 
        new_labs
    }
    
      s3write_using(
      comb_labs,
      FUN = write_csv,
      object = paste0(prefix,label_tab),
      bucket = bucket
    )
      
    # update tagged column in pick list
    message("Updating tile list with tiles tagged")
    
    # create summary table of tiles tagged
    tagged <-
      comb_labs %>% 
      group_by(tileName, label) %>% 
      tally() %>%
      pivot_wider(names_from = label, values_from = n) %>%
      mutate(tagged =1)
    
    # first need to load most current version of picklist and what is not yet tagged
    pl <- s3read_using(
      read_csv,
      object = paste0(prefix, tile_list),
      bucket = bucket,
      show_col_types = FALSE
    ) 
    
    
    # update picklist
    pl_update <- rows_update(pl, tagged, copy = TRUE, by = tileName)
    
    # write file to s3
    s3write_using(
      pl_update,
      FUN = write_csv,
      object = paste0(prefix, tile_list),
      bucket = bucket
    )
    
    message('Ready to clear working directory? (enter [y] to clear)')
    var <- readline()
    # clear working directory
    if(var == "y") {
      file.remove(list.files())
    }
    
    }
  # }


# update_labs(bucket, prefix)

    
