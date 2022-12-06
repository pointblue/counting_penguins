//
//  main.cpp
//  PenguinCounter
//
//  Created by Tim DeBenedictis on 12/5/22.
//

#include <iostream>
#include "PenguinCounter.hpp"

int main(int argc, const char * argv[])
{
    Ortho ortho;
    
    int maxTiles = ortho.allocateTiles ( 182789, 171319, 512, 256, 20, 20 );  // croz_2020-11-29
    //int maxTiles = ortho.allocateTiles ( 185998, 178549, 512, 256, 20, 20 );  // croz_2021-11-27
    cout << "Allocated storage for " << maxTiles << " tiles in " << ortho.numTilesH << " rows x " << ortho.numTilesV << " cols.\n";
    
    int numTiles = ortho.readTileIndex ( "/Users/timmyd/Projects/PointBlue/tiles/croz_2020-11-29/croz_2020-11-29_all_col_tilesGeorefTable.csv" );
    //int numTiles = ortho.readTileIndex ( "/Users/timmyd/Projects/PointBlue/tiles/croz_2021-11-27/croz_20211127_tilesGeorefTable.csv" );
    cout << "Read tile index with " << numTiles << " entries.\n";

    int numAdults = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/adult_s2_best/labels", kAdult );
    //int numAdults = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2021-11-27/adult_s2_best/labels", kAdult );
    cout << "Found " << numAdults << " adult predictions.\n";
    
    int numAdultStands = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/adult_stand_s5_best/labels", kAdult );
    //int numAdultStands = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2021-11-27/adult_stand_s5_best/labels", kAdult );
    cout << "Found " << numAdultStands << " adult stand predictions.\n";

    int numChicks = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/chick_s_best/labels", kAdult );
    // int numChicks = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2021-11-27/chick_s_best/labels", kAdult );
    cout << "Found " << numChicks << " chick predictions.\n";

    return 0;
}
