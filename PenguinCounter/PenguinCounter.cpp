//  PenguinCounter.cpp
//  PenguinCounter
//
//  Created by Tim DeBenedictis on 12/5/22.

#include <algorithm>
#include <gdal_priv.h>
#include <opencv2/opencv.hpp>

#include "GImage.h"
#include "PenguinCounter.hpp"
#include "SSUtilities.hpp"

// Penguin default constructor

Penguin::Penguin ( void )
{
    clas = kAny;
    prob = INFINITY;
    cenx = ceny = INFINITY;
    sizex = sizey = INFINITY;
}

// destructor

Penguin::~Penguin ( void )
{
    
}

// Returns true if center of Penguin p is within this Penguin's bounding box.

bool Penguin::overlaps ( Penguin &p )
{
    float radx = sizex / 2.0, rady = sizey / 2.0;
    if ( p.cenx > cenx + radx || p.cenx < cenx - radx || p.ceny > ceny + rady || p.ceny < ceny - rady )
        return false;
    else
        return true;
}

// Returns true if any Penguin in the vector (penguins) overlaps this penguin
// and has a higher detection probability. Populates vector of duplicate penguins
// (duplicates), containing zero elements if this Penguin has no duplicates.

bool Penguin::hasDuplicates ( vector<Penguin> &penguins, vector<Penguin> &duplicates )
{
    for ( Penguin &p : penguins )
    {
        if ( *this != p && overlaps ( p ) )
        {
            if ( prob < 1.0 && prob < p.prob )  // this Penguin is a prediction, compare probability to other Penguin.
                duplicates.push_back ( p );
            else if ( prob == 1.0 )             // this Penguin is a validation, ignore probability of other Penguin.
                duplicates.push_back ( p );
        }
    }
    return duplicates.size() > 0;
}

// Returns true if this Penguin overlaps any Penguin in (tile)'s vector of
// Penguins predictions or validation labels with a higher detection probability.
// Populates vector of duplicate Penguins (duplicates); will contain zero elements
// if this Penguin has no duplicates.

bool Penguin::hasDuplicates ( Tile *tile, bool predictions, vector<Penguin> &duplicates )
{
    if ( tile == nullptr )
        return false;
    
    return hasDuplicates ( predictions ? tile->predictions : tile->validations, duplicates );
}

// Returns true if this Penguin overlaps any Penguin (prediction or validation)
// in ortho tile at or adjacent to (row,col) with a higher detection probability.
// Populates vector of duplicate Penguins (duplicates); will contain zero elements
// if this Penguin has no duplicates.

bool Penguin::hasDuplicates ( Ortho *ortho, int row, int col, bool predictions, vector<Penguin> &duplicates )
{
    Tile *tile = ortho->tiles[row][col];
    if ( tile == nullptr )
        return false;
    
    // Get tile boundaries within ortho, inset by tile overlap margins
    
    float tileLeft = tile->left + ortho->tileOverH, tileTop = tile->top + ortho->tileOverV;
    float tileRight = tile->left + ortho->tileWidth - ortho->tileOverH, tileBottom = tile->top + ortho->tileHeight - ortho->tileOverV;
    
    // Get Penguin bounding box
    
    float radx = sizex / 2.0, rady = sizey / 2.0;
    float left = cenx - radx, right = cenx + radx;
    float top = ceny - rady, bottom = ceny + rady;
    
    // Check if this Penguin has duplicates within this Tile,
    // or (if needed) within adjacent tiles.
    
    bool dup = hasDuplicates ( tile, predictions, duplicates );
    
    if ( left < tileLeft && col > 0 )
        dup = dup || hasDuplicates ( ortho->tiles[row][col-1], predictions, duplicates );
    
    if ( top < tileTop && row > 0 )
        dup = dup || hasDuplicates ( ortho->tiles[row-1][col], predictions, duplicates );
    
    if ( right > tileRight && col < ortho->numTilesH - 1 )
        dup = dup || hasDuplicates ( ortho->tiles[row][col+1], predictions, duplicates );
    
    if ( bottom > tileBottom && row < ortho->numTilesV - 1 )
        dup = dup || hasDuplicates ( ortho->tiles[row+1][col], predictions, duplicates );
    
    return dup;
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
            predictions.push_back ( p );
            numPredictions++;
        }
    }
    
    fclose ( file );
    return numPredictions;
}

// Converts penguin bounding box from tile coordinates (i.e. fraction of tile size)
// to absolute orthomosaic coordinates (i.e. pixels relative to ortho top left)

void Tile::tileToOrthoCoords ( Penguin &p )
{
    p.cenx = left + width * p.cenx;
    p.ceny = top + height * p.ceny;
    p.sizex = width * p.sizex;
    p.sizey = height * p.sizey;
}

// Converts penguin bounding box absolute orthomosaic coordinates (i.e. pixels relative to ortho top left)
// to tile-relative coordinates (i.e. fraction of tile size)

