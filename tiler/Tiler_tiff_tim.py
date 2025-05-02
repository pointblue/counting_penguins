# This is the original tiler_tiff script, modified by Tim DeBenedictis to run in low-memory environments
# like laptops, where the entire input ortho TIFF won't fit into RAM.
# -Tim DeBenedictis (timd@southernstars.com) - 27 Oct 2022

import cv2
import tifffile as tiff # need version 2022.3.25
import math
from pathlib import Path
import numpy as np
import itertools as it
import os
import sys
import glob
import rasterio
import csv
import zarr # need to use version 2.11.0 or later with tifffile version 2022.3.25 

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
            # get geodata
            rast = rasterio.open(file)
            print ( "Got geo data, reading " + file )

            # get overall dimensions of TIFF file
            tif = tiff.TiffFile ( file )
            page = tif.pages[0]
            height = page.shape[0]
            width = page.shape[1]
            print ( "TIFF width = %d, height = %d" % ( width, height ) )
            print ( "Tile width = %d, height = %d" % ( self.xSize, self.ySize ) )

            # get number of tiles
            nX = np.ceil((width-self.buffer) /
                         (self.xSize-self.buffer)).astype(int)
            nY = np.ceil((height-self.buffer) /
                         (self.ySize-self.buffer)).astype(int)
            print( "Number of tiles (width x height): %d x %d" % ( nX, nY ) )
            print( "Number of tiles (total): %d" % ( nX * nY ) )

            name = Path(file).stem

            store = tiff.imread(file, aszarr=True)
            z = zarr.open(store, mode='r')
            img = z[0]
            
            # get dims
            img_shape = img.shape
            print ( img_shape )
            
            height=img_shape[0]
            width=img_shape[1]
            # loop over square index. get top left of pt w/ cropped image
            print(f"tileing file {name}")

            # open a file to append data
            header = ["tileName", "pixelX", "pixelY", "easting", "northng"]
            outcsv = str(Path(os.path.join(str(self.outDir),name)+"_tilesGeorefTable.csv"))
            fcsv = open(outcsv, 'w', newline='')
            writer = csv.writer(fcsv)
            writer.writerow(header)

            for (j, i) in it.product(range(nY), range(nX)):
                xx = i*(self.xSize-self.buffer)
                yy = j*(self.ySize-self.buffer)

                print ( "extracting tile at xx=%d, yy=%d" % ( xx, yy ) )
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


