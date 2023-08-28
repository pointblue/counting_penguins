#!/bin/bash

# This script builds the PenguinCounter excutable (counter) on Ubuntu linux.
# Make sure it has execute permission (chmod +x build.sh) before running!
# -Tim DeBenedictis (TDeBenedictis-RA@pointblue.org) 22 Feb 2023

# First install preprequsisites
sudo apt install build-essential libjpeg-dev libtiff-dev libgdal-dev

# Now compile the source files, link libraries, and generate "counter" executable
gcc -o counter main.cpp PenguinCounter.cpp SSUtilities.cpp GImage.cpp -std=c++2a \
-I/usr/include \
-I/usr/include/gdal \
-I/usr/include/opencv4 \
-L/usr/lib \
-lstdc++ -lm -ltiff -ljpeg -lgdal -lopencv_core -lopencv_imgcodecs