void Tile::orthoToTileCoords ( Penguin &p )
{
    p.cenx = ( p.cenx - left ) / width;
    p.ceny = ( p.ceny - top ) / height;
    p.sizex /= width;
    p.sizey /= height;
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

// Opens Ortho TIFF file at (path), reads image size and geotransform.
// Returns true if successful or false on failure.

bool Ortho::readMetadata ( const string &path )
{
    GDALAllRegister();
    GDALDataset *fin = (GDALDataset*) GDALOpen ( path.c_str(), GA_ReadOnly );
    if ( fin == NULL )
        return false;
    
    width = fin->GetRasterXSize();
    height = fin->GetRasterYSize();
    
    CPLErr err = fin->GetGeoTransform ( &geotransform[0][0] );
    GDALClose ( fin );
    
    return err == CE_None ? true : false;
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
        
        if ( p.clas != Penguin::kNone )
            tile->validations.push_back ( p );

        numValidations++;
    }
    
    fclose ( file );
    return numValidations;
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
                if ( validatedTilesOnly && tile->validated == false )
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

// Counts total number of tiles in this ortho that contain zero penguin predictions (if predictions is true)
// or zero penguin validation  labels (if predictions is false).
// If validatedTilesOnly is true, only counts empty tiles that have been human-validated.

int Ortho::countEmptyTiles ( bool predictions, bool validatedTilesOnly )
{
    int total = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr )
                continue;
            
            if ( validatedTilesOnly && tile->validated == false )
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

// Deletes penguin predictions of the specified class (clas), or of any class if clas is Penguin::kAny.
// whose bounding boxes are smaller than the specified minimum (minSizeX, minSizeY)
// or larger than the specified maximum (maxSizeX, maxSizeY)
// Returns total number of penguins deleted.

int Ortho::deleteOutsizedPenguins ( Penguin::Class clas, float minSizeX, float maxSizeX, float minSizeY, float maxSizeY )
{
    int total = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile != nullptr )
            {
                vector<Penguin> &penguins = tile->predictions;
                auto p = penguins.begin();
                while ( p != penguins.end() )
                {
                    if ( ( p->clas == clas || clas == Penguin::kAny ) )
                    {
                        if ( p->sizex < minSizeX || p->sizex > maxSizeX || p->sizey < minSizeY || p->sizey > maxSizeY )
                        {
                            p = penguins.erase ( p );
                            total++;
                            continue;
                        }
                    }
                    p++;
                }
            }
        }
    }

    return total;
}

int Ortho::deleteImprobablePenguins ( Penguin::Class clas, float minProb )
{
    int total = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile != nullptr )
            {
                vector<Penguin> &penguins = tile->predictions;
                auto p = penguins.begin();
                while ( p != penguins.end() )
                {
                    if ( ( p->clas == clas || clas == Penguin::kAny ) )
                    {
                        if ( p->prob < minProb )
                        {
                            p = penguins.erase ( p );
                            total++;
                            continue;
                        }
                    }
                    p++;
                }
            }
        }
    }

    return total;
}

// Converts all Penguin prediction and validation label bounding boxes
// from tile-relative to ortho-absolute coordinates.

void Ortho::tileToOrthoPenguins ( void )
{
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr )
                continue;
            
            for ( Penguin &p : tile->predictions )
                tile->tileToOrthoCoords ( p );
            
            for ( Penguin &p : tile->validations )
                tile->tileToOrthoCoords ( p );
        }
    }
}

// Converts all Penguin prediction and validation label bounding boxes
// from ortho-absolute to tile-relative coordinates.

void Ortho::orthoToTilePenguins ( void )
{
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr )
                continue;
            
            for ( Penguin &p : tile->predictions )
                tile->orthoToTileCoords ( p );
            
            for ( Penguin &p : tile->validations )
                tile->orthoToTileCoords ( p );
        }
    }
}

// Deletes duplicate Penguin predictions or validations from the entire ortho.
// Returns number of deleted Penguins.

int Ortho::deDuplicate ( bool predictions )
{
    int total = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr )
                continue;
            
            // For each predicted Penguin in this Tile...
            
            vector<Penguin> &penguins = predictions ? tile->predictions : tile->validations;
            auto p = penguins.begin();
            while ( p != penguins.end() )
            {
                // Does the Penguin have duplicates in this or adjacent tiles?
                
                vector<Penguin> duplicates;
                bool dup = p->hasDuplicates ( this, row, col, predictions, duplicates );

                // If so, delete this Penguin!
                
                if ( dup )
                {
                    p = penguins.erase ( p );
                    total++;
                    continue;
                }
                
                p++;
            }
        }
    }
    
    return total;
}

// Generate confusion matrix

