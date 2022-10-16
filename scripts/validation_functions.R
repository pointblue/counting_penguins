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

tile_picker <-
  function(bucket,
           prefix,
           tile_list,
           file_id,
           initials = NA,
           wd) {
    # required libraries
    require(tidyverse)
    require(googledrive)
    require(googlesheets4)
    require(aws.s3)
    
    # check if provided path for images has trailing slash
    if(substr(wd, nchar(wd), nchar(wd)) == "\\" |
        substr(wd, nchar(wd), nchar(wd)) == "/") {
    setwd(wd)
    }else{
      message(
        "Warning: working directory path missing trailing slash, please add and re-save to environment before continuing"
      )
    }
    stopifnot(substr(wd, nchar(wd), nchar(wd)) == "\\" |
                substr(wd, nchar(wd), nchar(wd)) == "/")
    
    
    # set temp working dir
    setwd(wd)
    
    # set initials
    if (is.na(initials)) {
      init = readline(prompt = "Please provide your initials (all caps):")
      
    } else{
      init = initials
    }
    # Ask how many images want to download
    n = as.numeric(readline(prompt = "How many images would you like to download?"))
    
    # find google sheet based on url
    id <-
      file_id
    pl <-
      read_sheet(ss = id,
                 sheet = "tile_list",
                 col_types = "cnncTnnnn")
    
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
    
    # download tiles
    message(paste(
      "Downloading",
      as.character(n),
      "tiles from:",
      paste0(bucket, prefix),
      "to:",
      getwd()
    ))
    
    if (length(list.files(pattern = ".jpg")) > 0) {
      dl <- readline(prompt =
                       "Warning: working directory contains image tiles already \nWould you like to proceed with downloading more?")
    } else{
      dl <- "y"
    }
    if (dl == "y") {
      # download tiles from s3 bucket
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
      }
      
      # also download label file
      if (file.exists("label_key.txt")) {
        message("label_key.txt file already in wd")
      } else{
        save_object(
          object = paste0(prefix, "label_key.txt"),
          bucket = bucket,
          file = paste0(wd, "label_key.txt"),
          overwrite = TRUE
        )
       } 
        # update downloaded field in picklist
        pl_update <- rows_update(pl, set, by = "tileName")
        
        # update google sheet
        sheet_write(pl_update, ss = id, sheet = "tile_list")
      
    } else {
      message("Download aborted, please upload labels to clear working directory")
    }
    
    
    
  }
    
    # Function2:
    # run when done with tagging session
    # read in tables just created by tagging tiles
    # add column with tile name and who tagged
    # read in existing table in s3
    # combine tables
    # write updated table to google
    # update picklist with tagged
    # summarize how many tiles remain
    
update_labs <-
  function(bucket,
           prefix,
           file_id,
           wd) {
    # libraries required
    require(tidyverse)
    require(aws.s3)
    require(googledrive)
    require(googlesheets4)
    
    # set temp working dir
    wd = setwd(wd)
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
    
    # format labels for table
    new_labs <-
      map(.x = files,
          ~ read_delim(.x, col_names = FALSE, show_col_types = FALSE)) %>%
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

    
    # in case the same set of labels gets uploaded again, read in label sheet
    # append new data 
    # and remove dups and overwrite
    read_sheet(ss = id,
               sheet = "label_data",
               col_types = "ccnnnn") %>%
      # append new data to existing label data sheet
      bind_rows(new_labs) %>%
      distinct() %>%
      sheet_write(ss = id, sheet = "label_data")
    
    # update tagged column in pick list
    message("Updating tile list with tiles tagged")
    
    # create summary table of tiles tagged
    tagged <-
      new_labs %>%
      group_by(tileName, label) %>%
      tally() %>%
      pivot_wider(names_from = label, values_from = n) %>%
      mutate(tagged = 1)
    
    # read in tile list again
    pl <-
      read_sheet(ss = id,
                 sheet = "tile_list",
                 col_types = "cnncTnnnn")
    
    # update picklist
    pl_update <-
      rows_update(pl, tagged, copy = TRUE, by = "tileName")
    
    # overwite tile list with updated data
    sheet_write(pl_update, ss = id, sheet = "tile_list")
    
    #summarize how many tiles tagged
    tot_tag <-
      filter(pl_update, tagged == 1) %>%
      nrow()
    
    # print summary of how many updated and how many tiles remain
    message(
      paste(
        "Updated labels for",
        nrow(tagged),
        "tiles",
        "\n",
        tot_tag,
        "of",
        nrow(pl),
        paste0("(", tot_tag * 100 / nrow(pl), "%", ")"),
        "complete"
      )
    )
    
    # print summary of how many tiles processed by initials
    pl_inits <- 
      pl_update %>%
      group_by(initials) %>% 
      tally()
    
    message("Tally by initials:")
    print(as.data.frame(pl_inits))
    
    #make a chart
    fig1<-
      pl_inits %>%
      filter(!is.na(initials)) %>%
      ggplot(aes(x=initials, y=n, fill=initials)) +
      geom_bar(stat="identity", color="black") +
      scale_fill_brewer(palette="Set2") +
      ggtitle(paste0(prefix,": n counted by initials")) +
      theme_minimal()
    
    print(fig1)
    
    # prompt to clear working directory
    var <-
      readline(prompt = 'Ready to clear working directory? (enter [y] to clear)')
    # clear working directory
    if (var == "y") {
      unlink(list.files(), force = TRUE)
    }
    if (length(list.files()) > 0) {
      file_ls <- list.files()
      message(paste(
        "working directory not cleared",
        "\n files remaining:",
        file_ls
      ))
    } else {
      message("working directory cleared")
    }
  }
