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

path_to_objTiler='/home/ubuntu/Workspace/counting_penguins/tiler/'

import sys
sys.path.insert(0, path_to_objTiler)

from Tiler_tiff import Tiler

tiler = Tiler(xSize=512, ySize=256, buffer=20, outDir="/home/ubuntu/Workspace/tiles/", outFileExt="jpg")
for file in glob.glob("/home/ubuntu/Workspace/orthos/*.*"):
    if "croz" in file:
        tiler.tile(file)
