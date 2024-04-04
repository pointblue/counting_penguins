
# Description -------------------------------------------------------------


# functions to create shapefiles from validation data and matching predictions to evaluate model performance and calculate best threshold to use
# both functions expect same arguments
# db_name = path to database where survey data stored
# colony = 4-letter colony code lower case
# date = YYYY-mm of survey of interest
#
# AS 3/2024


# Functions ---------------------------------------------------------------


create_validation_shapefiles <- function(db_name, colony, date) {
  # Required Libraries ------------------------------------------------------
  require(sf)
  require(tidyverse)
  require(RSQLite)
  require(terra)
  require(sp)
  
  # Connect to UAV survey db ------------------------------------------------
  db <- dbConnect(SQLite(), dbname = db_name)
  
  # List of surveys in db
  survey_ls <- dbGetQuery(db, "SELECT * FROM Surveys")
  
  # Get survey ID
  survey <- survey_ls %>%
    filter(str_detect(SurveyId, glue::glue("{colony}_.*_{date}"))) %>%
    pull(SurveyId)
  
  valid_dir <- paste("data", survey, "validate", sep = "/")
  
  valid_labs <-
    list.files(valid_dir, pattern = "^label.*\\.csv$", full.names = TRUE) %>%
    read_csv()
  
  names(valid_labs) <-
    c(
      "label_name",
      "bbox_x",
      "bbox_y",
      "bbox_width",
      "bbox_height",
      "tileName",
      "image_width",
      "image_height"
    )
  
  predict_dir <-
    paste("data", survey, "predict", sep = "/")
  
  
  # Get pixel size of orthos
  ortho_info <-
    list.files(predict_dir, pattern = "OrthoInfo", full.names = TRUE) %>%
    map(.,
        ~ read_csv(.x, show_col_types = FALSE) %>% mutate(file_name = basename(.x))) %>%
    bind_rows() %>%
    mutate(ortho_name = sub("^(.*?)_OrthoInfo\\.csv$", "\\1", file_name)) %>%
    select(-file_name)  # Remove the original file_name column
  
  proj <- CRS(ortho_info$crs_r[1])
  
  georef_ls <-
    list.files(predict_dir, pattern = "tilesGeoref", full.names = TRUE)
  
  reformat_string <- function(old_string) {
    if (startsWith(old_string, "bird")) {
      new_string <-
        str_replace(
          old_string,
          "^(bird)_(middle|north|south)_(\\d{4})(\\d{2})(\\d{2})_(.*)\\.jpg$",
          "\\1_\\2_adpe_\\3-\\4-\\5_\\6"
        )
      if (grepl("middle", new_string)) {
        # Replace "middle" with "mid"
        new_string <- gsub("middle", "mid", new_string)
      }
      
    } else if (startsWith(old_string, "croz") ||
               startsWith(old_string, "royd")) {
      new_string <-
        str_replace(
          old_string,
          "^(croz|royd)_((?:middle|north|south)_)?(\\d{4})(\\d{2})(\\d{2})_(.*)\\.jpg$",
          "\\1_\\2adpe_\\3-\\4-\\5_\\6"
        )
      # Replace "middle" with "mid" if it's present in the new string
      if (grepl("middle", new_string)) {
        new_string <- gsub("middle", "mid", new_string)
      }
    }
    # Remove .jpg at the end
    new_string <- gsub("\\.jpg$", "", new_string)
    return(new_string)
  }
  
  georef <- map_dfr(georef_ls, read_csv, show_col_types = FALSE)
  
  # Apply the function to the column of strings
  georef$tileName <- sapply(georef$tileName, reformat_string)
  
  # Assuming georef is the table with upper-left corner coordinates of each tile
  # and valid_labs is the table with label box coordinates relative to the upper-left corner of each tile
  valid_labs_coords <-
    valid_labs %>%
    mutate(tileName = gsub("\\.jpg$", "", tileName)) %>%
    inner_join(georef, . , by = "tileName") %>%
    mutate(ortho_name = sub("^(.*?)_\\d+_\\d+$", "\\1", tileName)) %>%
    left_join(ortho_info) %>%
    mutate(
      left_geo = easting + bbox_x * xres,
      top_geo = northing - bbox_y * yres,
      # Subtract because y-coordinate increases downward in pixel space
      right_geo = left_geo + bbox_width * xres,
      bottom_geo = top_geo - bbox_height * yres
    )
  
  
  
  # Create polygons
  valid_polygons_list <-
    lapply(1:nrow(valid_labs_coords), function(i) {
      sp::Polygon(cbind(
        c(
          valid_labs_coords$left_geo[i],
          valid_labs_coords$right_geo[i],
          valid_labs_coords$right_geo[i],
          valid_labs_coords$left_geo[i],
          valid_labs_coords$left_geo[i]
        ),
        c(
          valid_labs_coords$bottom_geo[i],
          valid_labs_coords$bottom_geo[i],
          valid_labs_coords$top_geo[i],
          valid_labs_coords$top_geo[i],
          valid_labs_coords$bottom_geo[i]
        )
      ))
    })
  
  # Convert list of polygons to SpatialPolygons
  valid_sp_polygons <-
    SpatialPolygons(lapply(1:length(valid_polygons_list), function(i) {
      Polygons(list(valid_polygons_list[[i]]), ID = as.character(i))
    }), proj4string = proj)
  
  valid_sp_polygons_df <-
    SpatialPolygonsDataFrame(valid_sp_polygons, data = valid_labs_coords)
  
  # Convert the SpatialPolygonsDataFrame to an sf object
  valid_sf_object <- st_as_sf(valid_sp_polygons_df)
  
  # Write the polygons to a shapefile
  st_write(
    valid_sf_object,
    paste0("data/", survey, "/validate/", survey, "_validation", ".shp"),
    append = FALSE
  )
  
  # Convert prediction labels to shapefile ----------------------------------
  
  # Get model name
  predictions <- dbGetQuery(db, "SELECT * FROM ModelPredictions")
  model <- predictions %>%
    filter(SurveyId == survey) %>%
    pull(ModelName) %>%
    .[1]
  
  pred_labs_dir <-
    paste(predict_dir, "counts", model, "labels", sep = "/")
  
  # Table with prediction labels
  pred_labs <-
    list.files(pred_labs_dir,
               pattern = paste(sub("\\.jpg$", "", valid_labs$tileName), collapse = "|"),
               full.names = TRUE) %>%
    map(.,
        ~ read_delim(
          .x,
          col_names = c(
            "class",
            "bbox_x",
            "bbox_y",
            "bbox_width",
            "bbox_height",
            "conf"
          ),
          col_types = cols(.default = "n")
        ) %>%
          mutate(file_name = basename(.x))) %>%
    bind_rows() %>%
    mutate(ortho_name = sub("^(.*?)_\\d+_\\d+\\.txt$", "\\1", file_name))
  
  # Calculate coordinates
  pred_labs_coords <- pred_labs %>%
    mutate(tileName = gsub("\\.txt$", "", file_name)) %>%
    inner_join(georef, . , by = "tileName") %>%
    left_join(ortho_info) %>%
    mutate(
      image_width = valid_labs$image_width[1],
      image_height = valid_labs$image_height[1],
      half_width = bbox_width * xres * image_width / 2,
      # Half the width of the bounding box
      half_height = bbox_height * yres * image_height / 2,
      # Half the height of the bounding box
      left_geo = easting + (bbox_x * xres * image_width) - half_width,
      top_geo = northing - (bbox_y * yres * image_height) + half_height,
      right_geo = easting + (bbox_x * xres * image_width) + half_width,
      bottom_geo = northing - (bbox_y * yres * image_height) - half_height
    )
  
  # Create polygons
  pred_polygons_list <-
    lapply(1:nrow(pred_labs_coords), function(i) {
      sp::Polygon(cbind(
        c(
          pred_labs_coords$left_geo[i],
          pred_labs_coords$right_geo[i],
          pred_labs_coords$right_geo[i],
          pred_labs_coords$left_geo[i],
          pred_labs_coords$left_geo[i]
        ),
        c(
          pred_labs_coords$bottom_geo[i],
          pred_labs_coords$bottom_geo[i],
          pred_labs_coords$top_geo[i],
          pred_labs_coords$top_geo[i],
          pred_labs_coords$bottom_geo[i]
        )
      ))
    })
  
  # Convert list of polygons to SpatialPolygons
  pred_sp_polygons <-
    SpatialPolygons(lapply(1:length(pred_polygons_list), function(i) {
      Polygons(list(pred_polygons_list[[i]]), ID = as.character(i))
    }), proj4string = proj)
  
  pred_sp_polygons_df <-
    SpatialPolygonsDataFrame(pred_sp_polygons, data = pred_labs_coords)
  
  # Convert the SpatialPolygonsDataFrame to an sf object
  pred_sf_object <- st_as_sf(pred_sp_polygons_df)
  
  # Write the polygons to a shapefile
  st_write(
    pred_sf_object,
    paste0(
      "data/",
      survey,
      "/validate/",
      survey,
      "_predictions_to_validate",
      ".shp"
    ),
    append = FALSE
  )
  
  # Close the database connection
  dbDisconnect(db)
  
}



