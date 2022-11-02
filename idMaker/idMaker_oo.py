### This file contains the functions and class that inspect predictions by tile
### and assigns each penguin a unique ID. It then re-IDs each penguin based on it's location 
### being close (some radius distance) to another detection in a different tile
### The result is a table of detections with unique penguin IDs


import os
import sys
import glob
import rasterio
import pandas as pd
import uuid
from pathlib import Path
import numpy as np

## This is the class definition
# reftable_path is the full path and name of the tile reference table
# ortho_path is the full path and name of the orthomosaic image
# filespath is the full path to the directory with prediction .txt files
# modelClass is the model class: "adult_s2_best", etc.
# tileSize is a two-element array with width, height of the tile in pixels
# pixdistance (plus one pixel) is the minimum distance two detections must be part to not be counted as duplicates
# res is a (empty?) pandas data.frame that will be populated by the class
class IDmaker(object):
    """docstring for IDmaker"""
    
    def __init__(self, reftablePath, orthoPath, filesPath, modelClass, tileSize = (512,256), pixdistance = 20):
        super(IDmaker, self).__init__()
        self.reftable_path = reftablePath
        self.ortho_path = orthoPath
        self.filespath = filesPath
        self.modelClass = modelClass
        self.tileSize = tileSize
        self.pixdistance = pixdistance
    
    def makeId(self, res):  #This is the main function
        try:
            df = self.getTableOfPengunLocs()
            
            for index, row in df.iterrows():
                abx = row["absX"]
                aby = row["absY"]
                pID = row["penguinID"]
                rdf = self.findDupes(abx=abx, aby=aby, pID=pID, df=df, res=res)
                rdf = rdf.reset_index(drop=True)            
                res = pd.concat([res,rdf],axis=0)
            
            return(res)
            
        except OSError:
            print("cannot examine predictions")
    
    ## Function to calculate the length and width of a pixel
    def getPixelLength(self):
        try:
            rast = rasterio.open(self.ortho_path)
            ncol = rast.width
            nrow = rast.height
            rextent = rast.bounds
            
            pixW = (rextent[2] - rextent[0])/ncol
            pixH = (rextent[3] - rextent[1])/ncol
            
            return [pixW, pixH]
            
        except OSError:
            print("cannot open", orthopath)
    
    ## Function that retrieves the absolute and geocoordinates of a table's lower left corner
    # tilename is the name of the tile for which the coordinates are being sought, passed from calcPenguinLocation
    def getTileCornerCoords(self,tilename):
        try:
            reftable = pd.read_csv(self.reftable_path)
            tilemeta = reftable[reftable.tileName == tilename]
            tmd = tilemeta.to_numpy()
            #xmin, ymin, easting, northing
            return [tmd[0,1],tmd[0,2],tmd[0,3],tmd[0,4]]
        
        except OSError:
            print("cannot open", reftable_path)
    
    ## Function to position each detection in the ortho 
    # pred_path is the full path and name of prediction table for a given tile, from function getTableOfPengunLocs
    # pixelLength is the length of each pixel in width and height, based on the ortho projection, from function getPixelLength
    def calcPenguinLocation(self, pred_path, pixelLength):
        try:
        
            # get tile name from pred_path
            tilename = Path(pred_path).stem + ".jpg"
            
            # get the needed tile metadata
            tilemeta = self.getTileCornerCoords(tilename=tilename)
            
            predtable = pd.read_csv(pred_path,names = ['predClass','relX','relY','width','heigth','probDet'], delim_whitespace = True)
            ## calculate absolute and geo positions for each record
            predtable['absX'] = (predtable['relX'] * self.tileSize[0]) + tilemeta[0]
            predtable['absY'] = (predtable['relY'] * self.tileSize[1]) + tilemeta[1]
            predtable['geoX'] = (predtable['absX'] * pixelLength[0]) + tilemeta[2]
            predtable['geoY'] = (predtable['absY'] * pixelLength[1]) + tilemeta[3]
            
            ## add initial penguinID
            predtable['penguinID'] = [uuid.uuid4() for _ in range(len(predtable.index))] 
            
            ## add tilename
            predtable['tilename'] = tilename
            
            ## add the model class
            predtable['modelClass'] = self.modelClass
            
            ## sort columns and return
            predtable = predtable[['tilename', 'modelClass', 'penguinID', 'probDet', 'relX', 'relY', 'absX', 'absY', 'geoX', 'geoY']]
            
            return predtable 
        
        except OSError:
            print("cannot open", pred_path)
        
    ## Function to loop over list of predictions and use the above functions to get table of predictions
    def getTableOfPengunLocs(self):
        try:
            
            pixelLength = self.getPixelLength()
            filenames = glob.glob(self.filespath + "/*.txt")
            dfs = []
            for filename in filenames:
                pred_path = filename
                dft = self.calcPenguinLocation(pred_path = pred_path, pixelLength = pixelLength)
                dfs.append(dft)
        
            df = pd.concat(dfs, ignore_index=True)
            
            return df
            
        except OSError:
            print("cannot concatenate ", modelClass)
        
    ## Function to take one record and find its duplicate detections within pixdistance from it
    # abx is the current record X location, passed from makeId
    # aby is the current record Y location, passed from makeId
    # pID is the current record penguinID, passed from makeId
    # df is the data table being de-duplicated, passed from makeId
    # res is the current tally table of de-duplicated records, passed from makeId
    def findDupes(self, abx, aby, pID, df, res):
        try:
        
            tdf = df[(df.absX >= (abx-self.pixdistance)) & (df.absX <= (abx+self.pixdistance)) & (df.absY >= (aby-self.pixdistance)) & (df.absY <= (aby+self.pixdistance))]
            if (len(tdf.index)==1):
                tdf = tdf.reset_index(drop=True)
                tdf.loc[:,"distance"] = np.sqrt(((tdf.absX-abx)**2) + ((tdf.absY-aby)**2))
                tdf = tdf[tdf["distance"] <= self.pixdistance]
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
    

###################
## TRY IT
rtp = '/home/ubuntu/Workspace/tiles/croz_20191202_tilesGeorefTable.csv'
ortp = '/home/ubuntu/Workspace/orthos/croz_20191202.tif'
filp = '/home/ubuntu/Workspace/counts/adult_s2_best/labels'
modelC = 'adult_s2_best'
#instantiate the object...
idm = IDmaker(reftablePath=rtp, orthoPath=ortp, filesPath=filp, modelClass=modelC, tileSize = (512,256), pixdistance = 20)
#run the method...
res = pd.DataFrame()
import time
start = time.time()
predtable = idm.makeId(res=res)
end = time.time()
print(end - start)
###################