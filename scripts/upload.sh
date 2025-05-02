#!/bin/bash

# Destinatioon S3 bucket where we want to upload files
# Destination directory within bucket. Must end with a slash!

BUCKET=deju-penguinscience
DIR=PenguinCounting/croz_20201129/tiles/

# If no files specified on command line, upload all files in current directory

if [ $# -eq 0 ]; then
    echo "Uploading all files in current directory to s3://$BUCKET/$DIR"
    aws s3 sync . "s3://$BUCKET/$DIR" --acl bucket-owner-full-control
else
    echo "Uploading $# files to s3://$BUCKET/$DIR"
    FILES="$@"
    for FILE in $FILES
    do
        aws s3 cp "$FILE" "s3://$BUCKET/$DIR" --acl bucket-owner-full-control
    done
fi

