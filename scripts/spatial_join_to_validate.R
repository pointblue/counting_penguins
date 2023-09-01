
library(sf)
library(dplyr)

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

# create data.frame to hold validation stats
# tp = true positive (labeled in both prediction and validation)
# fp = false positive (in prediction but not validation data)
# fn = false negative (not labeled in prediction but labeled in validation)
# conf_thresh = confidence threshold examined

conf_thresh = seq(0.01, 0.13, by = 0.01)

valid_stats <-
  data.frame(tileName = NA, tp = NA, fp = NA, fn = NA, conf_thresh = NA)
             
             # precision = tp / (tp+fp),
             # recall = tp/(tp + fn))

for (j in 1:length(conf_thresh)) {
  conf = conf_thresh[j]
  for (i in 1:length(tiles)) {
    # pull out tile name
    tn <-
      tiles[i]
    print(paste(conf, i,tn))
    # filter to predictions for that tile
    preds <-
      filter(preds_sf, tileNam == tn,
             confdnc > conf)
    # filter to validation data from that tile
    valids <-
      filter(valid_sf, tileName == tn)
    
    # 
    # # Calculate the intersection of the two polygons
    # intersection_area <- st_area(st_intersection(preds, valids))
    # 
    # # Calculate the union of the two polygons
    # union_area <- st_area(st_union(preds, valids))
    # 
    # # Compute the IoU
    # iou <- intersection_area / union_area
    
    
    # create object with intersection
    # has column for valid ID, with row for each intersection of that validation label
    # so can have multiple rows for each validation label (ID)
    inter <-
      st_intersection(preds, valids) %>%
      mutate(area_overlap = as.numeric(st_area(geometry))) %>% 
      # flag valid overlap, less than threshold means overlapping with an adjacent label
      filter(area_overlap > 0.05) %>%
      group_by(ValidId) %>%
      arrange(area_overlap) %>%
      slice_tail(n =1)

    #true positives
    tp <-
      inter %>% 
      # filter(inter, valid == 1) %>%
      nrow()
    
    
    # false positives
    fp = nrow(preds) - nrow(inter)
    
    # false negatives
    
    fn <-
      nrow(valids) - tp
    
    # validations stats by tile
    valid_stats[i,] <- c(tileName = tn,tp = tp,  fp = fp, fn = fn, conf_thresh = conf)
  }
}
plot(preds$geometry, col = "blue")
plot(valids$geometry, col = "pink", add = TRUE)
plot(inter$geometry, border = "red", add = TRUE, lwd = 3) 
t <-filter(inter, valid == 0)
  plot(t$geometry, border = "green", add = TRUE, lwd = 3)
