//  main.cpp
//  PenguinCounter
//
//  Created by Tim DeBenedictis on 12/5/22.

#include <iostream>
#include "PenguinCounter.hpp"

#define kTileWidth 512
#define kTileHeight 256
#define kTileOverlap 20
#define kOutputScale (1.0/32.0)
#define kMinProbability 0.01

void print_usage_and_exit ( const char *exename, int exitcode )
{
    cout << "Usage: " << exename << " ortho index adults stands chicks validations val_map raw_pred_map ref_pred_map small_ortho\n";
    cout << "ortho: input path to full-size orthomosaic in GeoTIFF format" << endl;
    cout << "index: input path to tile index in CSV format" << endl;
    cout << "adults: input path to directory containing adult penguin predictions in TOLO .txt format" << endl;
    cout << "stands: input path to directory containing adult standing penguin predictions in TOLO .txt format" << endl;
    cout << "chicks: input path to directory containing penguin chick predictions in TOLO .txt format" << endl;
    cout << "validations: input path to directory containing human-validated labels in YOLO .txt format" << endl;
    cout << "val_map: output path to validations map image, or \"none\"" << endl;
    cout << "raw_pred_map: output path to raw predictions map image, or \"none\"" << endl;
    cout << "ref_pred_map: output path to refined predictions map image, or \"none\"" << endl;
    cout << "small_ortho: output path to small version of input orthomosaic, or \"none\"" << endl;

    exit ( exitcode );
}

