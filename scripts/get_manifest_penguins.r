#Download a manifest file to track progress on a GroundTruth labeling job
#note: does not (yet) track numbers of each label etc. - see python code for that (parse_json_labels_make_yolo.py).
#Grant - 11/8/2022
#last update: 12/04/2022

library(tidyverse)
library(aws.s3)
library(data.table)
library(stringr)
library(rjson)

#for aws s3 access
# set region for s3 bucket access
#Sys.setenv("AWS_DEFAULT_REGION" = "us-east-2")
Sys.setenv("AWS_DEFAULT_REGION" = "us-east-2")

wd <-
  "C:/gballard/s031/analyses/counting_penguins/scripts/"

setwd(wd)

bucket <-
  "s3://deju-penguinscience/"

#for labeling projects underway, use this:
object <-
  #"PenguinCounting/croz_20211127/label_sample_2/croz-20211127-2/manifests/intermediate/1/output.manifest"
  "PenguinCounting/croz_20211127/label_sample_2/croz-20211127-2/manifests/output/output.manifest"
#object <-
#  "PenguinCounting/croz_20211127/label_sample/adpe-label-test3/manifests/output/output.manifest"

#for completed labeling projects the general pattern is:
#mani_path = f"s3://{s3_bucket}/{job_id}/ground_truth_annots/{gt_job_name}/manifests/output/output.manifest"
#so for mono lake gulls would be:
#object <-
#  "orthomosaics/mono_20220601/label_sample/mono-20220601/manifests/output/output.manifest"

obj<-paste0(bucket,object)

mfn="../data/labels/croz_20211127/output.manifest"
save_object(
  obj,
  file=mfn,
  overwrite = TRUE)

df<-read.table(mfn, fill = TRUE, header = FALSE, sep="") 
df<-data.frame(V1 = df$V1)#only need first column

df_labeled<-filter(df, str_detect(df$V1, "image_size") == TRUE) #any tile that was labeled will have this text
df_not_labeled<-filter(df, str_detect(df$V1, "image_size") == FALSE) #any tile not labeled will not have this text

##########################################################################################
#get the tile list that is not already labeled in case you need to make a new job from it:
##########################################################################################

for(i in 1:nrow(df_not_labeled)) {
  df_not_labeled$tile[i] = str_sub(str_split(df_not_labeled$V1,"/")[[i]][[7]],1,-3)
}


prefix <-
  "PenguinCounting/croz_20211127/tiles/"

prefix2 <- "PenguinCounting/croz_20211127/label_sample_2/"

set <- df_not_labeled
  
for (i in 1:nrow(set)) {
  tile_name <-
    set$tile[i]
  
  fr_object <-
    paste0(prefix, tile_name)
  to_object <-
    paste0(prefix2, tile_name)
  
  # copy the tile to another S3 bucket
  copy_object(
    fr_object,
    to_object = to_object,
    from_bucket = bucket,
    to_bucket = bucket
    
  )
}

####################################################################################
####Get the info from manifest 
#this is much faster than reading from .json files, but doesn't contain worker info
#also - the manifest file is updated only about once per hour
#don't forget to download it again from above!
#####################################################################################

#00000000000000000000000000000000000000000000000000000
#Make data frame for holding results####
yolo_output_df<-data.frame(img_file=character(0),category=character(0),box_left=integer(),box_top=integer(),box_height=integer(),
                          box_width=integer(),img_width=integer(),img_height=integer(), int_category=integer(),
                          box_center_w=integer(), box_center_h=integer(), box_area=integer(), stringsAsFactors=F)
#00000000000000000000000000000000000000000000000000000

get_tile_info <- function(ff) {
  
  n_tiles <- length(ff$V1)
  l1 = 0
  l2 = 0 
  l3 = 0
  
  for(tile in 1:n_tiles) {
    #json_s_file <- save_object(
    #  file_filter$Key[tile],
    #  bucket,
    # file = "json_test.json",
    #  overwrite = TRUE)
    
    jstr1 <- fromJSON(as.character(ff[tile,1])) 
    
    n_labels<-length(jstr1[[2]][[2]]) #can't use label names with hyphens here? refer by index position
    
    for (i in 1:n_labels) {
      label<-jstr1[[2]][[2]][[i]]$class_id
      #jstr1[[2]][[2]][[11]]$class_id
      #print(label)
      
      if (label == 0) {l1=l1+1
      } else if (label == 1) {
        l2=l2+1
      } else if (label == 2) {
        l3=l3+1
      }
    
      
      jpeg<-str_split(jstr1[[1]][[1]],"/")[[1]][[7]]
      print(paste("Tile #: ",tile, "Tile Name:",jpeg))
      
      label_name<-"" ##assigned after the loop
      
      bl<-jstr1[[2]][[2]][[i]]$left   #label left
      bt<-jstr1[[2]][[2]][[i]]$top    #label top 
      bh<-jstr1[[2]][[2]][[i]]$height #label height
      bw<-jstr1[[2]][[2]][[i]]$width  #label width
      iw<-jstr1[[2]][[1]][[1]]$width  #image width
      ih<-jstr1[[2]][[1]][[1]]$height #image height
      bcw<-(bl+bw/2) ##box center width
      bch<-(bt+bh/2) ##box center height
      ba <- bw*bh ##box area
      #yolo dimensions for labels are expressed as percentages of the image (tile) dimensions
      
      bh <- bh / ih
      bw <- bw / iw
      bcw <- bcw / iw
      bch <- bch / ih

      yolo_output_df[nrow(yolo_output_df)+1,] <- 
        c(jpeg,label_name,bl, bt, bh, bw, iw, ih, label, bcw, bch, ba)  
    }
    
     
  }
  
  #return(c(n_tiles, l1, l2, l3))
  return(yolo_output_df)
}


