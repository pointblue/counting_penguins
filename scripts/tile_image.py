import cv2
import math
import os
import numpy as np
import time
import argparse
from joblib import Parallel, delayed
import multiprocessing
from pathlib import Path
import logging
import pandas as pd
import tifffile as tiff

'''
This script creates jpg tiles from a tiff.  Tiles can overlap in the x and/or y direction.
'''
       
def tile_image(file,out_folder,jpg_quality, tile_x=1024,tile_y= 600,object_size_px=20,out_file_ext="JPG"):
    '''
    Tile images in a directory.  This function takes width and hight arguments
    and finds the minimum number of tiles in the x and y directions that have at
    least `object_size_px/2` pixels of overlap.  It is set up to always output
    tiles with the exact `width` and `height` of the input arguments and the
    number of tiles will vary based on the image dimentions, and so will the
    % overlap between images.
    
    # Example
    python D:/CM,Inc/git_repos/cmiimagetools/python/tile_image.py  --in_folder "\\\\NAS1\\NAS1_2Jun14\\Images\\USGS_AerialImages_2019_R1_sum19"   --out_folder "\\\\NAS1\\NAS1_2Jun14\\Images\\USGS_AerialImages_2019_R1_sum19_tiles"  --quality 75  --tile_x 1024 --tile_y 600 --file_ext "JPG"
    
    # Input args for testing
    in_folder="\\\\NAS1\\NAS2_9Oct14\\Images\\PointBlue_Penguins_2019_R3\\croz_v3"
    out_folder = "\\\\NAS1\\NAS2_9Oct14\\Images\\PointBlue_Penguins_2019_R3\\croz_v3_tiles_2"
    quality =100
    tile_x =500
    tile_y =250
    object_size_px=30
    out_file_ext="JPG"
    file_ext="tif"
    '''
    logging.basicConfig(filename=os.path.join(out_folder,str(os.path.basename(out_folder))+'.log'),
                        level=logging.DEBUG,format='%(asctime)s %(levelname)s %(message)s',
                        datefmt='%m/%d/%Y %I:%M:%S %p')

    # get base file name (index 0) and the extention index 1)
    filename = os.path.splitext(os.path.basename(file))
    # make out folder
    out_folder2 = os.path.join(out_folder,os.path.basename(os.path.dirname(file)))
    for delay in range(10):
        try:
            if not Path.is_dir(Path(out_folder2)):
                try:
                    os.makedirs(out_folder2,exist_ok=False)
                except FileExistsError as e:
                    logging.warning(e)
                finally:
                    logging.info("Folder exists, continuing")

   
            # read image
            logging.info("Tiling: "+file)
            img = tiff.imread(file)

            # get dims
            img_shape = img.shape
            height=img_shape[0]
            width=img_shape[1]
            
            # devide in to chunks
            n_x = math.ceil(width/tile_x)
            n_y = math.ceil(height/tile_y)
            height1=height/n_y
            width1=width/n_x
                
            while ((height-height1)<object_size_px/2):
                  n_y=n_y+1
                  height1=height/n_y
            
            while ((width-width1)<object_size_px/2):
                  n_x=n_x+1
                  width1=width/n_x
                  
            offset_x=math.floor(width/n_x)
            offset_y=math.floor(height/n_y)
            
            # loop to subset into each crop
            for i in range(n_y): 
                for j in range(n_x):
                  #logic to make overlapping tiles after the first iteration
                    if i==0:
                        offset_y_new=offset_y*i
                    else:
                        offset_y_new=(offset_y*i)-(tile_y-offset_y)
                    
                    if j==0:
                        offset_x_new=offset_x*j
                    else:
                        offset_x_new=(offset_x*j)-(tile_x-offset_x)
                        
                    out_path_temp=os.path.join(out_folder2,filename[0]+ "_" + str(offset_x_new) + "_" + str(offset_y_new) + '.' +  out_file_ext)
                    
                    try:
                        if not Path.is_file(Path(out_path_temp)):
                        # make crop
                            cropped_img = img[offset_y_new:min(offset_y_new+tile_y, height), offset_x_new:min(offset_x_new+tile_x, width)]
                            cropped_img =cv2.cvtColor(cropped_img, cv2.COLOR_RGB2BGR)

                            logging.info("creating tile: "+out_path_temp)
    
                            # save crop
                            cv2.imwrite(out_path_temp , cropped_img, [cv2.IMWRITE_JPEG_QUALITY, jpg_quality])
                    except:
                        logging.info("tile exists, skipping: "+out_path_temp)

        except Exception as e:
            logging.debug(e)
            logging.debug("Retry (%delay) sleeping for 5 seconds")
            time.sleep(5)


