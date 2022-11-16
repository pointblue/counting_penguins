### This file contains the functions and classes that inspect predictions by tile
### and assigns each penguin a unique ID, but only if not too close to a tile's edge

#### First activate the environment. Go to the environments folder and then:
source makeidenv/bin/activate


## The result is a table of detections with unique penguin IDs
import os
import sys
import glob
import rasterio
import pandas as pd
import uuid
from pathlib import Path
import numpy as np

## Function to calculate the length and width of a pixel
# ortho_path is the full path and name of the orthomosaic image
def getPixelLength(ortho_path):
    try:
        rast = rasterio.open(ortho_path)
        ncol = rast.width
        nrow = rast.height
        rextent = rast.bounds
        
        pixW = (rextent[2] - rextent[0])/ncol
        pixH = (rextent[3] - rextent[1])/ncol
        
        return [pixW, pixH]
        
    except OSError:
        print("cannot open", orthopath)
        

## Function that retrieves the absolute and geocoordinates of a table's lower left corner
# reftable_path is the full path and name of the tile reference table
# tilename is the name of the tile for which the coordinates are being sought
def getTileCornerCoords(reftable_path,tilename):
    try:
        reftable = pd.read_csv(reftable_path)
        tilemeta = reftable[reftable.tileName == tilename]
        tmd = tilemeta.to_numpy()
        #xmin, ymin, easting, northing
        return [tmd[0,1],tmd[0,2],tmd[0,3],tmd[0,4]]
    
    except OSError:
        print("cannot open", reftable_path)


## Function to position each detection in the ortho 
# reftable_path is the full path and name of the tile reference table
# pred_path is the full path and name of prediction table for a given tile
# pixelLength is the length of each pixel in width and height, based on the ortho projection, from function getPixelLength
# modelClass is the model class: "adult_s2_best", etc.
# tileSize is a two-element array with width, height of the tile in pixels
# excLim is a vector of the limits of relative positions in x and y so that a penguin is not too close to the edge of the tile and can be counted
def calcPenguinLocation(pred_path,reftable_path,pixelLength,modelClass,tileSize,excLim):
    try:
    
        # get tile name from pred_path
        tilename = Path(pred_path).stem + ".jpg"
        
        # get the needed tile metadata
        tilemeta = getTileCornerCoords(reftable_path,tilename)
        
        predtable = pd.read_csv(pred_path,names = ['predClass','relX','relY','width','heigth','probDet'], delim_whitespace = True)
        
        ## subset predtable to exclude records too close to the edge of the tile
        predtable = predtable[(predtable.relX >= excLim[0]) & (predtable.relX <= excLim[1]) & (predtable.relY >= excLim[2]) & (predtable.relY <= excLim[3])]
        
        ## now, it there are penguins away enough from the edge...
        if (len(predtable.index) > 0):
            ## calculate absolute and geo positions for each record
            predtable['absX'] = (predtable['relX'] * tileSize[0]) + tilemeta[0]
            predtable['absY'] = (predtable['relY'] * tileSize[1]) + tilemeta[1]
            predtable['geoX'] = (predtable['absX'] * pixelLength[0]) + tilemeta[2]
            predtable['geoY'] = (predtable['absY'] * pixelLength[1]) + tilemeta[3]
            
            ## add initial penguinID
            predtable['penguinID'] = [uuid.uuid4() for _ in range(len(predtable.index))] 
            
            ## add tilename
            predtable['tilename'] = tilename
            
            ## add the model class
            predtable['modelClass'] = modelClass
            
            ## sort columns and return
            predtable = predtable[['tilename', 'modelClass', 'penguinID', 'probDet', 'relX', 'relY', 'absX', 'absY', 'geoX', 'geoY']]
            
            return predtable 
    
    except OSError:
        print("cannot open", pred_path)


## Function to loop over list of predictions and use the above functions to get table of predictions
# reftable_path is the full path and name of the tile reference table
# modelClass is the model class: "adult_s2_best", etc.
# tileSize is a two-element array with width, height of the tile in pixels
# ortho_path is the full path and name of the orthomosaic image
# filespath is the full path to the directory with prediction .txt files
def getTableOfPengunLocs(reftable_path,ortho_path,filespath,modelClass,tileSize = (512,256),pixdistance=20):
    try:
        
        pixelLength = getPixelLength(ortho_path)
        filenames = glob.glob(filespath + "/*.txt")
        
        # calculate exclusion limits:
        excL_X = (pixdistance/2)/tileSize[0]
        excU_X = 1 - excL_X
        excL_Y = (pixdistance/2)/tileSize[1]
        excU_Y = 1 - excL_Y
        excLim = (excL_X,excU_X,excL_Y,excU_Y)
        
        dfs = []
        for filename in filenames:
            pred_path = filename
            dft = calcPenguinLocation(pred_path = pred_path,reftable_path = reftable_path,pixelLength = pixelLength,modelClass = modelClass,tileSize = tileSize,excLim = excLim)
            dfs.append(dft)
    
        df = pd.concat(dfs, ignore_index=True)
        
        return df
        
    except OSError:
        print("cannot concatenate ", modelClass)


###################
#'adult_s2_best'  'adult_stand_s5_best'  'chick_s_best'
## TRY IT
reftable_path = '/home/ubuntu/Workspace/tiles/croz_20191202_tilesGeorefTable.csv'
ortho_path = '/home/ubuntu/Workspace/orthos/croz_20191202.tif'
modelClass = 'chick_s_best'
filespath = '/home/ubuntu/Workspace/counts/' + modelClass + '/labels'
tileSize = (512,256)
pixdistance = 20
import time
start = time.time()
df = getTableOfPengunLocs(reftable_path=reftable_path,ortho_path=ortho_path,filespath=filespath,modelClass=modelClass,tileSize=tileSize,pixdistance=pixdistance)
df.to_csv('~/Workspace/croz_20191202_preds_' + modelClass + '.csv')
end = time.time()
print(end - start)
###################

