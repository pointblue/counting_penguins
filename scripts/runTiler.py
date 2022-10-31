# This script implements Step 3 in Leo's setup instructions here:
# https://docs.google.com/document/d/1B-DXIHf2EQWcJSGhCHTx0Xsfz6YjB3TIQo1z2pK9bRk

import cv2
import tifffile as tiff
import math
from pathlib import Path
import numpy as np
import itertools as it
import os
import sys
import glob
import imagecodecs
import csv

# Full path to workspace directory contining counting_penguins repo,
# and orthos and tiles subdirectories. Must end with a slash!

workspace = '/Users/timmyd/projects/Point Blue/'
#workspace = '/home/ubuntu/Workspace/'

path_to_objTiler = workspace + '/counting_penguins/tiler/'

import sys
sys.path.insert(0, path_to_objTiler)

from Tiler_tiff_tim import Tiler

tiler = Tiler(xSize=512, ySize=256, buffer=20, outDir=workspace + 'tiles/', outFileExt='jpg')
for file in glob.glob(workspace + "orthos/*.*"):
    if "croz" in file:
        tiler.tile(file)
