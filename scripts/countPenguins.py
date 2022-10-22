# This script implements Step 4 in Leo's instructions here:
# https://docs.google.com/document/d/1B-DXIHf2EQWcJSGhCHTx0Xsfz6YjB3TIQo1z2pK9bRk

from pathlib import Path
import os
from argparse import Namespace
import sys
import glob

path_to_objCounter='/home/ubuntu/Workspace/counting_penguins/counter/'
path_to_yolo='/home/ubuntu/Workspace/yolov5'

import sys
sys.path.insert(0, path_to_objCounter)
sys.path.insert(0, path_to_yolo)

from counter import Counter
import detect

tileDir="/home/ubuntu/Workspace/tiles/"

counter = Counter(output_dir="/home/ubuntu/Workspace/counts/",  
					models=['/home/ubuntu/Workspace/counting_penguins/models/adult_s2_best.pt',
        					'/home/ubuntu/Workspace/counting_penguins/models/adult_stand_s5_best.pt',
        					'/home/ubuntu/Workspace/counting_penguins/models/chick_s_best.pt'])
if os.path.exists(tileDir):
    counter.count(tileDir="/home/ubuntu/Workspace/tiles/")
