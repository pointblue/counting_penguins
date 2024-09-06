# Load necessary libraries
library(sf)
library(dbscan)
library(dplyr)
library(concaveman)
library(ggplot2)
library(RSQLite)
library(future.apply)

# Function to build the path
build_path <-
  function(colony, species, year, file_type, model = "ADPE_20231024_adult_sit") {
    # Construct the base directory path
    base_path <- "data"
    
    # List all directories in the base path
    all_dirs <-
      list.dirs(base_path, full.names = TRUE, recursive = FALSE)
    
    # Pattern to match the directories with the specified colony, species, and year
    pattern <- paste0(colony, "_", species, "_", year)
    
    # Filter directories that match the pattern and exclude directories with "01" in the date part
    matching_dirs <- all_dirs[grep(pattern, all_dirs)]
    # Pattern to specifically exclude directories with "01" as the month part
    matching_dirs <-
      matching_dirs[!grepl("_[0-9]{4}-01-", matching_dirs)]
    
    # Check if a matching directory is found
    if (length(matching_dirs) == 0) {
      stop(paste("No directories found for", colony, species, "in year", year))
    }
    
    selected_dir <-
      matching_dirs[1] # Take the first matching directory
    
    if (file_type == "manual" & colony == "croz") {
      file_path <-
        file.path(selected_dir,
                  "manual_count",
                  paste0(basename(selected_dir), "_m_occ.shp"))
    } else if (file_type == "manual" & colony == "royd") {
      file_path <-
        file.path(selected_dir,
                  "manual_count",
                  paste0(basename(selected_dir), "_occ.shp"))
    } else if (file_type == "manual" & colony == "bird") {
      file_path <-
        file.path(
          selected_dir,
          "manual_count",
          paste(
            colony,
            "north",
            species,
            substr(basename(selected_dir), 11, 20),
            "occ.shp",
            sep = "_"
          )
        )
    } else if (file_type == "predict") {
      # List all .shp files in the predict + model directory
      predict_dir <-
        list.files(
          file.path(selected_dir, paste0("predict/counts/", model, "/GIS")),
          pattern = ".shp",
          full.names = TRUE,
          recursive = TRUE
        )
      # Filter for files that contain "masked_labels_cleaned" and are shapefiles
      predict_files <-
        predict_dir[grep("masked_labels_cleaned.shp$", predict_dir)]
      
      if (length(predict_files) == 0) {
        stop("No prediction files found")
      }
      
      # Get file information, including the modification time
      file_info <- file.info(predict_files)
      
      # Find the most recent file based on the modification time
      most_recent_file <- predict_files[which.max(file_info$mtime)]
      
      # Return the path to the most recent file
      file_path <- most_recent_file
      
    } else {
      stop("Invalid file type specified")
    }
    
    if (!file.exists(file_path)) {
      stop(paste("File does not exist:", file_path))
    }
    
    return(file_path)
  }

