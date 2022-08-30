import cv2
import tifffile as tiff
import math
from pathlib import Path
import numpy as np
import itertools as it
import os
import sys
import glob
import rasterio
import csv

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

            # get geodata
            rast = rasterio.open(file)

            # loop over square index. get top left of pt w/ cropped image
            print(f"tileing file {name}")

            # open a file to append data
            header = ["tileName", "pixelX", "pixelY", "easting", "northng"]
            outcsv = str(Path(os.path.join(str(self.outDir),name)+"_tilesGeorefTable.csv"))
            fcsv = open(outcsv, 'w', newline='')
            writer = csv.writer(fcsv)
            writer.writerow(header)

            for (i, j) in it.product(range(nX), range(nY)):
                xx = i*(self.xSize-self.buffer)
                yy = j*(self.ySize-self.buffer)

                cropped_img = img[yy:min(yy+self.ySize, height), xx:min(xx+self.xSize, width)]
                cropped_img =cv2.cvtColor(cropped_img, cv2.COLOR_RGB2BGR)

                # filter only for tiles with something in them (i.e., not single-color tiles)
                # could be as simple as...
                if np.max(cropped_img) != np.min(cropped_img):

                    # Save in table img name, xx, yy, easting, northing
                    # xx and yy are the absolute references.
                    # the georeferences are easy to get
                    eastV = rast.xy(xx,yy)[0]
                    northV = rast.xy(xx,yy)[1]
                    tilename = str(name+f'_{i}_{j}.{self.outFileExt}')
                    data = [tilename, xx, yy, eastV, northV]
                    writer.writerow(data)

                    outfile = str(Path(os.path.join(str(self.outDir),name)+f'_{i}_{j}.{self.outFileExt}'))

                    cv2.imwrite(outfile , cropped_img, [cv2.IMWRITE_JPEG_QUALITY, 100])

            fcsv.close()

            print("\tdone")

        except OSError:
            print("cannot open", file)