int Ortho::confusionMatrix ( int &tp, int &tn, int &fp, int &fn )
{
    int total = 0;
    
    tp = tn = fp = fn = 0;
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr || tile->validated == false )
                continue;
            
            for ( Penguin &p : tile->predictions )
            {
                vector<Penguin> duplicates;
                if ( p.hasDuplicates ( this, row, col, false, duplicates ) )
                    tp++;
                else
                    fp++;
            }
            
            for ( Penguin &p : tile->validations )
            {
                vector<Penguin> duplicates;
                if ( ! p.hasDuplicates ( this, row, col, true, duplicates ) )
                    fn++;
            }

            if ( tile->validations.empty() && tile->predictions.empty() )
                tn++;
#if 0
            if ( tile->validations.empty() )
            {
                if ( tile->predictions.empty() )
                    tn++;
                else
                    fn++;
            }
#endif
            total++;
        }
    }
    
    return total;
}

int Ortho::classificationMatrix ( int counts[4][4] )
{
    int total = 0;
    
    for ( int row = 0; row < 4; row++ )
        for ( int col = 0; col < 4; col++ )
            counts[row][col] = 0;
    
    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr || tile->validated == false )
                continue;
            
            for ( Penguin &p : tile->predictions )
            {
                vector<Penguin> duplicates;
                if ( p.hasDuplicates ( this, row, col, false, duplicates ) )
                {
                    Penguin d = duplicates[0];
                    counts[ p.clas ][ d.clas ]++;
                }
            }
            
            total++;
        }
    }
    
    return total;
}

// Writes Penguin survey map to an image file at (path). Each Penguin is represented as a single pixel in the map.
// Adults are red, AdultStands are green, Chicks are blue. Pixels without Penguins are white.
// The output image size relative to the original ortho is (scale); for example 1.0/32.0 writes an image 1/32 the size of the ortho.
// If (predictions) is true, writes only predicted Penguins; if false, writes only validated Penguin labels.
// If (validatedTilesOnly) is true, writes Penguins only in human-validated tiles; implied true if predictions is false.

bool Ortho::writePenguinMap ( const string &path, float scale, bool predictions, bool validatedTilesOnly )
{
    int sizeY = ceil ( height * scale );
    int sizeX = ceil ( width * scale );
    
    cv::Mat map ( sizeY, sizeX, CV_8UC3 );
    map.setTo ( cv::Scalar ( 255, 255, 255 ) );

    for ( int row = 0; row < numTilesV; row++ )
    {
        for ( int col = 0; col < numTilesH; col++ )
        {
            Tile *tile = tiles[row][col];
            if ( tile == nullptr )
                continue;
            
            if ( validatedTilesOnly && ! tile->validated )
                continue;

            vector<Penguin> &penguins = predictions ? tile->predictions : tile->validations;
            for ( Penguin &p : penguins )
            {
                cv::Vec3b color ( 0, 0, 0 );    // format is B, G, R
                if ( p.clas == Penguin::kAdult )
                    color = cv::Vec3b ( 0, 0, 255 );    // Adults are Red
                else if ( p.clas == Penguin::kAdultStand )
                    color = cv::Vec3b ( 0, 255, 0 );    // AdultStands are Green
                else if ( p.clas == Penguin::kChick )
                    color = cv::Vec3b ( 255, 0, 0 );    // Chicks are Blue
                int px = p.cenx * scale, py = p.ceny * scale;
                map.at<cv::Vec3b> ( cv::Point ( px, py ) ) = color;
            }
        }
    }

    return cv::imwrite ( path.c_str(), map );
}

bool Ortho::downscaleOrtho ( const string &path, float scale, const string &outpath )
{
    TIFF *tiff = GOpenTIFFImage ( path.c_str() );
    if ( tiff == NULL )
        return false;

    int stripHeight = 1.0 / scale;
    GImagePtr image = GCreateImage ( width, stripHeight, 32 );
    if ( image == NULL )
        return NULL;
    
    int sizeY = ceil ( height * scale );
    int sizeX = ceil ( width * scale );
    cv::Mat map ( sizeY, sizeX, CV_8UC3 );

    for ( int row = 0; row < sizeY; row++ )
    {
        int stripTop = row * stripHeight;
        int stripBottom = min ( stripTop + stripHeight, height );
        int result = GReadTIFFImageStrip ( tiff, stripTop, stripBottom - stripTop, image, 0 );
        if ( result == 0 )
            break;
        
        for ( int col = 0; col < sizeX; col++ )
        {
            int cellLeft = col * stripHeight;
            int cellRight = min ( cellLeft + stripHeight, width );
            float rgba[4] = { 0 };
            
            GGetAverageColor ( image, cellLeft, 0, cellRight - cellLeft, stripBottom - stripTop, rgba );
            if ( rgba[2] != 255 || rgba[1] != 255 || rgba[0] != 255 )
                rgba[2] = rgba[2];
            
            cv::Vec3b color ( rgba[2], rgba[1], rgba[0] );
            map.at<cv::Vec3b> ( cv::Point ( col, row ) ) = color;
        }
        
        printf ( "Processed row %d of %d.\n", row, sizeY );
    }
    
    GDeleteImage ( image );
    TIFFClose ( tiff );

    return cv::imwrite ( outpath.c_str(), map );
}
