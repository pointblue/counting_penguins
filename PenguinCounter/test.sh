#!/bin/bash

# This script tests the PenguinCounter (counter) executable.
# It assumes the orthomosiac, predictions, validation labels, etc. are
# actually present in the directories below!
# -Tim DeBenedictis (TDeBenedictis-RA@pointblue.org) 22 Feb 2023

./counter ../../orthos/croz_20211127.tif \
../../tiles/croz_20211127_tilesGeorefTable.csv \
../../counts/croz_2021-11-27/adult_s2_best/labels \
../../counts/croz_2021-11-27/adult_stand_s5_best/labels \
../../counts/croz_2021-11-27/chick_s_best/labels \
../../counts/croz_2021-11-27/validation_data/croz_20211127_validation_labels.csv \
../../counts/croz_2021-11-27/validations.png \
../../counts/croz_2021-11-27/predictions_raw.png \
../../counts/croz_2021-11-27/predictions_refined.png \
../../orthos/croz_20211127_small.jpg