compute_threshold_results <- function(db_name, colony, date) {
  # Required Libraries ------------------------------------------------------
  require(sf)
  require(tidyverse)
  require(parallel)
  require(RSQLite)
  
  # Connect to UAV survey db ------------------------------------------------
  db <- dbConnect(SQLite(), dbname = db_name)
  
  # Get survey ID
  survey_ls <- dbGetQuery(db, "SELECT * FROM Surveys")
  survey <- survey_ls %>%
    filter(str_detect(SurveyId, glue::glue("{colony}_.*_{date}"))) %>%
    pull(SurveyId)
  
  # Build paths
  pred_path <-
    paste0("data/",
           survey,
           "/validate/",
           survey,
           "_predictions_to_validate.shp")
  valid_path <-
    paste0("data/", survey, "/validate/", survey, "_validation.shp")
  
  # Read data
  preds_sf <- st_read(pred_path) %>%
    mutate(PredictId = row_number()) %>%
    rename(tileName  = tileNam,
           confidence = conf)
  
  valid_sf <- st_read(valid_path) %>%
    mutate(ValidId = row_number()) %>%
    rename(tileName  = tileNam)
  
  # List of tiles that have validation data
  tile_ls <- unique(valid_sf$tileName)
  
  compute_tile_stats <-
    function(tile_index,
             tiles,
             preds_sf,
             valid_sf,
             conf_thresh) {
      require(sf)
      require(dplyr)
      
      tn <- tiles[tile_index]
      
      preds <-
        filter(preds_sf, tileName == tn, confidence > conf_thresh)
      valids <- filter(valid_sf, tileName == tn)
      
      inter <- st_intersection(preds, valids) %>%
        mutate(area_overlap = as.numeric(st_area(geometry))) %>%
        filter(area_overlap > 0.05) %>%
        group_by(ValidId) %>%
        arrange(area_overlap) %>%
        slice_tail(n = 1)
      
      tp <- nrow(inter)
      fp <- nrow(preds) - nrow(inter)
      fn <- nrow(valids) - tp
      
      return(data.frame(
        tileName = tn,
        tp = tp,
        fp = fp,
        fn = fn,
        conf_thresh = conf_thresh
      ))
    }
  
  conf_thresh_values <- seq(0.3, 1, by = 0.01)
  
  no_cores <- detectCores() - 10
  cl <- makeCluster(no_cores)
  
  # Export necessary variables to the cluster
  clusterExport(
    cl,
    c(
      "tile_ls",
      "compute_tile_stats",
      "preds_sf",
      "valid_sf",
      "conf_thresh_values"
    ),
    envir = environment()
  )
  
  results_list <-
    parLapply(cl, conf_thresh_values, function(conf) {
      valid_stats_list <-
        lapply(
          1:length(tile_ls),
          compute_tile_stats,
          tiles = tile_ls,
          preds_sf = preds_sf,
          valid_sf = valid_sf,
          conf_thresh = conf
        )
      return(do.call(rbind, valid_stats_list))
    })
  
  
  # Stop the cluster once finished
  stopCluster(cl)
  
  # Bind all results into one dataframe
  all_results <- do.call(rbind, results_list)
  
  # Compute precision/recall curve
  results_summ <- all_results %>%
    group_by(conf_thresh) %>%
    summarise(
      tp_all = sum(tp),
      fp_all = sum(fp),
      fn_all = sum(fn),
      actual_positive = tp_all + fn_all,
      total_positive = tp_all + fp_all,
      precision = tp_all / total_positive,
      recall = tp_all / actual_positive
    ) %>%
    mutate(
      conf_thresh = conf_thresh,
      # correction factor = fraction to adjust by to get real number. Real number is tp + fn
      # real/estimate
      correction_fact = actual_positive / total_positive,
      FScore = (2 * precision * recall / (precision + recall))
    )
  
  # Write results to a CSV file
  write_csv(
    results_summ,
    paste0(
      "data/",
      survey,
      "/validate/",
      survey,
      "_threshold_results.csv"
    )
  )
  

  # Calculate values at threshold that maximizes F1Score
  selected_thresh <-
    max(results_summ$conf_thresh[results_summ$FScore == max(results_summ$FScore, na.rm = TRUE)], na.rm = TRUE)
  
  F1Score <-
    round(results_summ$FScore[which.max(results_summ$FScore)], 4)
  Precision <-
    round(results_summ$precision[which.max(results_summ$FScore)], 4)
  Recall <-
    round(results_summ$recall[which.max(results_summ$FScore)], 4)
  
  # Plot precision/recall curve
  recall_precision_plot <-
    ggplot(data = results_summ, aes(recall, precision, col = conf_thresh)) +
    geom_point(na.rm = TRUE) +  # Remove missing values
    geom_label(aes(label = conf_thresh), na.rm = TRUE) +  # Remove missing values
    theme(legend.position = "none")
  
  f_score_plot <-
    ggplot(data = results_summ, aes(conf_thresh, FScore, col = conf_thresh)) +
    geom_point(na.rm = TRUE) +  # Remove missing values
    geom_text(aes(
      x = conf_thresh[10],
      y = 0.5,
      label = paste("Selected Threshold =", selected_thresh)
    )) +
    theme(
      legend.position = "none",
      axis.text.x = element_text(
        angle = 90,
        vjust = 0.5,
        hjust = 1
      )
    )
  
  # Write plots as JPEG files
  ggsave(
    filename = paste0(
      "data/",
      survey,
      "/validate/",
      survey,
      "_precision_recall.jpeg"
    ),
    plot = recall_precision_plot,
    width = 8,
    height = 6,
    units = "in",
    dpi = 150
  )
  ggsave(
    filename = paste0("data/", survey, "/validate/", survey, "_FScores.jpeg"),
    plot = f_score_plot,
    width = 8,
    height = 4,
    units = "in",
    dpi = 150
  )
  
  
  # Write plots as JPEG files
  ggsave(
    filename = paste0(
      "data/",
      survey,
      "/validate/",
      survey,
      "_precision_recall.jpeg"
    ),
    plot = recall_precision_plot,
    width = 8,
    height = 6,
    units = "in",
    dpi = 150
  )
  ggsave(
    filename = paste0("data/",
                      survey,
                      "/validate/",
                      survey,
                      "_FScores.jpeg"),
    plot = f_score_plot,
    width = 8,
    height = 4,
    units = "in",
    dpi = 150
  )

  # Write values to human labels table in db
  query <- glue::glue("
    UPDATE ModelPredictions
    SET F1Score = {F1Score}, Precision = {Precision}, Recall = {Recall}, Threshold = {selected_thresh}
    WHERE SurveyId = '{survey}'
  ")
  dbExecute(db, query)
    
  # Close the database connection
  dbDisconnect(db)
  
  message("Selected threshold for max F1Score = ", selected_thresh)
  message("F1Score = ", F1Score)
  message("Precision = ", Precision)
  message("Recall = ", Recall)

}
