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

tile_picker <-
  function(bucket, 
           prefix, 
           pick_list,
           initials, 
           n, 
           working_dir){
    require(tidyverse)
    require(aws.s3)
    init = initials
    setwd(working_dir)
    # first need to load most current version of picklist and what is not yet tagged
    pl <-s3read_using(read_csv, 
                      object = paste0(prefix, "validation_set/",pick_list), 
                      bucket = bucket,
                      show_col_types = FALSE)
    # then select next set
    # do this randomly so aren't processing tiles sequentially
    #first filter pl to tiles that haven't yet been tagged
    set <- 
      filter(pl,
             is.na(tagged))%>%
      slice_sample(n=n) %>%
      mutate(
        tagged = 1,
        initials = init,
        datetime = Sys.time()
      )
    
    # update picklist
    pl <- rows_update(pl,set)
    # write file to s3
    s3write_using(pl,
                  FUN = write_csv, 
                  object = paste0(prefix, pick_list),
                  bucket = bucket)
    # download tiles
    message(paste("Downloading",as.character(n),"tiles from:", paste0(bucket,prefix,"validation_set"), "to:", getwd()))
    for(i in 1:nrow(set)){
      tile_name = set$tile_name[i]
      object = paste0(prefix,tile_name)
      save_object(
        object = object,
        bucket = bucket,
        file = paste0(working_dir,tile_name)
      )
      # also download label file
      save_object(
        object = paste0(prefix,"validation_set/label_key.txt"),
        bucket = bucket,
        file = paste0(working_dir,"label_key.txt")
      )
        
      
    }
  }

# tile_picker(
  # pick_list = "croz_20191202_pick_list.csv",
  # bucket = bucket,
  # prefix = prefix,
  # initials = "AS",
  # working_dir = "C:/Users/aschmidt/Desktop/test_images/",
  # n = 5)
  #   

# Function2:
# run when done with tagging session
# read in tables just created by tagging tiles
# add column with tile name and who tagged
# read in existing table in s3
# combine tables
# write updated table to s3

update_labs <- 
  function(bucket,
           prefix){
    require(tidyverse)
    require(aws.s3)
    dir = getwd()
    
    # read in label key file
    labs <- read_delim("label_key.txt", delim = ",", col_names = "label", show_col_types = FALSE) %>%
      mutate(lab_key = c(0,1,2))
    
    # read in tables with annotations in file_location
    file_ls <- 
      # list.files(pattern = ".zip")
      file.choose()
    # if(length(file_ls) > 1) {
    #   message("Warning: multiple label.zip files exist, only most recent will be used")
    # } else {
    # if(length(file_ls) == 0){
    #   readline(prompt=message('There is no zipped label file. Move labels.zip file from downloads and press [enter]'))
    # }
      
# unzip files to local directory
    unzip(file_ls[1], exdir = getwd())
    files <- list.files(pattern = "(\\d{1,3}.txt)$")
    

    new_labs <-
      map(.x = files, ~read_delim(.x, col_names = FALSE, show_col_types = FALSE))%>%
      map2(.y = files, ~mutate(.x, tileName = .y)) %>%
      bind_rows() %>%
      rename(lab_key = X1, x = X2, y = X3, width = X4, height = X5) %>%
      left_join(labs) %>%
      
      
  # check if table of labels already exists
    try(
     existing_labs <-
       s3read_using(
        read_csv,
        object = paste0(prefix, "validation_set/validation_labels.csv"), 
        bucket = bucket,
        show_col_types = FALSE,
        )
    )
    if(exists("existing_labs")){
      comb_labs <- 
        full_join(
          existing_labs,
          new_labs)
    }else{
      comb_labs <- 
        new_labs
    }
    
      s3write_using(
      comb_labs,
      FUN = write_csv,
      object = paste0(prefix,"validation_set/validation_labels.csv"),
      bucket = bucket
    )
    message('Ready to clear working directory? (enter "y" to proceed)')
    var <- readline()
    # clear working directory
    if(var == "y") {
      file.remove(list.files())
    }
    
    }
  # }


# update_labs(bucket, prefix)

    
