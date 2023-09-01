library(sf)
library(dplyr)
library(parallel)

preds_sf <-
  st_read("predict/2019/croz_20191202/adult_s2_best/croz_20191202_combined_predictions.shp") %>%
  mutate(PredictId = row_number()) %>% 
  rename(tileName  = tileNam,
         confidence = confdnc)

valid_sf <-
  st_read("predict/2019/croz_20191202/adult_s2_best/croz_20191202_validation_data.shp") %>%
  filter(label %in% c("ADPE_a", "ADPE_a_stand")) %>%
  mutate(ValidId = row_number())

# list of tiles that have validation data
tiles <-
  unique(valid_sf$tileName)



compute_tile_stats <- function(tile_index, tiles, preds_sf, valid_sf, conf_thresh) {
  require(sf)
  require(dplyr)
  
  tn <- tiles[tile_index]
  
  preds <- filter(preds_sf, tileName == tn, confidence > conf_thresh)
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
  
  return(data.frame(tileName = tn, tp = tp, fp = fp, fn = fn, conf_thresh = conf_thresh))
}

conf_thresh_values = seq(0.01, 0.2, by = 0.01)

no_cores <- detectCores() - 10
cl <- makeCluster(no_cores)

# Export necessary variables to the cluster
clusterExport(cl, c("tiles", "compute_tile_stats", "preds_sf", "valid_sf"))

results_list <- parLapply(cl, conf_thresh_values, function(conf) {
  valid_stats_list <- lapply(1:length(tiles), compute_tile_stats, tiles=tiles, preds_sf=preds_sf, valid_sf=valid_sf, conf_thresh=conf)
  return(do.call(rbind, valid_stats_list))
})

# Stop the cluster once finished
stopCluster(cl)

# Bind all results into one dataframe
all_results <- do.call(rbind, results_list)


# precision/recall curve
# precision = tp / (tp+fp),
# recall = tp/(tp + fn)), higher recall means your false negative rate is lower (missing fewer penguins)

results_summ <-
  all_results %>% 
  group_by(conf_thresh) %>% 
  summarise(tp_all = sum(tp), fp_all = sum(fp),
            fn_all = sum(fn),
            precision = tp_all/(tp_all+fp_all),
            recall = tp_all/(tp_all + fn_all)) %>% 
  mutate(conf_thresh = factor(conf_thresh))

ggplot(data = results_summ,
       aes(recall, precision, col = conf_thresh))+
  geom_point() +
  geom_label(aes(label = conf_thresh))+
  theme(
    legend.position = "none"
  )


# recommending 0.05 for confidence threshold