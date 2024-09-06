# Load the necessary functions and libraries
source("code/compare_manual_counts_function.R")

# Define the years, colonies, species, and predict paths
years_croz_royd <- 2018:2023
years_bird <- c(2021, 2022, 2023)

colonies <- c("croz", "royd", "bird")
species <- "adpe"

# Define the prediction paths for the bird colony
predict_paths_bird <- c(
  "data/bird_adpe_2021-12-02/predict/counts/ADPE_20231024_adult_sit/GIS_north/masked_labels_cleaned.shp",
  "data/bird_adpe_2022-11-26/predict/counts/ADPE_20231024_adult_sit/GIS/bird_north_adpe_2022-11-26_lcc169/masked_labels_cleaned.shp",
  "data/bird_adpe_2023-11-30/predict/counts/ADPE_20231024_adult_sit/GIS/bird_north_adpe_2023-11-30_lcc169/masked_labels_cleaned.shp"
)

# Initialize an empty list to store results
results_list <- list()

# Loop over colonies and years to calculate percentage difference
for (colony in colonies) {
  
  if (colony == "bird") {
    years <- years_bird
    predict_paths <- predict_paths_bird
    # Loop over years and paths to calculate percentage difference for bird colony
    for (i in seq_along(years)) {
      year <- years[i]
      predict_path <- predict_paths[i]
      
      # Calculate percentage difference for the current year
      result <- data.frame(
        Year = year,
        Colony = colony,
        Perc_Diff = calculate_perc_diff_for_year(
          year = year,
          colony = colony,
          species = species,
          predict_path = predict_path
        )
      )
      
      # Store the result in the list
      results_list[[length(results_list) + 1]] <- result
    }
    
  } else {
    years <- years_croz_royd
    
    # Loop over years to calculate percentage difference for croz and royd colonies
    result <- data.frame(
      Year = years,
      Colony = colony,
      Perc_Diff = sapply(
        years,
        calculate_perc_diff_for_year,
        colony = colony,
        species = species
      )
    )
    
    # Store the result in the list
    results_list[[length(results_list) + 1]] <- result
  }
}

# Combine all results into a single data frame
final_results <- do.call(rbind, results_list) %>% 
  mutate(CF = 1 - Perc_Diff)

# Display the final results
print(final_results)

mean(final_results$Perc_Diff)
range(final_results$Perc_Diff)

readr::write_csv(final_results, "data/manual_model_comparison_v2024-08-16.csv")


# apply correction factor to model predictions to get final count





# # Read in ground count data
# 
# db <- dbConnect(SQLite(), dbname = "data/UAVSurveys.db")
# ground_cts <- dbGetQuery(db, "SELECT * from GroundCounts")
# dbDisconnect(db)
# 
# subcol_cts <-
#   ground_cts %>% 
#   group_by(col,subcol) %>% 
#   summarise(n_subcol = n()) # some issues here, can't just compare total count in ground count becuase not every subcol counted each year
# 
# # calculate occupied to active ratio
# occ_act <-
#   ground_cts %>% 
#   group_by(col, season) %>% 
#   summarise(tot_occ = sum(occ_ct),
#             tot_act = sum(active_ct),
#             occ_act = tot_occ/tot_act)
# 
# # Calculate the mean ratio and standard error for each colony
# # Calculate the mean ratio and standard error for each colony and season
# mean_occ_act <- ground_cts %>%
#   mutate(occ_act = occ_ct/active_ct) %>% 
#   group_by(col, season) %>%
#   summarise(
#     mean_occ_act = mean(occ_act, na.rm = TRUE),
#     se_occ_act = sd(occ_act, na.rm = TRUE) / sqrt(n())
#   )
# 
# # Plotting the mean ratio of occupied to active at each colony with bars for each year
# library(ggplot2)
# 
# ggplot(mean_occ_act, aes(x = season, y = mean_occ_act, fill = col)) +
#   geom_bar(stat = "identity", position = "dodge", color = "black") +
#   geom_errorbar(aes(ymin = mean_occ_act - se_occ_act, ymax = mean_occ_act + se_occ_act), 
#                 width = 0.2, position = position_dodge(0.9)) +
#   labs(
#     title = "Mean Ratio of Occupied to Active Nests by Colony and Season",
#     x = "Season",
#     y = "Mean Ratio of Occupied to Active",
#     fill = "Colony"
#   ) +
#   theme_minimal()





  