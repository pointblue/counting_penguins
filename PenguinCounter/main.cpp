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
    
    //int maxTiles = ortho.allocateTiles ( 182789, 171319, 512, 256, 20, 20 );  // croz_2020-11-29
    int maxTiles = ortho.allocateTiles ( 185998, 178549, 512, 256, 20, 20 );  // croz_2021-11-27
    cout << "Allocated storage for " << maxTiles << " tiles in " << ortho.numTilesH << " rows x " << ortho.numTilesV << " cols.\n";
    
    //int numTiles = ortho.readTileIndex ( "/Users/timmyd/Projects/PointBlue/tiles/croz_2020-11-29/croz_2020-11-29_all_col_tilesGeorefTable.csv" );
    int numTiles = ortho.readTileIndex ( "/Users/timmyd/Projects/PointBlue/tiles/croz_2021-11-27/croz_20211127_tilesGeorefTable.csv" );
    cout << "Read tile index with " << numTiles << " entries.\n";

    //int numAdults = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/adult_s2_best/labels", Penguin::kAdult );
    int numAdults = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2021-11-27/adult_s2_best/labels", Penguin::kAdult );
    cout << "Found " << numAdults << " adult predictions.\n";
    
    //int numAdultStands = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/adult_stand_s5_best/labels", Penguin::kAdultStand );
    int numAdultStands = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2021-11-27/adult_stand_s5_best/labels", Penguin::kAdultStand );
    cout << "Found " << numAdultStands << " adult stand predictions.\n";

    //int numChicks = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/chick_s_best/labels", Penguin::kChick );
    int numChicks = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2021-11-27/chick_s_best/labels", Penguin::kChick );
    cout << "Found " << numChicks << " chick predictions.\n";

    //int numChicks = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/chick_s_best/labels", Penguin::kChick );
    int numEmpty = ortho.countEmptyTiles ( true );
    cout << "Found " << numEmpty << " tiles with no predictions.\n";

    // int numValidations = ortho.readValidations ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/validation_data/croz_20201129_validation_labels.csv" );
    int numValidations = ortho.readValidations ( "/Users/timmyd/Projects/PointBlue/counts/croz_2021-11-27/validation_data/croz_20211127_validation_labels.csv" );
    cout << "Read " << numValidations << " validation labels.\n";
    
    int n = ortho.countValidatedTiles();
    cout << "Counted " << n << " tiles with validation labels.\n";

    n = ortho.countPenguins ( Penguin::kAdult, false );
    cout << "Counted " << n << " adult validation labels.\n";
    
    n = ortho.countPenguins ( Penguin::kAdultStand, false );
    cout << "Counted " << n << " adult stand validation labels.\n";

    n = ortho.countPenguins ( Penguin::kChick, false );
    cout << "Counted " << n << " chick validation labels.\n";

    n = ortho.countEmptyTiles ( false );
    cout << "Counted " << n << " validated tiles with no validation labels.\n";

    n = ortho.countPenguins ( Penguin::kAdult, true, true );
    cout << "Counted " << n << " adult predictions in validated tiles.\n";
    
    n = ortho.countPenguins ( Penguin::kAdultStand, true, true );
    cout << "Counted " << n << " adult stand predictions in validated tiles.\n";

    n = ortho.countPenguins ( Penguin::kChick, true, true );
    cout << "Counted " << n << " chick predictions in validated tiles.\n";

    Penguin min, max, mean, stdev;
    n = ortho.getPenguinStats ( Penguin::kAdult, true, min, max, mean, stdev );
    printf ( "Predicted Adult Min n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, min.cenx, min.ceny, min.sizex, min.sizey );
    printf ( "Predicted Adult Max n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, max.cenx, max.ceny, max.sizex, max.sizey );
    printf ( "Predicted Adult Mean n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, mean.cenx, mean.ceny, mean.sizex, mean.sizey );
    printf ( "Predicted Adult Stdv n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, stdev.cenx, stdev.ceny, stdev.sizex, stdev.sizey );

    n = ortho.getPenguinStats ( Penguin::kAdultStand, true, min, max, mean, stdev );
    printf ( "Predicted Adult Stand Min n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, min.cenx, min.ceny, min.sizex, min.sizey );
    printf ( "Predicted Adult Stand Max n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, max.cenx, max.ceny, max.sizex, max.sizey );
    printf ( "Predicted Adult Stand Mean n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, mean.cenx, mean.ceny, mean.sizex, mean.sizey );
    printf ( "Predicted Adult Stand Stdv n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, stdev.cenx, stdev.ceny, stdev.sizex, stdev.sizey );

    n = ortho.getPenguinStats ( Penguin::kChick, true, min, max, mean, stdev );
    printf ( "Predicted Chick Min n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, min.cenx, min.ceny, min.sizex, min.sizey );
    printf ( "Predicted Chick Max n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, max.cenx, max.ceny, max.sizex, max.sizey );
    printf ( "Predicted Chick Mean n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, mean.cenx, mean.ceny, mean.sizex, mean.sizey );
    printf ( "Predicted Chick Stdv n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, stdev.cenx, stdev.ceny, stdev.sizex, stdev.sizey );

    n = ortho.getPenguinStats ( Penguin::kAdult, false, min, max, mean, stdev );
    printf ( "Validated Adult Min n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, min.cenx, min.ceny, min.sizex, min.sizey );
    printf ( "Validated Adult Max n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, max.cenx, max.ceny, max.sizex, max.sizey );
    printf ( "Validated Adult Mean n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, mean.cenx, mean.ceny, mean.sizex, mean.sizey );
    printf ( "Validated Adult Stdv n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, stdev.cenx, stdev.ceny, stdev.sizex, stdev.sizey );

    n = ortho.getPenguinStats ( Penguin::kAdultStand, false, min, max, mean, stdev );
    printf ( "Validated Adult Stand Min n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, min.cenx, min.ceny, min.sizex, min.sizey );
    printf ( "Validated Adult Stand Max n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, max.cenx, max.ceny, max.sizex, max.sizey );
    printf ( "Validated Adult Stand Mean n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, mean.cenx, mean.ceny, mean.sizex, mean.sizey );
    printf ( "Validated Adult Stand Stdv n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, stdev.cenx, stdev.ceny, stdev.sizex, stdev.sizey );

    n = ortho.getPenguinStats ( Penguin::kChick, false, min, max, mean, stdev );
    printf ( "Validated Chick Min n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, min.cenx, min.ceny, min.sizex, min.sizey );
    printf ( "Validated Chick Max n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, max.cenx, max.ceny, max.sizex, max.sizey );
    printf ( "Validated Chick Mean n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, mean.cenx, mean.ceny, mean.sizex, mean.sizey );
    printf ( "Validated Chick Stdv n=%d cenx=%.3f ceny=%.3f sizex=%.3f sizey=%.3f\n", n, stdev.cenx, stdev.ceny, stdev.sizex, stdev.sizey );

    return 0;
}
