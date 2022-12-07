//  PenguinCounter.cpp
//  PenguinCounter
//
//  Created by Tim DeBenedictis on 12/5/22.

#include <algorithm>
#include "PenguinCounter.hpp"
#include "SSUtilities.hpp"

// Penguin default constructor

Penguin::Penguin ( void )
{
    clas = kAny;
    prob = INFINITY;
    cenx = ceny = INFINITY;
    sizex = sizey = INFINITY;
    left = top = right = bottom = -1;
}

// destructor

Penguin::~Penguin ( void )
{
    
}

void Penguin::getPixelCenter ( int &h, int &v )
{
    h = ( left + right ) / 2;
    v = ( top + bottom ) / 2;
}

void Penguin::getPixelSize ( int &w, int &h )
{
    w = right - left;
    h = bottom - top;
}

// Tile default constructor

Tile::Tile ( void )
{
    left = top = width = height -1;
    east = north = INFINITY;
    min = max = -1;
    mean = stdev = INFINITY;
    validated = false;
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

// Parses tile row and column in ortho from name.
// If successful, returns true and (col,row) receive zero-based tile position.
// On failure, returns false and (col,row) are set to -1.

bool Tile::getColRowFromName ( const string &name, int &col, int &row )
{
    col = row = -1;
    size_t pos = name.find_last_of ( '_' );
    if ( pos != string::npos )
        pos = name.find_last_of ( '_', pos - 1 );
    if ( pos != string::npos )
    {
        string col_row = name.substr ( pos + 1, string::npos );
        if ( sscanf ( col_row.c_str(), "%d_%d", &col, &row ) == 2 )
            return true;
    }
    
    return false;
}

// Reads predictions in YOLO format (or a variant thereof) from a text file at (path).
// The classification override (clasOver) will be used if not Penguin::kNone.
// Returns number of predictions read from file, or zero if file can't be read.

int Tile::readPredictions ( const string &path, Penguin::Class clasOverride )
{
    FILE *file = fopen ( path.c_str(), "r" );
    if ( file == nullptr )
        return 0;
    
    string line;
    int numPredictions = 0;
    while ( fgetline ( file, line ) )
    {
        Penguin p;
        
        if ( sscanf ( line.c_str(), "%d %f %f %f %f %f", &p.clas, &p.cenx, &p.ceny, &p.sizex, &p.sizey, &p.prob ) == 6 )
        {
            if ( clasOverride != Penguin::kNone )
                p.clas = clasOverride;
            setPenguinBounds ( p );
            predictions.push_back ( p );
            numPredictions++;
        }
    }
    
    fclose ( file );
    return numPredictions;
}

// Computes penguin bounding box in pixels in parent orthomosaic
// from bounding box relative to local tile coordinates.

void Tile::setPenguinBounds ( Penguin &p )
{
    int w = width * p.sizex, h = height * p.sizey;
    int x = width * p.cenx, y = height * p.ceny;
    p.left = left + x - w / 2;
    p.top = top + y - w / 2;
    p.right = left + w;
    p.bottom = top + h;
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
        // If successful, store tile at appropriate location in matrix.
        
        int col = -1, row = -1;
        if ( Tile::getColRowFromName ( tile->name, col, row ) )
        {
            if ( col >= 0 && col < numTilesH )
            {
                if ( row >= 0 && row < numTilesV )
                {
                    tiles[row][col] = tile;
                    numTiles++;
                }
            }
        }
    }
    
    fclose ( file );
    return numTiles;
}

int Ortho::readPredictions ( const string &parentDir, Penguin::Class clasOverride )
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

// Reads validation labels from a CSV file at the specified path.
// The expected format is: tileName,label,x,y,width,height. Example:
// croz_20201129_144_434,no_ADPE,0.53943,0.507131,0.037752,0.092282
// croz_20201129_111_349,ADPE_a,0.469169,0.855705,0.065017,0.088087
// croz_20201129_141_371,ADPE_a_stand,0.25,0.911074,0.036074,0.116611
// Assumes this Ortho's tiles have already been allocated & populated.
// Returns the total number of validations read, or zero on failure.

