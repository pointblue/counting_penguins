### This file contains the functions and classes that inspect predictions by tile
### and assigns each penguin a unique ID. It then re-IDs each penguin based on it's location 
### being close (some radius distance) to another detection in a different tile

## The logic is as follows:
## A function first retrieves the original orthomosaic and captures the extent and ncol/nrow data
## With these, it calculates how much distance in latitude and longitude is covered by a pixel 

## A second function takes as input a tile and queries the reference table to obtain 
## its min(lat) and min(lon), and minimum absolute position(ie., position of lower left corner)

## A third function takes all predictions in the tile and uses the information returned by the above
## functions to database the absolute and georeferenced position of each detection, along with 
## the probability of the detection. It also assigns a GUID to the detection

## A fourth function compares the predictions in this tile to those of an adjacent tile
## First note that tiles are counted starting on the lower-left corner and moving right and down, 
## as indicated in the tiling code:  
##		cropped_img = img[yy:min(yy+self.ySize, height), xx:min(xx+self.xSize, width)]
## So, we proceed from the top-left, moving right and then down.
## This function compares the current tile to the adjacent (A) tilee:
##		In that A tile we look for detections within the radius R of each detection in the current tile
##		If a detection is found in A within the radius R of a detection in the current tile, 
##		the current detection inherits the ID of the detection in the A tile
## That is, this function loops through all detections in the current file and all detections in the A tile

## A fifth function acts as a wrapper of the previous function:
## It finds if there is an upper-left tile to the current tile and passes it to the above function
## It then does the same for a top-adjacent tile, and then a left-adjacent tile


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
def calcPenguinLocation(pred_path,reftable_path,pixelLength,modelClass,tileSize):
    try:
    
        # get tile name from pred_path
        tilename = Path(pred_path).stem + ".jpg"
        
        # get the needed tile metadata
        tilemeta = getTileCornerCoords(reftable_path,tilename)
        
        predtable = pd.read_csv(pred_path,names = ['predClass','relX','relY','width','heigth','probDet'], delim_whitespace = True)
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
def getTableOfPengunLocs(reftable_path,ortho_path,filespath,modelClass,tileSize = (512,256)):
    try:
        
        pixelLength = getPixelLength(ortho_path)
        filenames = glob.glob(filespath + "/*.txt")
        dfs = []
        for filename in filenames:
            pred_path = filename
            dft = calcPenguinLocation(pred_path = pred_path,reftable_path = reftable_path,pixelLength = pixelLength,modelClass=modelClass,tileSize = tileSize)
            dfs.append(dft)
    
        df = pd.concat(dfs, ignore_index=True)
        
        return df
        
    except OSError:
        print("cannot concatenate ", modelClass)


###################
## TRY IT
reftable_path = '/home/ubuntu/Workspace/tiles/croz_20191202_tilesGeorefTable.csv'
ortho_path = '/home/ubuntu/Workspace/orthos/croz_20191202.tif'
filespath = '/home/ubuntu/Workspace/counts/adult_s2_best/labels'
modelClass = 'adult_s2_best'
df = getTableOfPengunLocs(reftable_path=reftable_path,ortho_path=ortho_path,filespath=filespath,modelClass=modelClass)
###################

# Now loop through the table to find dupes using the below functions

def findDupes(abx, aby, pID, df, res, pixdistance):
    try:
    
        tdf = df[(df.absX >= (abx-pixdistance)) & (df.absX <= (abx+pixdistance)) & (df.absY >= (aby-pixdistance)) & (df.absY <= (aby+pixdistance))]
        if (len(tdf.index)==1):
            tdf = tdf.reset_index(drop=True)
            tdf.loc[:,"newPenguinID"] = pID
            
            
        else:
            tdf = tdf[~tdf.penguinID.isin(res.penguinID)]
            if (len(tdf.index) > 0):
                tdf.loc[:,"newPenguinID"] = pID
                tdf = tdf.reset_index(drop=True)
            else:
                tdf = pd.DataFrame()
            
        return(tdf)
    
    except OSError:
        print("cannot find duplicates")


def examPredictions(df, res, pixdistance = 20):
    try:
        for index, row in df.iterrows():
            abx = row["absX"]
            aby = row["absY"]
            pID = row["penguinID"]
            rdf = findDupes(abx, aby, pID, df, res, pixdistance)
            rdf = rdf.reset_index(drop=True)            
            res = pd.concat([res,rdf],axis=0)
        
        return(res)
        
    except OSError:
        print("cannot examine predictions")

res = pd.DataFrame()

import time
start = time.time()
qdf = examPredictions(df= df, res=res, pixdistance = 20)
end = time.time()
print(end - start)



### That takes too long!
## Let's try creating the target column ahead, then:
## find the dupes, 
## if any have newID: assign that to all (if any has all should have)
## else: sort by ordID, retrieve first ordID's penguinID, assign to all

blankID = uuid.UUID('00000000-0000-0000-0000-000000000000')
kdf = df.head(20)
kdf["newPenguinID"] = blankID
kdf.insert(0, 'ordinalID', range(0, len(kdf.index)))

def examPredictions(df, blankID, pixdistance = 20):
    try:
        for index, row in df.iterrows():
            abx = row["absX"]
            aby = row["absY"]
            pID = row["penguinID"]; 
            tdf = df[(df.absX >= (abx-pixdistance)) & (df.absX <= (abx+pixdistance)) & (df.absY >= (aby-pixdistance)) & (df.absY <= (aby+pixdistance))]
            tdf = tdf.reset_index(drop=True)
            tdf.loc[:,"distance"] = np.sqrt(((tdf.absX-abx)**2) + ((tdf.absY-aby)**2))
            tdf = tdf[tdf["distance"] <= pixdistance]
            
            # split first by number of records
            if(len(tdf.index) == 1):
                if(tdf['newPenguinID'].iloc[0] == blankID):
                    df.loc[(df.penguinID == pID),'newPenguinID']= pID
                # else do nothing
                # need to partition the conditions this way and not combined, so that else is...
                
            else:
                # there are several dupes 
                npvals = tdf['newPenguinID'].tolist()
                if(npvals.count(blankID) > 0):
                    # we only care to deal with those that have blankIDs, but it could be all or some of the values...
                    # if some, sort by ordinal and re-collect the pID to be the first ordinal, otherwise use current collected pID, then assign the pID to all
                    if(npvals.count(blankID) < len(tdf.index)):
                        # some values already have pID - sort by ordinal for those not with blanks and re-capture the pID from the first one
                        nbtdf = tdf[~tdf.newPenguinID.isin(list(str(blankID)))]
                        nbtdf = nbtdf.sort_values('ordinalID')
                        pID = nbtdf['penguinID'].iloc[0]
    
                    for index, trow in tdf.iterrows():
                        tpID = trow["penguinID"]
                        df.loc[(df.penguinID == tpID),'newPenguinID']= pID
        
        return(df)
                         
    except OSError:
        print("cannot examine predictions")


wdf = examPredictions(df=kdf, blankID=blankID, pixdistance = 20)

wdf.newPenguinID.nunique()


df["newPenguinID"] = blankID
df.insert(0, 'ordinalID', range(0, len(df.index)))
import time
start = time.time()
res = examPredictions(df = df, blankID=blankID, pixdistance = 20)
end = time.time()
print(end - start)
# 4.5 hrs per model for the big ortho

Try this ortho:
croz_20191202.tif
http://deju-penguinscience.s3-us-east-2.amazonaws.com/PenguinCounting/index.html?prefix=PenguinCounting/croz_20191202/tiles/

