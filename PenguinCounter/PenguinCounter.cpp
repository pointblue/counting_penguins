//  PenguinCounter.cpp
//  PenguinCounter
//
//  Created by Tim DeBenedictis on 12/5/22.

#include "PenguinCounter.hpp"
#include "SSUtilities.hpp"

// Tile default constructor

Tile::Tile ( void )
{
    col = row = left = top = width = height -1;
    east = north = INFINITY;
    min = max = -1;
    mean = stdev = INFINITY;
}

// Tile constructor with dimensions

Tile::Tile ( int w, int h ) : Tile()
{
    width = w;
    height = h;
}

// Tile destructor

Tile::~Tile ( void )
{
    
}

// Reads predictions in YOLO format (or a variant thereof) from a text file at (path).
// If the classification override (clasOver) is non-negative, the prediction class
// will be overridden with it.
// Returns number of predictions read from file, or zero if file can't be read.

int Tile::readPredictions ( const string &path, int clasOver )
{
    FILE *file = fopen ( path.c_str(), "r" );
    if ( file == nullptr )
        return 0;
    
    string line;
    int numPredictions = 0;
    while ( fgetline ( file, line ) )
    {
        Penguin p;
        
        if ( sscanf ( line.c_str(), "%d %f %f %f %f %f", &p.clas, &p.cenx, &p.ceny, &p.width, &p.height, &p.prob ) == 6 )
        {
            if ( clasOver > -1 )
                p.clas = clasOver;
            penguins.push_back ( p );
            numPredictions++;
        }
    }
    
    fclose ( file );
    return numPredictions;
}

Ortho::Ortho ( void )
{
    width = height = -1;
    tileWidth = tileHeight = -1;
    tileOverH = tileOverV = -1;
    numTilesH = numTilesV = -1;
    
    geotransform[0][0] = geotransform[0][1] = geotransform[0][2] = INFINITY;
    geotransform[1][0] = geotransform[1][1] = geotransform[1][2] = INFINITY;
}

Ortho::~Ortho ( void )
{
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
            delete tiles[row][col];
        delete tiles[row];
    }
    
    delete tiles;
}

// Sets ortho width (w), height (h), tile width (tw), tile height (th),
// tile horizontal overlap (tho), and tile vertical overlap (tvo).
// Computes maximum possible number of tiles, horiztonal and vertical.
// Allocates matrix of tiles large enough to store all possible tiles.
// Returns number of tiles allocated in matrix or -1 on failure.

int Ortho::allocateTiles ( int w, int h, int tw, int th, int tho, int tvo )
{
    width = w;
    height = h;
    tileWidth = tw;
    tileHeight = th;
    tileOverH = tho;
    tileOverV = tvo;
    
    int tileNonOverlapWidth = tileWidth - tileOverH;
    int tileNonOverlapHeight = tileHeight - tileOverV;
    
    numTilesH = ( width + tileNonOverlapWidth - 1 ) / tileNonOverlapWidth;
    numTilesV = ( height + tileNonOverlapHeight - 1 ) / tileNonOverlapHeight;
    
    tiles = (Tile ***) calloc ( numTilesV, sizeof ( Tile ** ) );
    if ( tiles == nullptr )
        return -1;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        tiles[row] = (Tile **) calloc ( numTilesH, sizeof ( Tile * ) );
        if ( tiles[row] == nullptr )
            return -1;
    }
    
    return numTilesH * numTilesV;
}

bool Ortho::readMetadata ( const string &path )
{
    return false;
}

// Reads tile index CSV file at (path).
// Returns number of tile entries read from index.

int Ortho::readTileIndex ( const string &path )
{
    FILE *file = fopen ( path.c_str(), "r" );
    if ( file == nullptr )
        return false;
    
    // read CSV header line
    
    string line;
    fgetline ( file, line );
    
    // read CSV tile lines
    
    int numTiles = 0;
    while ( fgetline ( file, line ) )
    {
        vector<string> fields = split_csv ( line );
        if ( fields.size() < 5 )
            continue;

        Tile *tile = new Tile ( tileWidth, tileHeight );
        if ( tile == nullptr )
            continue;
        
        // Get tile name.
        
        tile->name = fields[0];

        // Get top left corner pixel within ortho and corresponding geographic coordinates.
        
        tile->left = strtoint ( fields[1] );
        tile->top = strtoint ( fields[2] );
        tile->east = strtofloat64( fields[3] );
        tile->north = strtofloat64 ( fields[4] );

        // If present, get image statistical characteristics
        
        if ( fields.size() > 8 )
        {
            tile->min = strtoint ( fields[5] );
            tile->max = strtoint ( fields[6] );
            tile->mean = strtoint ( fields[7] );
            tile->stdev = strtoint ( fields[8] );
        }

        // Parse tile row and column in ortho from name.
        
        int col = -1, row = -1;
        size_t pos = tile->name.find_last_of ( '_' );
        if ( pos != string::npos )
            pos = tile->name.find_last_of ( '_', pos - 1 );
        if ( pos != string::npos )
        {
            string col_row = tile->name.substr ( pos + 1, string::npos );
            if ( sscanf ( col_row.c_str(), "%d_%d", &col, &row ) == 2 )
            {
                tile->col = col;
                tile->row = row;
            }
        }

        // Store tile at appropriate location in matrix.
        
        if ( col >= 0 && col < numTilesH )
        {
            if ( row >= 0 && row < numTilesV )
            {
                tiles[row][col] = tile;
                numTiles++;
            }
        }
    }
    
    fclose ( file );
    return numTiles;
}

int Ortho::readPredictions ( const string &parentDir, int clasOverride )
{
    int numPredictions = 0;
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile != nullptr )
            {
                string path = parentDir;
                if ( path.back() != '/' )
                    path += '/';
                path += tile->name;
                path = setFileExt ( path, ".txt" );
                numPredictions += tile->readPredictions ( path, clasOverride );
            }
        }
    }
    
    return numPredictions;
}
