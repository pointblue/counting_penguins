# This script implements Step 4 in Leo's instructions here:
# https://docs.google.com/document/d/1B-DXIHf2EQWcJSGhCHTx0Xsfz6YjB3TIQo1z2pK9bRk

from pathlib import Path
import os
from argparse import Namespace
import sys
import glob

# path to Workspace directory. Must end with a slash!
# workspaceDir='/home/ubuntu/Workspace/'
workspaceDir='/Users/timmyd/Projects/PointBlue/'

path_to_objCounter = workspaceDir + 'counting_penguins/counter/'
path_to_yolo = workspaceDir + 'yolov5/'
path_to_tiles = workspaceDir + 'tiles/'

import sys
sys.path.insert(0, path_to_objCounter)
sys.path.insert(0, path_to_yolo)

# Note: the counter needs pytorch.  To install on MacOS:
# pip3 install torch torchvision torchaudio

from counter import Counter
import detect

counter = Counter(output_dir=workspaceDir+"counts/",  
                  models=[workspaceDir+'counting_penguins/models/adult_s2_best.pt',
                          workspaceDir+'counting_penguins/models/adult_stand_s5_best.pt',
                          workspaceDir+'counting_penguins/models/chick_s_best.pt'])

if os.path.exists(path_to_tiles):
    counter.count(tileDir=path_to_tiles)