int Ortho::readValidations ( const string &path )
{
    FILE *file = fopen ( path.c_str(), "r" );
    if ( file == nullptr )
        return 0;
    
    // read CSV header line
    
    string line;
    fgetline ( file, line );
    
    int numValidations = 0;
    while ( fgetline ( file, line ) )
    {
        vector<string> fields = split_csv ( line );
        if ( fields.size() < 6 )
            continue;

        int col = -1, row = -1;
        if ( ! Tile::getColRowFromName ( fields[0], col, row ) )
            continue;
        
        // Make sure we have a tile to store the validation into
        
        Tile *tile = tiles[row][col];
        if ( tile == nullptr )
            continue;
        
        tile->validated = true;
        Penguin p;

        // Get class label.
        
        if ( fields[1].compare ( "no_ADPE" ) == 0 )
            p.clas = Penguin::kNone;
        else if ( fields[1].compare ( "ADPE_a" ) == 0 )
            p.clas = Penguin::kAdult;
        else if ( fields[1].compare ( "ADPE_a_stand" ) == 0 )
            p.clas = Penguin::kAdultStand;
        else if ( fields[1].compare ( "ADPE_a_chick" ) == 0 )
            p.clas = Penguin::kChick;
        else
            continue;
        
        p.prob = 1.0;

        // Get bounding box
        
        if ( fields.size() > 10 )
        {
            // format of croz_20211127:
            // img_file,category,box_left,box_top,box_height,box_width,img_width,img_height,int_category,box_center_w,box_center_h,box_area
            
            p.cenx = strtofloat ( fields[9] );
            p.ceny = strtofloat ( fields[10] );
            p.sizex = strtofloat ( fields[5] );
            p.sizey = strtofloat ( fields[4] );
        }
        else
        {
            // format of croz_20201129:
            // tileName,label,x,y,width,height

            p.cenx = strtofloat ( fields[2] );
            p.ceny = strtofloat ( fields[3] );
            p.sizex = strtofloat ( fields[4] );
            p.sizey = strtofloat ( fields[5] );
        }
        
        // Discard "no_ADPE" labels.
        
        tile->setPenguinBounds ( p );
        if ( p.clas != Penguin::kNone )
            tile->validations.push_back ( p );

        numValidations++;
    }
    
    fclose ( file );
    return numValidations;
}

// Counts total number of penguins (predictions or validations) of a particular class (class)
// for all tiles in this ortho. If clas is Penguin::kAny, counts all penguins of any class in the ortho.
// If validatedTilesOnly is true, only counts penguins in tiles with validations; implied if predictions is false.

int Ortho::countPenguins ( Penguin::Class clas, bool predictions, bool validatedTilesOnly )
{
    int total = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile != nullptr )
            {
                if ( validatedTilesOnly && tile->validations.size() == 0 )
                    continue;
                
                vector<Penguin> &penguins = predictions ? tile->predictions : tile->validations;
                for ( Penguin &p : penguins )
                    if ( p.clas == clas || clas == Penguin::kAny )
                        total++;
            }
        }
    }

    return total;
}

// Counts total number of tiles in this ortho that have been validated
// by a numan inspector.

int Ortho::countValidatedTiles ( void )
{
    int total = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile != nullptr && tile->validated )
                total++;
        }
    }

    return total;
}

// Counts total number of tiles in this ortho that contain
// no predicted (or validated) penguins.

int Ortho::countEmptyTiles ( bool predictions )
{
    int total = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr )
                continue;
            
            if ( predictions && tile->predictions.size() == 0 )
                total++;
            else if ( tile->validated && tile->validations.size() == 0 )
                total++;
        }
    }

    return total;
}

int Ortho::getPenguinStats ( Penguin::Class clas, bool predictions, Penguin &min, Penguin &max, Penguin &mean, Penguin &stdev )
{
    int total = 0;
    
    mean.cenx = mean.ceny = mean.sizex = mean.sizey = 0;
    stdev.cenx = stdev.ceny = stdev.sizex = stdev.sizey = 0;
    min.cenx = min.ceny = min.sizex = min.sizey = INFINITY;
    max.cenx = max.ceny = max.sizex = max.sizey = -INFINITY;

    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile != nullptr )
            {
                vector<Penguin> &penguins = predictions ? tile->predictions : tile->validations;
                for ( Penguin &p : penguins )
                {
                    if ( p.clas == clas || clas == Penguin::kAny )
                    {
                        mean.cenx += p.cenx;
                        mean.ceny += p.ceny;
                        mean.sizex += p.sizex;
                        mean.sizey += p.sizey;

                        stdev.cenx += p.cenx * p.cenx;
                        stdev.ceny += p.ceny * p.ceny;
                        stdev.sizex += p.sizex * p.sizex;
                        stdev.sizey += p.sizey * p.sizey;

                        min.cenx = std::min ( min.cenx, p.cenx );
                        min.ceny = std::min ( min.ceny, p.ceny );
                        min.sizex = std::min ( min.sizex, p.sizex );
                        min.sizey = std::min ( min.sizey, p.sizey );

                        max.cenx = std::max ( max.cenx, p.cenx );
                        max.ceny = std::max ( max.ceny, p.ceny );
                        max.sizex = std::max ( max.sizex, p.sizex );
                        max.sizey = std::max ( max.sizey, p.sizey );

                        total++;
                    }
                }
            }
        }
    }

    if ( total > 0 )
    {
        mean.cenx /= total;
        mean.ceny /= total;
        mean.sizex /= total;
        mean.sizey /= total;
        
        stdev.cenx = sqrt ( stdev.cenx / total - mean.cenx * mean.cenx );
        stdev.ceny = sqrt ( stdev.ceny / total - mean.ceny * mean.ceny );
        stdev.sizex = sqrt ( stdev.sizex / total - mean.sizex * mean.sizex );
        stdev.sizey = sqrt ( stdev.sizey / total - mean.sizey * mean.sizey );
    }
    
    return total;
}
