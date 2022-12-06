//
//  PenguinCounter.hpp
//  PenguinCounter
//
//  Created by Tim DeBenedictis on 12/5/22.
//

#ifndef PenguinCounter_hpp
#define PenguinCounter_hpp

#include <stdio.h>
#include <string>
#include <vector>

using namespace std;

const uint8_t kAdultStand = 0;
const uint8_t kAdult = 1;
const uint8_t kChick = 2;

struct Penguin
{
    float cenx, ceny;          // bounding box center position as fraction of tile width/height
    float width, height;       // bounding box width and height as fraction of tile width/height
    float prob;                // detection probability
    int   clas;                // classification (kAdultStand, kAdult
};

class Tile
{
public:
    string name;                   // file name
    int col, row;                  // position in tile matrix generated from parent orthomosaic; counted from (0,0)
    int left, top;                 // coordinates of (left,top) corner pixel in parent orthomosaic
    int width, height;             // dimensions in pixels
    double east, north;            // geographical longitude and latitude corresonding to (left,top)
    int min, max;                  // minimum and maximum grayscale value
    float mean, stdev;             // mean and standard deviatio of grayscale values
    vector<Penguin> penguins;      // vector of penguins found in tile
    
    Tile ( void );                  // default constructor
    Tile ( int width, int height ); // constructor with dimensions
    virtual ~Tile ( void );         // destructor
    
    int readPredictions ( const string &path, int clasOver = -1 );
};

class Ortho
{
public:
    string name;                    // file name
    int width, height;              // overall dimensions in pixels
    int tileWidth, tileHeight;      // tile dimensions in pixels
    int tileOverH, tileOverV;       // tile horizontal and vertical overlap in pixels
    int numTilesH, numTilesV;       // maximum possible numner of tiles in horizontal and vertical direction
    Tile ***tiles;                  // matrix of pointers to tiles, arranged in columns within rows.
    double geotransform[2][3];      // converts pixel (x,y) coordinates to (lon,lat)

    Ortho ( void );                 // default constructor
    virtual ~Ortho ( void );        // destructor
    
    int allocateTiles ( int w, int h, int tw, int th, int tho, int tvo );
    int readTileIndex ( const string &path );
    bool readMetadata ( const string &path );
    int readPredictions ( const string &path, int clasOver = -1 );
};

#endif /* PenguinCounter_hpp */
