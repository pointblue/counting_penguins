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

// Penguin class identifiers

struct Penguin
{
    enum Class                 // Penguin class identifiers
    {
        kAny = -1,             // all/ant penguin classes
        kNone = 0,             // no_ADPE
        kAdultStand = 1,       // ADPE_a_stand
        kAdult = 2,            // ADPE_a
        kChick = 3             // ADPE_j
    };

    Class clas;                // classification (kAdultStand, kAdult, etc.)
    float prob;                // detection probability
    float cenx, ceny;          // bounding box center position as fraction of tile width/height
    float width, height;       // bounding box width and height as fraction of tile width/height
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
    vector<Penguin> predictions;   // vector of penguins predicted (found by AI) in tile
    vector<Penguin> validations;   // vector of penguins validated (found by human inspector) in tile. If empty, humans have not inspected this tile.
                                   // A single penguin of class kNone means human inspectors found no penguins in this tile.
    
    Tile ( void );                  // default constructor
    Tile ( int width, int height ); // constructor with dimensions
    virtual ~Tile ( void );         // destructor

    int readPredictions ( const string &path, Penguin::Class clasOver = Penguin::kNone );
    static bool getColRowFromName ( const string &name, int &col, int &row );
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
    int readPredictions ( const string &path, Penguin::Class clasOver = Penguin::kNone );
    int readValidations ( const string &path );
    int countPenguins ( Penguin::Class clas, bool predictions );
};

#endif /* PenguinCounter_hpp */