def tile_image_dir_par(in_folder,out_folder,jpg_quality, tile_x=1024,tile_y= 600,object_size_px=20,file_ext="JPG",out_file_ext="JPG",par=True):

    '''
    Function to go through a folder and find the image files and then for each 
    file tile it.  The can happen in parrelel and the default is to run 
    3 x cpu_count jobs at once
    '''
    if not Path.is_dir(Path(out_folder)):
        try:
            os.makedirs(out_folder,exist_ok=False)
        except FileExistsError as e:
            logging.warning(e)
        finally:
            logging.info("Folder exists, continuing")
    # set up logging
    logging.basicConfig(filename=os.path.join(out_folder,str(os.path.basename(in_folder))+'.log'),level=logging.DEBUG,format='%(asctime)s %(levelname)s %(message)s',datefmt='%m/%d/%Y %I:%M:%S %p')
    
    # lists better
    logging.info("searching for file of type: "+file_ext)
    if Path.is_file(Path(in_folder)):
        files_table = pd.read_csv(in_folder)
        files = files_table.SourceFile
    else:
        files = list(Path(in_folder).rglob("**/*."+file_ext))
    
    logging.info("Tiling "+str(len(files))+" "+file_ext+" in "+in_folder)
    # get number of cores
    if par=="True":
        num_cores = multiprocessing.cpu_count()*3
    else:
         num_cores = 1
    # parallel function that runs tile_image from above on the list of files
   
    Parallel(n_jobs=num_cores )(delayed(tile_image)(str(file), out_folder, jpg_quality, tile_x, tile_y, object_size_px, out_file_ext) for file in files)
    logging.info("Finished Tiling")


#import pandas as pd
#files_table = pd.read_csv(r"D:\CM,Inc\Dropbox (CMI)\CMI_Team\Analysis\2019\USGS_AerialImage_2019\failed_tiles.csv")
#files_table.SourceFile
#
#for file in files:
#    i=file
#    tile_image(str(file), out_folder, jpg_quality, tile_x, tile_y, object_size_px, out_file_ext)

if __name__ == "__main__":
    # construct the argument parse and parse the arguments
    ap = argparse.ArgumentParser()
    ap.add_argument("-i", "--in_folder", required=True,
    	help="path to input folder path")
    ap.add_argument("-o", "--out_folder", required=True,
    	help="path to the output folder path")
    ap.add_argument("-q", "--quality", type=int, default=75,
    	help="jpeg quality for files out.  Machine learning papers have found that quality (range 0-100) of >10 leads to little change in performance of modern CNNs. but for humans we can perceve a reduction of quality with <75 or so.  For our putposes in the 50-75 range is probabily good.")
    ap.add_argument("-x", "--tile_x", type=int, default=1024,
    	help="tile sizes (x)")
    ap.add_argument("-y", "--tile_y", type=int, default=600,
    	help="tile sizes (y)")
    ap.add_argument("-os", "--object_size_px",type=int,  default=20,
    	help="target-object size in pixels (currently only accepts a square with equal sides). This should be ~ the max dimentions of an object of interest in pixels in the x or y direction.")
    ap.add_argument("-e", "--file_ext", type=str, default="JPG",
    	help="the extention on files (currently only can handle a single file type")
    ap.add_argument("-oe", "--out_file_ext", type=str, default="JPG",
    	help="the extention on files writen (currently only can handle a single file type")
    ap.add_argument("-p", "--par", type=str, default="True",
    	help="the extention on files writen (currently only can handle a single file type")
    args = vars(ap.parse_args())
    
    # run the function
    tile_image_dir_par(args["in_folder"],args["out_folder"],args["quality"],args["tile_x"],args["tile_y"],args["object_size_px"],args["file_ext"],args["out_file_ext"],args["par"])
    #
    #
    
    #currentDT = datetime.datetime.now()
    #print("Finished " + str(args["in_folder"]) + " "+str(currentDT))