# Main function to calculate percentage difference
calculate_perc_diff_for_year <- function(year, colony, species, predict_path = NULL) {
  tryCatch({
    # Build file paths
    manual_count_path <- build_path(colony, species, year, file_type = "manual")
    
    # Use the provided predict_path or build it if not provided
    if (is.null(predict_path)) {
      predict_count_path <- build_path(colony, species, year, file_type = "predict")
    } else {
      predict_count_path <- predict_path
    }
    
    survey_name <- substr(manual_count_path, 6, 25)
    
    # Read the shapefiles
    manual_shapefile <- st_read(manual_count_path)  # Manual count points layer
    predict_shapefile <- st_read(predict_count_path)  # Prediction points layer
    
    # Ensure shapefiles are in the same CRS
    predict_shapefile <- st_transform(predict_shapefile, crs = st_crs(manual_shapefile))
    
    # Get the bounding box (extent) of the manual shapefile
    bbox_manual <- st_bbox(manual_shapefile)
    
    # Crop the prediction shapefile to the extent of the manual shapefile
    predict_shapefile <- st_crop(predict_shapefile, bbox_manual)
    
    # Convert to spatial points
    manual_coords <- st_coordinates(manual_shapefile)
    predict_coords <- st_coordinates(predict_shapefile)
    
    # Run DBSCAN to identify clumps (adjust eps value as needed)
    manual_dbscan_result <- dbscan(manual_coords, eps = 2, minPts = 3)
    
    # Add cluster IDs to the shapefiles
    manual_shapefile$cluster <- manual_dbscan_result$cluster
    
    # Filter out noise points (cluster != 0)
    manual_shapefile <- manual_shapefile %>% filter(cluster != 0)
    
    # Create concave hulls directly using concaveman
    create_concave_hull <- function(cluster_geom) {
      points <- st_cast(cluster_geom, "POINT")
      xy <- st_coordinates(points)
      ch <- concaveman(xy, concavity = 2, length_threshold = 2)
      st_polygon(list(ch))
    }
    
    # Convert each cluster to a concave hull polygon and add buffer for manual shapefile
    manual_clump_polygons <- manual_shapefile %>%
      group_by(cluster) %>%
      summarise(geometry = st_union(geometry)) %>%
      rowwise() %>%
      mutate(geometry = st_sfc(create_concave_hull(geometry), crs = st_crs(manual_shapefile))) %>%
      st_buffer(dist = 0.5) %>%
      ungroup() %>%
      st_as_sf()
    
    # Perform spatial join to count points within each polygon from the manual shapefile
    joined_manual <- st_join(manual_shapefile, manual_clump_polygons, join = st_within)
    
    # Perform spatial join to count points within each polygon from the prediction shapefile using boundaries from the manual shapefile
    joined_predict <- st_join(predict_shapefile, manual_clump_polygons, join = st_within) %>%
      filter(!is.na(cluster))
    
    # Summarize the number of points in each polygon from the manual shapefile
    manual_point_counts <- joined_manual %>%
      group_by(cluster.y) %>%
      summarise(count_manual = n()) %>%
      rename(cluster = cluster.y)
    
    # Summarize the number of points in each polygon from the prediction shapefile
    predict_point_counts <- joined_predict %>%
      group_by(cluster) %>%
      summarise(count_predict = n())
    
    # Merge the point counts from both shapefiles
    point_counts <- select(manual_point_counts, cluster, count_manual) %>%
      as.data.frame() %>%
      full_join(as.data.frame(select(predict_point_counts, cluster, count_predict)), by = "cluster") %>%
      mutate(
        count_manual = ifelse(is.na(count_manual), 0, count_manual),
        count_predict = ifelse(is.na(count_predict), 0, count_predict)
      ) %>%
      filter(!is.na(cluster))
    
    # Write the filtered prediction points and clump polygons as shapefiles
    st_write(
      joined_predict,
      paste0("data/", survey_name, "/validate/", survey_name, "_ground_predictions.shp"),
      delete_layer = TRUE
    )
    st_write(
      manual_clump_polygons,
      paste0("data/", survey_name, "/validate/", survey_name, "_ground_polygons.shp"),
      delete_layer = TRUE
    )
    
    # Read in table with manual counts
    db <- dbConnect(SQLite(), dbname = "data/UAVSurveys.db")
    manual_cts <- dbGetQuery(db, "SELECT * from ManualCountsOccupied")
    dbDisconnect(db)
    
    std <- manual_cts %>%
      filter(Year == year, Colony == tolower(colony)) %>%
      select(Colony, StandingOccupiedCt)
    
    occ_ct <- point_counts %>%
      summarise(occupied_tot = sum(count_manual)) %>%
      mutate(occu_sit = occupied_tot - std$StandingOccupiedCt)
    
    pred_ct <- point_counts %>%
      summarise(sit_tot = sum(count_predict))
    
    perc_diff <- (pred_ct$sit_tot - occ_ct$occu_sit) / pred_ct$sit_tot
    message(paste("Prediction percent difference", colony, year, perc_diff))
    return(perc_diff)
    
  }, error = function(e) {
    message(paste("Error processing year", year, ":", e$message))
    return(NA)  # Return NA if there's an error
  })
}