#run the function above:
tile_info<-get_tile_info(ff = df_labeled)

#update the labels ("category" in the df)
tile_info$category = ifelse (tile_info$int_category == 0, 'ADPE_a', tile_info$category)
tile_info$category = ifelse (tile_info$int_category == 1, 'ADPE_a_stand', tile_info$category)
tile_info$category = ifelse (tile_info$int_category == 2, 'no_ADPE', tile_info$category)

print(paste0("Total tiles: ",length(unique(tile_info$img_file))))
tile_info %>% count(category)

#write a csv with one row per label in yolo format
write.csv(tile_info, file = "yolo_labels_output_r.csv", row.names = FALSE)

#summarize by tile by category
yolo_tiles<-tile_info %>% 
  group_by(img_file, category) %>%
  summarize(count_by_category = n())
write.csv(yolo_tiles, file = "yolo_tiles_output_r.csv", row.names = FALSE)

#or make a summary table with one row per tile and column for each label category
df <- data.frame(img_file = unique(tile_info$img_file))


df1 <- filter(tile_info,category=="ADPE_a") %>%
  group_by(img_file) %>%
  summarize(ADPE_a = n()) 
df2 <- filter(tile_info,category=="ADPE_a_stand") %>%
  group_by(img_file) %>%
  summarize(ADPE_a_stand = n()) 
df3 <- filter(tile_info,category=="no_ADPE") %>%
  group_by(img_file) %>%
  summarize(no_ADPE = n()) 
yolo_tiles_summary<- df %>%
  left_join(df1, by='img_file') %>%
  left_join(df2, by='img_file') %>%
  left_join(df3, by='img_file')

write.csv(yolo_tiles_summary, file = "yolo_tiles_summary_r.csv", row.names = FALSE)

#Now for the fun part?
#first - simple estimate of how many breeding pairs based on a heuristic approach
#assumptions:
#89% of sitting penguins tagged should be counted
#60% of standing penguins count
#(this is on the basis of 57 tiles with penguins in them assessed by GB for croz_20211127)
#(should check for other years how much it varies, and also whether 57 tiles is enough!)
#at 75 tiles checked the numbers were 88.8% and 60.8% - not changing much
#take total tile count
#calculate number of ADPE_a total on those tiles
#calculate number of ADPE_a_stand total on those tiles
#discount by above 
#multiply times total number of tiles >60kb (smaller than that are not included in the tagging because they are edge tiles or all white or all black)
#e.g., for croz_20211127 the total is 39921
#can change the file you want to read from using the consolidated output; for example:
#yolo_tiles_summary<- read.csv("../data/labels/croz_20211127/croz_20211127_validation_tile_summary.csv")
n_tiles<-nrow(yolo_tiles_summary)
n_ADPE_a<-sum(yolo_tiles_summary$ADPE_a, na.rm = TRUE)
n_ADPE_stand<-sum(yolo_tiles_summary$ADPE_a_stand, na.rm = TRUE)
n_OT_per_tile<-((n_ADPE_a*.888235)+(n_ADPE_stand*0.60815))/n_tiles
#note that total_tiles is different for each orthomosaic:
total_tiles <- 39921 ##croz_20211127
#total_tiles <- 28484 ##croz_20191202
#total_tiles <- 56919 ##croz_202011129
OT_est <- total_tiles*n_OT_per_tile
print(OT_est)


#check for problems in the label data:
#tiles with more than 1 "no_adpe":
prob_tiles<-filter(yolo_tiles_summary, no_ADPE>0 & (ADPE_a>0 | ADPE_a_stand>0))

#duplicate labels?
tile_info<-read.csv("../data/labels/croz_20211127/croz_20211127_validation_labels.csv")
dis_tile_info<-distinct(tile_info)

######Below is in progress######################################################################
#Another strategy would be to remove duplicates and whoever remains "counts"? 
print (mean(as.numeric(tile_info$box_area[tile_info$category=="ADPE_a"]), na.rm = TRUE))
#hist(as.numeric(tile_info$box_area[tile_info$category=="ADPE_a"]), na.rm = TRUE)
fivenum(as.numeric(tile_info$box_area[tile_info$category=="ADPE_a"]), na.rm = TRUE)
#returns Tukey min, lower-hinge, median, upper-hinge, max

require(psych)
describeBy(as.numeric(filt_df$box_area), filt_df$category, na.rm=TRUE)

