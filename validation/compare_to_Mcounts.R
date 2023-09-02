# Compare manual count of M in UAV image and Predictions

library(sf)
library(dplyr)
# specify confidence threshold (determined from model evaluation code)
conf_thresh <-
  0.05

# load in predictions
preds <-
  st_read("predict/2019/croz_20191202/adult_s2_best/de_duplicated_nests_smaller_v7.shp") %>% 
# filter to confidence > 0.05
  filter(confdnc > conf_thresh)

# load in M manual count point shapefile
count <-
  st_read("manual_counts/GIS/Crozier UAV Manual Counts/croz_occ_1920_20191202_amc.shp")

# check that projection is the same
st_crs(preds) == st_crs(count)
# load in M count polygon boundaries (created in Arc using aggregate points with
# 3m boundary on the count point shapefile)
m_bound <-
  st_read("manual_counts/GIS/Crozier UAV Manual Counts/croz_20191202_count_aggregate.shp") %>% 
  mutate(PolyId = row_number())

st_crs(preds) == st_crs(m_bound)


# intersect to count how many labels in each subcol and how many points

# Join points to polygons based on spatial location
# Count the number of points within each polygon
count_data <- 
  st_join(m_bound, count) %>%
  group_by(PolyId) %>%
  summarise(n_count = n())

pred_data <-
  st_join(m_bound, preds) %>% 
  group_by(PolyId) %>% 
  summarise(n_preds = n())

# Compare  

n_by_subcol <-
  count_data %>% 
  st_join(pred_data)

total_count <- 
  sum(n_by_subcol$n_count)
total_preds <-
  sum(n_by_subcol$n_preds)
total_preds/total_count

CF <-
  1.09

ggplot()+
  geom_point(data = n_by_subcol, aes(n_count, n_preds*CF),size = 3, col = "purple") +
  # geom_smooth(data = n_by_subcol, aes(n_count, n_preds*CF), method = "lm", col = "purple") +
  geom_line(aes(x = seq(0,2000, by = 50), y = seq(0,2000, by = 50)), lty = 2)+
  ylab("Predicted Occupied") +
  xlab("Manual Ortho M Count") +
  ggtitle("Crozier 2019") +
  theme_classic()
  
m <-
  lm(n_count ~ I(n_preds*1.09), data = n_by_subcol)
summary(m)

# Total Crozier count 
# use aggregated prediction points layer as a mask
col_mask <-
  st_read("predict/2019/croz_20191202/adult_s2_best/croz_20191202_predict_aggregate.shp") %>% 
  mutate(PolyId = row_number())

# check projection
st_crs(preds) == st_crs(col_mask)

count_total <- 
  st_join(col_mask, preds) %>%
  group_by(PolyId) %>%
  summarise(n_count = n())

total_croz_occ <-
  sum(count_total$n_count)*CF
total_croz_active <-
  sum(count_total$n_count)*1.02
total_croz_sit <-
  sum(count_total$n_count)
