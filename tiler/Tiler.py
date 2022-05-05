from PIL import Image
import math
from pathlib import Path
import numpy as np
import itertools as it
import os
import sys

Image.MAX_IMAGE_PIXELS = None


class Tiler(object):
    """docstring for Tiler"""

    def __init__(self, size=(1280, 1280), buffer=20,
                 outDir="out", outFileExt="png"):
        super(Tiler, self).__init__()
        self.xSize, self.ySize = size
        self.buffer = 20
        self.outDir = outDir
        self.outFileExt = outFileExt

        self.outDir = Path(outDir)
        self.outDir.mkdir(parents=True, exist_ok=True)

    def tile(self, file):
        try:
            with Image.open(file) as image:
                name = Path(file).stem
                # get number of tiles
                nX = np.ceil((image.size[0]-self.buffer) /
                             (self.xSize-self.buffer)).astype(int)
                nY = np.ceil((image.size[1]-self.buffer) /
                             (self.ySize-self.buffer)).astype(int)
                # pad the image
                pad = (nX*(self.xSize-self.buffer)+self.buffer-image.size[0],
                       nY*(self.ySize-self.buffer)+self.buffer-image.size[1])
                image = self.addMargin(image, pad)
                # loop over square index. get top left of pt w/ cropped image
                print(f"tileing file {name}")
                for (i, j) in it.product(range(nX), range(nY)):
                    xx = i*(self.xSize-self.buffer)
                    yy = j*(self.xSize-self.buffer)
                    crop = image.crop(
                        (xx, yy, xx + self.xSize, yy + self.ySize))
                    outfile = Path(name+f'_{i}_{j}.{self.outFileExt}')
                    crop.save(self.outDir/outfile)
                print("\tdone")
        except OSError:
            print("cannot open", file)

    def addMargin(self, image, pad, color=(255, 255, 255)):
        width, height = image.size
        result = Image.new(image.mode, (width+pad[0], height+pad[1]), color)
        result.paste(image, (0, 0))
        return result
