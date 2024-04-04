# This python-based tiler is fast and works on very large TIF's, based on C++ approach from Timmy D
# Also works with tiffs that C++ doesn't seem to be able to handle (e.g., LZW output from metashape with tiles)
# GB + ChatGPT Jan 6, 2024

import os
import numpy as np
import rasterio
import csv
from PIL import Image

def get_tiles(ds, width=256, height=256, overlap=20):
    nols, nrows = ds.meta['width'], ds.meta['height']
    for col_off in range(0, nols, width - overlap):
        for row_off in range(0, nrows, height - overlap):
            # Adjust window width and height to not exceed image bounds
            window_width = min(width, nols - col_off)
            window_height = min(height, nrows - row_off)

            # No overlap for the first row and column
            if col_off == 0:
                window_width = width
            if row_off == 0:
                window_height = height

            window = rasterio.windows.Window(col_off=col_off, row_off=row_off, width=window_width, height=window_height)
            transform = rasterio.windows.transform(window, ds.transform)
            yield window, transform

def analyze_contrast(tile, threshold=10):
    """
    Analyze the contrast of the tile based on statistical measures for multi-band images.
    The threshold determines sensitivity to contrast variation.
    """
    low_contrast = True
    stats = []

    for band in tile:
        min_val = np.min(band)
        max_val = np.max(band)
        mean_val = np.mean(band)
        std_dev = np.std(band)

        stats.append((min_val, max_val, mean_val, std_dev))

        if std_dev >= threshold:
            low_contrast = False

    return low_contrast, stats

def calculate_georef(geotransform, col_off, row_off):
    """
    Calculate the georeferencing information for a tile.
    Note that the location of the values of interest may change with different versions of rasterio/GDAL?
    """
    easting = geotransform[2] + col_off * geotransform[0]
    northing = geotransform[5] + row_off * geotransform[4]

    # Debugging print statements
    # print(f"Geotransform: {geotransform}")
    # print(f"Column offset (col_off): {col_off}, Row offset (row_off): {row_off}")
    # print(f"Calculated Easting: {easting}, Northing: {northing}")

    return easting, northing

def aggregate_stats(tile):
    """
    Aggregate statistics across all bands.
    """
    min_val = np.min(tile)
    max_val = np.max(tile)
    mean_val = np.mean(tile)
    std_dev = np.std(tile)
    return min_val, max_val, mean_val, std_dev

def tile_large_geotiff(input_tiff, output_dir, tile_width, tile_height, contrast_threshold=5, overlap=20):
    with rasterio.open(input_tiff) as dataset:
        orthoname = os.path.splitext(os.path.basename(input_tiff))[0]

        csv_filename = os.path.join(output_dir, "GeorefTable.csv")
        with open(csv_filename, mode='w', newline='') as file:
            writer = csv.writer(file)
            writer.writerow(["tileName", "pixelX", "pixelY", "easting", "northing", "min", "max", "mean", "stdDev"])

            effective_tile_width = tile_width - overlap
            effective_tile_height = tile_height - overlap

            for window, transform in get_tiles(dataset, width=tile_width, height=tile_height, overlap=overlap):
                tile_x_index = window.col_off // effective_tile_width
                tile_y_index = window.row_off // effective_tile_height

                tile = dataset.read(window=window)

                low_contrast, _ = analyze_contrast(tile, threshold=contrast_threshold)
                if low_contrast:
                    # debug_print(f"low contrast: {window}")
                    continue

                tile_filename = f"{orthoname}_{tile_x_index}_{tile_y_index}.jpg"
                output_filepath = os.path.join(output_dir, tile_filename)

                print(tile_filename)

                # write the tile
                img = Image.fromarray(tile.transpose(1, 2, 0))
                if img.mode == 'RGBA':
                    img = img.convert('RGB')
                img.save(output_filepath, format='JPEG')

                # get statistics for the tile
                min_val, max_val, mean_val, std_dev = aggregate_stats(tile)

                # Calculate easting and northing for the upper-left corner of the tile
                easting, northing = calculate_georef(dataset.transform, window.col_off, window.row_off)

                # write a row in the GeoRefTable for this tile
                writer.writerow([tile_filename, window.col_off, window.row_off, easting, northing, min_val, max_val, mean_val, std_dev])

# Example usage. Note that the output_dir has to exist for this to work (and the input_tiff, of course)
tile_large_geotiff("D:/PenguinCounting/royd_20191204/royd_adpe_2019-12-04_lcc169.tif", "D:/PenguinCounting/tiles/royd_20191204/royd_adpe_2019-12-04_lcc169/", 512, 256, contrast_threshold=1, overlap=20)
