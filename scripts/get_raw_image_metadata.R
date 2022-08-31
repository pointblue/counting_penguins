#To get image metadata from raw UAV images
#May 2022
#Grant
#NOTE: in progress - starting from out-in-out summary code - beware!

library(dplyr)
library(exifr) #For pulling out exif metadata
library(reticulate)

the_path <- "Z:/Informatics/S031/S0311920/croz1920/UAV/photos/12-17-2019/all_photos/test"
#will re-direct to S3 or wherever we are storing

files <- list.files(the_path, recursive=TRUE, pattern="*.JPG",full.names=TRUE)
#Note we also have a challenge around routes that were flown twice, possibly - 
#maybe it is safe to use the metadata from the more recent photo for a given coordinate?

exifinfo <- read_exif(files, tags = c("DateTimeOriginal",
                "GPSLatitude","GPSLongitude",
                "AbsoluteAltitude","RelativeAltitude",
                "FlightXSpeed","FlightYSpeed","FlightZSpeed",
                "Make",
                "FNumber","FocalLength","ApertureValue","MaxApertureValue",
                "ExposureTime",
                "ISO",
                "MeteringMode","ExposureMode","ExposureCompensation",
                "ColorSpace",
                "XResolution","YResolution","ImageWidth","ImageHeight"
                ))

unique(exifinfo$SubjectDistanceRange)

#Load Image
img1 = cv2.imread('testing_1.png',3) #READ BGR

width, height, depth = img1.shape
maxValue = width * height * depth * 255
imageValue = np.sum(img1)

#Map Value between 0 and 1
m = interp1d([0,maxValue],[0,1])
print m(imageValue)


for (season in season.list) {
  the_path <- paste0("z:/informatics/S031/s031",season,"/")
  msy<-seas_fy(season)
  results<-get_wb_stats(season,343,350)
  mtd1<-results[1]
  mtdse1<-results[2]
  mn1<-results[3]
  mni1<-results[4]
  results<-get_wb_stats(season,351,358)
  mtd2<-results[1]
  mtdse2<-results[2]
  mn2<-results[3]
  mni2<-results[4]
  results<-get_wb_stats(season,359,366)
  mtd3<-results[1]
  mtdse3<-results[2]
  mn3<-results[3]
  mni3<-results[4]
  results<-get_wb_stats(season,1,7)
  mtd4<-results[1]
  mtdse4<-results[2]
  mn4<-results[3]
  mni4<-results[4]
  results<-get_wb_stats(season,8,14)
  mtd5<-results[1]
  mtdse5<-results[2]
  mn5<-results[3]
  mni5<-results[4]
  results<-get_wb_stats(season,1,366) #full season
  mtdfs<-results[1]
  mtdfsse<-results[2]
  mnfs<-results[3]
  mnifs<-results[4]
  
  results_df[nrow(results_df)+1,] <- c(msy,season,mtd1,mtdse1,mn1,mni1,
                                       mtd2,mtdse2,mn2,mni2,
                                       mtd3,mtdse3,mn3,mni3,
                                       mtd4,mtdse4,mn4,mni4,
                                       mtd5,mtdse5,mn5,mni5,
                                       mtdfs,mtdfsse,mnfs,mnifs)
}



#Function for getting the data we want:
get_wb_stats<-function(season,d1,d2) {
  fn<-paste0("ono_",season,".csv")
  df <- read.csv(fn)%>%
    dplyr::mutate(date1i=as.POSIXct(date1),
                  jd1 = as.numeric(format(date1i,"%j")))
  df1<-filter(df,jd1>=d1 & jd1<=d2 &
                (jd1>=343 | jd1<=14)) #to accomodate the case of the full seasondurout1i>=6 & durout1i<=24*6 & br==1)
  mtd<-round(mean(df1$durout1i, na.rm = TRUE),2)
  se_td<-round(sd(df1$durout1i, na.rm = TRUE)/sqrt(length(!is.na(df1$durout1i))),2)
  n<-nrow(df1) #this is number of trips
  ni<-nrow(distinct(df1,avid))
  return(c(mtd,se_td,n,ni))  
}

#function for getting season_yr out of the season data
seas_fy <- function(s) {
  #  s here is like "1920" for 2019 - 2020; returns 4 digit year
  y1 <- substring(s, 1, 2)
  if (as.numeric(y1) > 90) {
    sfy <- paste0("19", y1)
  }
  else {
    sfy <- paste0("20", y1)
  }
  #RETURN season_fullyr
  return(as.numeric(sfy))
}



write.csv(results_df,"td_summary.csv",row.names=F)

#((((((((((((((((((((((((((
#Food load summary now:####
#((((((((((((((((((((((((((

#Function for getting the data we want:
get_wb_fl<-function(season,d1,d2) {
  fn<-paste0("ono_",season,".csv")
  df <- read.csv(fn)%>%
    dplyr::mutate(date1i=as.POSIXct(date1),
                  jd1 = as.numeric(format(date1i,"%j")))
  #df1<-filter(df,foodload>0 & foodload<1.3 & jd1>=d1 & jd1<=d2 &
  df1<-filter(df, foodload<1.3 & jd1>=d1 & jd1<=d2 & #this version allows negative food loads 
                (jd1>=343 | jd1<=14) & #to accomodate the case of the full season
                durout1i>=6 & durout1i<=24*6 & br==1)
  #filter on foodload follows Lescroel et al. 2021 and Ballard et al 2010
  #upper filter on trip duration is not clear - Lescroel et al used 60 hours
  #Ballard et al. did not mention an upper limit; lower filter was 6 in both cases
  
  mfl<-round(mean(df1$foodload, na.rm = TRUE),3)
  se_fl<-round(sd(df1$foodload, na.rm = TRUE)/sqrt(length(!is.na(df1$foodload))),3)
  n<-nrow(df1) #this is number of trips
  ni<-nrow(distinct(df1,avid))
  return(c(mfl,se_fl,n,ni))  
}

