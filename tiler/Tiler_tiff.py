import cv2
import tifffile as tiff
import math
from pathlib import Path
import numpy as np
import itertools as it
import os
import sys
import glob

class Tiler(object):
    """docstring for Tiler"""

    def __init__(self, xSize=1280, ySize=1280, buffer=20,
                 outDir="out", outFileExt="png"):
        super(Tiler, self).__init__()
        self.xSize = xSize
        self.ySize = ySize
        self.buffer = buffer
        self.outDir = outDir
        self.outFileExt = outFileExt
        self.outDir = Path(outDir)
        self.outDir.mkdir(parents=True, exist_ok=True)

    def tile(self, file):
        try:
            img = tiff.imread(file)
            name = Path(file).stem
            # get dims
            img_shape = img.shape
            height=img_shape[0]
            width=img_shape[1]
            # get number of tiles
            nX = np.ceil((width-self.buffer) /
                         (self.xSize-self.buffer)).astype(int)
            nY = np.ceil((height-self.buffer) /
                         (self.ySize-self.buffer)).astype(int)
            # loop over square index. get top left of pt w/ cropped image
            print(f"tileing file {name}")
            for (i, j) in it.product(range(nX), range(nY)):
                xx = i*(self.xSize-self.buffer)
                yy = j*(self.xSize-self.buffer)

                cropped_img = img[yy:min(yy+self.ySize, height), xx:min(xx+self.xSize, width)]
                cropped_img =cv2.cvtColor(cropped_img, cv2.COLOR_RGB2BGR)

                                # Save in table img name, xx and yy

                outfile = str(Path(os.path.join(str(self.outDir),name)+f'_{i}_{j}.{self.outFileExt}'))

                cv2.imwrite(outfile , cropped_img, [cv2.IMWRITE_JPEG_QUALITY, 100])

            print("\tdone")

        except OSError:
            print("cannot open", file)