int main(int argc, const char * argv[])
{
    Ortho ortho;
    bool success;
    
    // Parse command line arguments; print usage and exit if we don't have enough
    
    if ( argc < 11 )
        print_usage_and_exit ( argv[0], -1 );
    
    string orthoPath ( argv[1] );
    string indexPath ( argv[2] );
    string adultsPath ( argv[3] );
    string standsPath ( argv[4] );
    string chicksPath ( argv[5] );
    string validationsPath ( argv[6] );
    
    string outValidationaMapPath ( argv[7] );
    string outRawPredMapPath ( argv[8] );
    string outRefPredMapPath ( argv[9] );
    string outSmallOrthoPath ( argv[10] );

    // Read orthomosaic metadata (dimensions, geotransform, etc.) but don't read the whole ortho!
    
    success = ortho.readMetadata ( orthoPath );
    if ( success )
        cout << "Read metadata from " << orthoPath << "; width = " << ortho.width << "; height = " << ortho.height << endl;

    // Allocate storage for tiles and read tile index
    
    //int maxTiles = ortho.allocateTiles ( 182789, 171319, 512, 256, 20, 20 );  // croz_2020-11-29
    int maxTiles = ortho.allocateTiles ( ortho.width, ortho.height, kTileWidth, kTileHeight, kTileOverlap, kTileOverlap );  // croz_2021-11-27
    cout << "Allocated storage for " << maxTiles << " tiles in " << ortho.numTilesH << " rows x " << ortho.numTilesV << " cols.\n";

    //int numTiles = ortho.readTileIndex ( "/Users/timmyd/Projects/PointBlue/tiles/croz_2020-11-29/croz_2020-11-29_all_col_tilesGeorefTable.csv" );
    int numTiles = ortho.readTileIndex ( "/Users/timmyd/Projects/PointBlue/tiles/croz_2021-11-27/croz_20211127_tilesGeorefTable.csv" );
    cout << "Read tile index " << indexPath << " with " << numTiles << " entries.\n";

    // Read YOLO predictions of adult, adult-standing, and chick penguins.
    
    //int numAdults = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/adult_s2_best/labels", Penguin::kAdult );
    int numAdults = ortho.readPredictions ( adultsPath, Penguin::kAdult );
    cout << "Found " << numAdults << " adult predictions in " << adultsPath << endl;
    
    //int numAdultStands = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/adult_stand_s5_best/labels", Penguin::kAdultStand );
    int numAdultStands = ortho.readPredictions ( standsPath, Penguin::kAdultStand );
    cout << "Found " << numAdultStands << " adult stand predictions in " << standsPath << endl;

    //int numChicks = ortho.readPredictions ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/chick_s_best/labels", Penguin::kChick );
    int numChicks = ortho.readPredictions ( chicksPath, Penguin::kChick );
    cout << "Found " << numChicks << " chick predictions in " << chicksPath << endl;

    // Count tiles where YOLO found no penguins.
    
    int numEmpty = ortho.countEmptyTiles ( true );
    cout << "Found " << numEmpty << " tiles with no predictions.\n";
    cout << endl;

    // Read validation data.
    
    //int numValidations = ortho.readValidations ( "/Users/timmyd/Projects/PointBlue/counts/croz_2020-11-29/validation_data/croz_20201129_validation_labels.csv" );
    int numValidations = ortho.readValidations ( validationsPath );
    cout << "Read " << numValidations << " validation labels from " << validationsPath << endl;
    
    // Count validated adult, adult_stand, and chick labels in validated tiles
    
    int n = ortho.countValidatedTiles();
    cout << "Counted " << n << " tiles with validation labels.\n";
    n = ortho.countPenguins ( Penguin::kAdult, false );
    cout << "Counted " << n << " adult validation labels.\n";
    n = ortho.countPenguins ( Penguin::kAdultStand, false );
    cout << "Counted " << n << " adult stand validation labels.\n";
    n = ortho.countPenguins ( Penguin::kChick, false );
    cout << "Counted " << n << " chick validation labels.\n";
    n = ortho.countEmptyTiles ( false, true );
    cout << "Counted " << n << " validated tiles with no validation labels.\n"<< endl;
    
    // Count predictions of adult, adult stand, and check penguins in validated tiles
    
    n = ortho.countPenguins ( Penguin::kAdult, true, true );
    cout << "Counted " << n << " adult predictions in validated tiles.\n";
    n = ortho.countPenguins ( Penguin::kAdultStand, true, true );
    cout << "Counted " << n << " adult stand predictions in validated tiles.\n";
    n = ortho.countPenguins ( Penguin::kChick, true, true );
    cout << "Counted " << n << " chick predictions in validated tiles.\n";
    n = ortho.countEmptyTiles ( true, true );
    cout << "Counted " << n << " validated tiles with no predictions.\n" << endl;

    // Convert all penguin positions from tile (local) to ortho (global) coordinates.
    // Write output maps of validation labels and raw predictions.
    
    ortho.tileToOrthoPenguins();

    if ( outValidationaMapPath != "none" )
    {
        success = ortho.writePenguinMap ( outValidationaMapPath, kOutputScale, false, false );
        if ( success )
            cout << "Wrote validations map " << outValidationaMapPath << endl;
        else
            cout << "Failed to write validations map " << outValidationaMapPath << endl;
    }
    
    if ( outRawPredMapPath != "none" )
    {
        success = ortho.writePenguinMap ( outRawPredMapPath, kOutputScale, true, false );
        if ( success )
            cout << "Wrote raw predictions map " << outRawPredMapPath << endl;
        else
            cout << "Failed to write raw predictions map " << outRawPredMapPath << endl;
    }
    
    // Get statistics on the positions and sizes of adult penguins predicted by YOLO.
    
    Penguin min, max, mean, stdev;
    n = ortho.getPenguinStats ( Penguin::kAdult, true, min, max, mean, stdev );
    printf ( "Predicted Adult Min sizex=%.3f sizey=%.3f\n", min.sizex, min.sizey );
    printf ( "Predicted Adult Max sizex=%.3f sizey=%.3f\n", max.sizex, max.sizey );
    printf ( "Predicted Adult Mean sizex=%.3f sizey=%.3f\n", mean.sizex, mean.sizey );
    printf ( "Predicted Adult Stdv sizex=%.3f sizey=%.3f\n", stdev.sizex, stdev.sizey );
    //n = ortho.deleteOutsizedPenguins ( Penguin::kAdult, mean.sizex - stdev.sizex, mean.sizex + stdev.sizex, mean.sizey - stdev.sizey, mean.sizey + stdev.sizey );
    //printf ( "Deleted %d Adult penguins.\n", n );

    // Get statistics on the positions and sizes of adult standing penguins predicted by YOLO.

    n = ortho.getPenguinStats ( Penguin::kAdultStand, true, min, max, mean, stdev );
    printf ( "Predicted Adult Stand Min sizex=%.3f sizey=%.3f\n", min.sizex, min.sizey );
    printf ( "Predicted Adult Stand Max sizex=%.3f sizey=%.3f\n", max.sizex, max.sizey );
    printf ( "Predicted Adult Stand Mean sizex=%.3f sizey=%.3f\n", mean.sizex, mean.sizey );
    printf ( "Predicted Adult Stand Stdv sizex=%.3f sizey=%.3f\n", stdev.sizex, stdev.sizey );
    //n = ortho.deleteOutsizedPenguins ( Penguin::kAdultStand, mean.sizex - stdev.sizex, mean.sizex + stdev.sizex, mean.sizey - stdev.sizey, mean.sizey + stdev.sizey );
    //printf ( "Deleted %d Adult Stand penguins.\n", n );

    // Get statistics on the positions and sizes of penguin chicks predicted by YOLO.

    n = ortho.getPenguinStats ( Penguin::kChick, true, min, max, mean, stdev );
    printf ( "Predicted Chick Min sizex=%.3f sizey=%.3f\n", min.sizex, min.sizey );
    printf ( "Predicted Chick Max sizex=%.3f sizey=%.3f\n", max.sizex, max.sizey );
    printf ( "Predicted Chick Mean sizex=%.3f sizey=%.3f\n", mean.sizex, mean.sizey );
    printf ( "Predicted Chick Stdv sizex=%.3f sizey=%.3f\n", stdev.sizex, stdev.sizey );
    //n = ortho.deleteOutsizedPenguins ( Penguin::kChick, mean.sizex - stdev.sizex, mean.sizex + stdev.sizex, mean.sizey - stdev.sizey, mean.sizey + stdev.sizey );
    //printf ( "Deleted %d Chick penguins.\n", n );

    // Get statistics on the positions and sizes of human-validated adult penguin labels.
    // Delete adult penguin predictions larger or smaller than the largest/smallest validated adult penguin labels.

    n = ortho.getPenguinStats ( Penguin::kAdult, false, min, max, mean, stdev );
    printf ( "Validated Adult Min sizex=%.3f sizey=%.3f\n", min.sizex, min.sizey );
    printf ( "Validated Adult Max sizex=%.3f sizey=%.3f\n", max.sizex, max.sizey );
    printf ( "Validated Adult Mean sizex=%.3f sizey=%.3f\n", mean.sizex, mean.sizey );
    printf ( "Validated Adult Stdv sizex=%.3f sizey=%.3f\n", stdev.sizex, stdev.sizey );
    n = ortho.deleteOutsizedPenguins ( Penguin::kAdult, min.sizex, max.sizex, min.sizey, max.sizey );
    printf ( "Deleted %d outsized Adult penguins.\n", n );

    // Get statistics on the positions and sizes of human-validated adult standing penguin labels.
    // Delete adult standing penguin predictions larger or smaller than the largest/smallest validated adult-standing labels.

    n = ortho.getPenguinStats ( Penguin::kAdultStand, false, min, max, mean, stdev );
    printf ( "Validated Adult Stand Min sizex=%.3f sizey=%.3f\n", min.sizex, min.sizey );
    printf ( "Validated Adult Stand Max sizex=%.3f sizey=%.3f\n", max.sizex, max.sizey );
    printf ( "Validated Adult Stand Mean sizex=%.3f sizey=%.3f\n", mean.sizex, mean.sizey );
    printf ( "Validated Adult Stand Stdv sizex=%.3f sizey=%.3f\n", stdev.sizex, stdev.sizey );
    n = ortho.deleteOutsizedPenguins ( Penguin::kAdultStand, min.sizex, max.sizex, min.sizey, max.sizey );
    printf ( "Deleted %d outsized Adult Stand penguins.\n", n );

    // Get statistics on the positions and sizes of human-validated penguin chick labels.
    // Delete chick predictions larger or smaller than the largest/smallest validated chick labels.

    n = ortho.getPenguinStats ( Penguin::kChick, false, min, max, mean, stdev );
    printf ( "Validated Chick Min sizex=%.3f sizey=%.3f\n", min.sizex, min.sizey );
    printf ( "Validated Chick Max sizex=%.3f sizey=%.3f\n", max.sizex, max.sizey );
    printf ( "Validated Chick Mean sizex=%.3f sizey=%.3f\n", mean.sizex, mean.sizey );
    printf ( "Validated Chick Stdv sizex=%.3f sizey=%.3f\n", stdev.sizex, stdev.sizey );
    n = ortho.deleteOutsizedPenguins ( Penguin::kChick, min.sizex, max.sizex, min.sizey, max.sizey );
    printf ( "Deleted %d outsized Chick penguins.\n", n );
    
    // Delete penguin predictions with very low probabilities.
    // Delete penguin predictions duplicated across overlapping tile edges.
    // Delete validation labels duplicated across overlapping tile edges.

    n = ortho.deleteImprobablePenguins ( Penguin::kAny, kMinProbability );
    printf ( "Deleted %d improbable Penguin predictions.\n", n );
    n = ortho.deDuplicate ( true );
    printf ( "Deleted %d duplicate Penguin predictions.\n", n );
    n = ortho.deDuplicate ( false );
    printf ( "Deleted %d duplicate Penguin validation labels.\n", n );
    cout << endl;

    // Count predictions in validated tiles
    
    n = ortho.countPenguins ( Penguin::kAdult, true, true );
    cout << "Counted " << n << " adult predictions in validated tiles.\n";
    n = ortho.countPenguins ( Penguin::kAdultStand, true, true );
    cout << "Counted " << n << " adult stand predictions in validated tiles.\n";
    n = ortho.countPenguins ( Penguin::kChick, true, true );
    cout << "Counted " << n << " chick predictions in validated tiles.\n";
    n = ortho.countEmptyTiles ( true, true );
    cout << "Counted " << n << " validated tiles with no predictions.\n";
    cout << endl;
    
    // Count predictions in all tiles
    
    n = ortho.countPenguins ( Penguin::kAdult, true, false );
    cout << "Counted " << n << " adult predictions in all tiles.\n";
    n = ortho.countPenguins ( Penguin::kAdultStand, true, false );
    cout << "Counted " << n << " adult stand predictions in all tiles.\n";
    n = ortho.countPenguins ( Penguin::kChick, true, false );
    cout << "Counted " << n << " chick predictions in all tiles.\n";
    n = ortho.countEmptyTiles ( true, false );
    cout << "Counted " << n << " tiles with no predictions.\n" << endl;

    // Write refined (de-duplicated) penguin prediction map if desired
    
    if ( outRefPredMapPath != "none" )
    {
        success = ortho.writePenguinMap ( outRefPredMapPath, kOutputScale, true, false );
        if ( success )
            cout << "Wrote refined prediction map " << outRefPredMapPath << endl;
        else
            cout << "Failed to write refined prediction map " << outRefPredMapPath << endl;
        cout << endl;
    }
    
    // Generate confusion matrix

    int tp, fp, tn, fn;
    n = ortho.confusionMatrix ( tp, tn, fp, fn );
    printf ( "Confusion Matrix:\n");
    printf ( "TP %5d FP %5d\n", tp, fp );
    printf ( "TN %5d FN %5d\n", tn, fn );
    cout << endl;
    
    // Generate classification matrix
    
    int counts[4][4] = { 0 };
    ortho.classificationMatrix ( counts );
    printf ( "Classification Matrix:\n" );
    for ( int i = 0; i < 4; i++ )
    {
        for ( int j = 0; j < 4; j++ )
            printf ( "%5d ", counts[i][j] );
        printf ( "\n");
    }

    // If desired, write scaled-down (small) version of input orthomosaic
    
    if ( outSmallOrthoPath != "none" )
    {
        cout << "Generating small version of ortho " << orthoPath << endl;
        success = ortho.downscaleOrtho ( orthoPath, kOutputScale, outSmallOrthoPath );
        if ( success )
            cout << "Wrote small version of ortho " << outSmallOrthoPath << endl;
        else
            cout << "Failed to write small version of ortho " << outSmallOrthoPath << endl;
    }
    
    return 0;
}

