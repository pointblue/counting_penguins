# User inputs ---------------------------------------------------------------

# model paths relitive to the YOLOv5 Directory
models=['../models/adult_s2_best.pt',
        '../models/adult_stand_s5_best.pt',
        '../models/chick_s_best.pt']

# tile folder relitive to the YOLOv5 directory
tile_dir= "../test_images_tiled/*"

# confidence threshold
conf_thres=0.01

# largest image dimention
image_size=512

# name for output directory (will be created in the yolov5 directory, e.g. ./yolov5/penguin_2021)
output_dir="penguin_2021"

# load librarys
from pathlib import Path
from argparse import Namespace
import os
# change to the yolov5 directory to inport the detect function
os.chdir("./yolov5")
os.getcwd()
from detect import detect

# loop to run each model
for mod in models:
    print(mod)
    
    # run_name is the name of the subfodler to create within the project folder.
    # In this case we name it after the model.  The detect function is set up to
    # NOT overwrite a run_name if it already exists and will chreate a new name
    # by adding a number after the runname and incrementing, so if you have many
    # runs they will not over write eachouther for better or worse!
    run_name=Path(mod).name.split(sep=".")[0]
    
    # load all the parameters See the detect.py for more info on these
    opt=Namespace(agnostic_nms=False,
        augment=False,
        classes=None,
        conf_thres=conf_thres,
        device="cpu",
        exist_ok=False,
        img_size=image_size,
        iou_thres=0.3,
        name=run_name,
        project=output_dir,
        save_conf=True,
        save_txt=True,
        source=tile_dir,
        update=False,
        view_img=False,
        weights=mod,
        save_xxyy=False)
    
    detect(opt)  

# change back to the main repo directory
os.chdir("..")