fl_df<-data.frame(season_yr=double(),season=character(),
          fl1=double(), fl1se=double(), n1=double(),ni1=double(),
          fl2=double(), fl2se=double(), n2=double(),ni2=double(),
          fl3=double(), fl3se=double(), n3=double(),ni3=double(),
          fl4=double(), fl4se=double(), n4=double(),ni4=double(),
          fl5=double(), fl5se=double(), n5=double(),ni5=double(),
          flfs=double(), flfsse=double(), nfs=double(),nifs=double(),
          stringsAsFactors=F)


for (season in season.list) {
  
  #filter by 7 day period, starting with jd 343 (12/8 or 12/9 on leap years)
  #tripduration>=6 hours and <=6 days
  #and bird is a breeder
  msy<-seas_fy(season)
  results<-get_wb_fl(season,343,350)
  mfl1<-results[1]
  mfl1se<-results[2]
  mn1<-results[3]
  mni1<-results[4]
  results<-get_wb_fl(season,351,358)
  mfl2<-results[1]
  mfl2se<-results[2]
  mn2<-results[3]
  mni2<-results[4]
  results<-get_wb_fl(season,359,366)
  mfl3<-results[1]
  mfl3se<-results[2]
  mn3<-results[3]
  mni3<-results[4]
  results<-get_wb_fl(season,1,7)
  mfl4<-results[1]
  mfl4se<-results[2]
  mn4<-results[3]
  mni4<-results[4]
  results<-get_wb_fl(season,8,14)
  mfl5<-results[1]
  mfl5se<-results[2]
  mn5<-results[3]
  mni5<-results[4]
  results<-get_wb_fl(season,1,366) #full season
  mflfs<-results[1]
  mflfsse<-results[2]
  mnfs<-results[3]
  mnifs<-results[4]
  
  fl_df[nrow(fl_df)+1,] <- c(msy,season,mfl1,mfl1se,mn1,mni1,
                                       mfl2,mfl2se,mn2,mni2,
                                       mfl3,mfl3se,mn3,mni3,
                                       mfl4,mfl4se,mn4,mni4,
                                       mfl5,mfl5se,mn5,mni5,
                                       mflfs,mflfsse,mnfs,mnifs)
}

write.csv(fl_df,"fl_summary.csv",row.names=F)

#((((((((((((((((((((((((((((((((((((((((((()))))))))))))))))))))))))))))))))))))))))))
#Verify how many individuals there should be in each season####
#include if: has pit tag that is read by wb, has nest_id, has nest with at least 1 egg
#((((((((((((((((((((((((((((((((((((((((((()))))))))))))))))))))))))))))))))))))))))))

nai_df<-data.frame(season_yr=double(),season=character(), n_individuals=double(), ni_tr=double(), ni_ono=double(),
                       stringsAsFactors=F)

for (season in season.list) {
  msy<-seas_fy(season)
  wb_path<-paste0("Z:/informatics/s031/s031",season,"/croz",season,"/wb/")
  nest_file<-paste0(wb_path,"wb_nests_",season,".csv")
  ono_file<-paste0("ono_",season,".csv")
    
  if (msy<2016) {
    wb_wts_path<-paste0("Z:/Informatics/S031/analyses/wb/weight algorithms/wb1/")
    wb_wts_file<-paste0(wb_wts_path,"crozwts",season,".csv")
  } else {
    wb_wts_path<-paste0("Z:/Informatics/S031/analyses/wb/weight algorithms/wb2_and_3/")  
    wb_wts_file<-paste0(wb_wts_path,"wbdata_",season,"_pred_wts.csv")
}
  nf<-read.csv(nest_file)
  wbf<-read.csv(wb_wts_file)
  onof<-read.csv(ono_file)
  sql<-"select * from nf where (nuegg>0 and nuegg<9) or (nuch>0 and nuch<9) or (outcome>0 and outcome<9) group by avid"
  sql2<-"select * from nf where ((nuegg>0 and nuegg<9) or (nuch>0 and nuch<9) or (outcome>0 and outcome<9)) and avid in 
      (select distinct avid from wbf) group by avid"
  sql3<-"select distinct avid from onof where br=1 group by avid"
  active_nests<-sqldf(sql) #number nests that were monitored that were active at one point
  active_nests_with_tr<-sqldf(sql2) #number of those nests where the tag was read at least once
  ono_tags<-sqldf(sql3) #number of individuals that are in the ONO file with br=1 (breeding status is yes)
  nai<-nrow(active_nests)
  naitr<-nrow(active_nests_with_tr)
  nono<-nrow(ono_tags)
  nai_df[nrow(nai_df)+1,] <- c(msy,season,nai,naitr,nono)
}

write.csv(nai_df,"sample_size_summary.csv",row.names=F)

