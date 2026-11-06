# ----------------------------------------------------------------------------
# python_tiler.py
#
# Cuts large georeferenced orthomosaics (GeoTIFF) into overlapping JPEG tiles
# for object detection, and writes the metadata needed to map detections on
# each tile back to geographic coordinates.
#
# For each orthomosaic, the script writes the following to
# <output_dir>/<ortho_name>/:
#   <ortho_name>_<x>_<y>.jpg         Image tiles; x and y are column and row
#                                    tile indices from the upper-left corner.
#   <ortho_name>_tilesGeorefTable.csv
#                                    One row per tile: pixel offset of the
#                                    tile's upper-left corner within the
#                                    orthomosaic, projected coordinates
#                                    (easting, northing) of that corner, and
#                                    pixel summary statistics.
#   <ortho_name>_OrthoInfo.csv       Coordinate reference system (WKT) and
#                                    pixel resolution of the orthomosaic.
#   <ortho_name>_tiles.shp (+ .shx, .dbf, .prj, .cpg)
#                                    Polygon footprint of each tile.
#
# Tiles are generated on a regular grid with a fixed step of (tile size minus
# overlap). Tiles along the right and bottom edges of the orthomosaic are
# truncated at the raster boundary rather than padded, so they can be smaller
# than the nominal tile size. Tiles in which the standard deviation of pixel
# values is below the contrast threshold in every band (chiefly no-data areas
# outside the orthomosaic footprint) are not written.
#
# Input can be a single GeoTIFF, a local directory of GeoTIFFs, or GeoTIFFs
# stored under a prefix in an Amazon S3 bucket. In S3 mode, each orthomosaic
# is downloaded, tiled locally, and the outputs are uploaded to
# s3://<bucket>/<prefix>tiles/<ortho_name>/.
#
# Requirements: Python 3.10+, numpy, rasterio, fiona, shapely, Pillow;
# boto3 for S3 mode only. Input orthomosaics must be 8-bit RGB or RGBA and in
# a projected coordinate reference system.
#
# Examples:
#   python code/python_tiler.py data/orthos/croz_adpe_2024-11-27.tif data/tiles
#   python code/python_tiler.py data/orthos data/tiles
#   python code/python_tiler.py --s3-bucket deju-penguinscience \
#       --s3-prefix PenguinCounting/croz_20241127/ data/tiles
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# Based on C code provided by Tim DeBenedictis
# ----------------------------------------------------------------------------

import argparse
import csv
import os
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

import fiona
import numpy as np
import rasterio
from PIL import Image
from rasterio.windows import Window
from rasterio.windows import bounds as window_bounds
from rasterio.windows import transform as window_transform
from shapely.geometry import box, mapping

# ----------------------------------------------------------------------------
# Default parameters (values used for the Ross Island Adélie penguin surveys)
# ----------------------------------------------------------------------------
TILE_WIDTH = 512
TILE_HEIGHT = 256
OVERLAP = 20
CONTRAST_THRESHOLD = 1.0
JPEG_QUALITY = 95
TIFF_EXTENSIONS = (".tif", ".tiff")

GEOREF_HEADER = ["tileName", "pixelX", "pixelY", "easting", "northing",
                 "min", "max", "mean", "stdDev"]
SHAPEFILE_EXTENSIONS = (".shp", ".shx", ".dbf", ".prj", ".cpg")


# ----------------------------------------------------------------------------
# Tiling helpers
# ----------------------------------------------------------------------------
def get_tiles(ds, width, height, overlap):
    """Yield (window, transform) for each tile on a regular overlapping grid.

    Windows step by (size - overlap) from the upper-left corner. Windows that
    reach the right or bottom raster edge are truncated to the raster extent.
    """
    ncols, nrows = ds.width, ds.height
    x_step = width - overlap
    y_step = height - overlap

    for col_off in range(0, ncols, x_step):
        for row_off in range(0, nrows, y_step):
            window = Window(col_off=col_off,
                            row_off=row_off,
                            width=min(width, ncols - col_off),
                            height=min(height, nrows - row_off))
            yield window, window_transform(window, ds.transform)


def is_low_contrast(tile, threshold):
    """Return True if the pixel standard deviation of every band is below
    the threshold. A tile is retained if any single band meets it."""
    if tile.size == 0:
        return True
    for band in tile:
        if np.std(band) >= threshold:
            return False
    return True


def tile_stats(tile):
    """Return min, max, mean, and standard deviation across all bands."""
    if tile.size == 0:
        return 0, 0, 0, 0
    return np.min(tile), np.max(tile), np.mean(tile), np.std(tile)


def check_input(ds, ortho_name):
    """Raise an informative error if the raster cannot be tiled as intended."""
    if ds.crs is None or not ds.crs.is_projected:
        raise ValueError(
            f"'{ortho_name}' is not in a projected coordinate reference "
            "system. Reproject it (e.g., to LCC or UTM) before tiling.")
    if ds.count not in (3, 4):
        raise ValueError(
            f"'{ortho_name}' has {ds.count} bands; expected 3 (RGB) or "
            "4 (RGBA).")
    if any(dt != "uint8" for dt in ds.dtypes):
        raise ValueError(
            f"'{ortho_name}' has data type {ds.dtypes[0]}; expected uint8 "
            "for JPEG output.")


# ----------------------------------------------------------------------------
# Main tiling function
# ----------------------------------------------------------------------------
def tile_geotiff(input_tiff, output_dir,
                 tile_width=TILE_WIDTH, tile_height=TILE_HEIGHT,
                 overlap=OVERLAP, contrast_threshold=CONTRAST_THRESHOLD,
                 jpeg_quality=JPEG_QUALITY):
    """Tile one orthomosaic and write tiles and metadata to
    <output_dir>/<ortho_name>/. Returns (tile_dir, n_written, n_skipped)."""
    if not (0 <= overlap < min(tile_width, tile_height)):
        raise ValueError("Overlap must be non-negative and smaller than "
                         "both tile dimensions.")

    ortho_name = os.path.splitext(os.path.basename(input_tiff))[0]
    tile_dir = os.path.join(output_dir, ortho_name)
    os.makedirs(tile_dir, exist_ok=True)

    with rasterio.open(input_tiff) as ds:
        check_input(ds, ortho_name)

        # Orthomosaic-level metadata: CRS and pixel resolution
        ortho_info_path = os.path.join(tile_dir, f"{ortho_name}_OrthoInfo.csv")
        with open(ortho_info_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["crs_r", "xres", "yres"])
            writer.writerow([ds.crs.to_wkt(), ds.transform.a,
                             abs(ds.transform.e)])

        georef_path = os.path.join(tile_dir,
                                   f"{ortho_name}_tilesGeorefTable.csv")
        shp_path = os.path.join(tile_dir, f"{ortho_name}_tiles.shp")
        shp_schema = {"geometry": "Polygon",
                      "properties": {"filename": "str"}}

        x_step = tile_width - overlap
        y_step = tile_height - overlap
        n_written = n_skipped = 0

        with open(georef_path, "w", newline="") as georef_file, \
                fiona.open(shp_path, "w", driver="ESRI Shapefile",
                           crs=ds.crs.to_wkt(), schema=shp_schema) as shp:
            georef = csv.writer(georef_file)
            georef.writerow(GEOREF_HEADER)

            for window, transform in get_tiles(ds, tile_width, tile_height,
                                               overlap):
                tile = ds.read(window=window)

                # Skip featureless tiles (no-data, open water, uniform snow)
                if is_low_contrast(tile, contrast_threshold):
                    n_skipped += 1
                    continue

                # Grid indices; offsets are exact multiples of the step size
                tile_x = window.col_off // x_step
                tile_y = window.row_off // y_step
                tile_name = f"{ortho_name}_{tile_x}_{tile_y}.jpg"

                # Write JPEG; reorder (bands, rows, cols) to (rows, cols, bands)
                # and drop the alpha band if present
                img = Image.fromarray(tile.transpose(1, 2, 0))
                if img.mode == "RGBA":
                    img = img.convert("RGB")
                img.save(os.path.join(tile_dir, tile_name), format="JPEG",
                         quality=jpeg_quality)

                # Georeference: projected coordinates of upper-left corner
                min_v, max_v, mean_v, std_v = tile_stats(tile)
                georef.writerow([tile_name, window.col_off, window.row_off,
                                 transform.c, transform.f,
                                 min_v, max_v, mean_v, std_v])

                # Tile footprint polygon
                footprint = box(*window_bounds(window, ds.transform))
                shp.write({"geometry": mapping(footprint),
                           "properties": {"filename": tile_name}})
                n_written += 1

    return tile_dir, n_written, n_skipped


# ----------------------------------------------------------------------------
# Amazon S3 helpers (boto3 is imported only when S3 mode is used)
# ----------------------------------------------------------------------------
def list_s3_orthos(s3_client, bucket, prefix):
    """List all GeoTIFF keys under a prefix, excluding existing tile output.
    The paginator retrieves every page, so listings over 1,000 objects are
    complete."""
    keys = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key.lower().endswith(TIFF_EXTENSIONS) and "/tiles/" not in key:
                keys.append(key)
    return keys


def upload_directory(s3_client, local_dir, bucket, dest_prefix, workers=16):
    """Upload every file in local_dir to s3://bucket/dest_prefix."""
    files = sorted(os.listdir(local_dir))

    def _upload(fname):
        s3_client.upload_file(os.path.join(local_dir, fname), bucket,
                              f"{dest_prefix}{fname}")

    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(_upload, files))
    return len(files)


# ----------------------------------------------------------------------------
# Command-line interface
# ----------------------------------------------------------------------------
def parse_args():
    p = argparse.ArgumentParser(
        description="Tile georeferenced orthomosaics into overlapping JPEGs "
                    "with georeferencing metadata.")
    p.add_argument("input", nargs="?",
                   help="GeoTIFF file or directory of GeoTIFFs (omit when "
                        "using --s3-bucket).")
    p.add_argument("output_dir",
                   help="Local directory for output; a subdirectory is "
                        "created for each orthomosaic.")
    p.add_argument("--tile-width", type=int, default=TILE_WIDTH)
    p.add_argument("--tile-height", type=int, default=TILE_HEIGHT)
    p.add_argument("--overlap", type=int, default=OVERLAP)
    p.add_argument("--contrast-threshold", type=float,
                   default=CONTRAST_THRESHOLD)
    p.add_argument("--jpeg-quality", type=int, default=JPEG_QUALITY)
    p.add_argument("--s3-bucket",
                   help="Read orthomosaics from this S3 bucket and upload "
                        "tiles back to it.")
    p.add_argument("--s3-prefix", default="",
                   help="S3 prefix containing the orthomosaics, ending in "
                        "'/'. Tiles are uploaded to <prefix>tiles/<ortho>/.")
    args = p.parse_args()
    if (args.input is None) == (args.s3_bucket is None):
        p.error("Provide either a local input path or --s3-bucket, not both.")
    return args


def main():
    args = parse_args()
    tile_opts = dict(tile_width=args.tile_width,
                     tile_height=args.tile_height,
                     overlap=args.overlap,
                     contrast_threshold=args.contrast_threshold,
                     jpeg_quality=args.jpeg_quality)
    failures = []
    os.makedirs(args.output_dir, exist_ok=True)

    if args.s3_bucket:
        # S3 mode: download each orthomosaic, tile locally, upload outputs
        import boto3
        s3 = boto3.client("s3")
        keys = list_s3_orthos(s3, args.s3_bucket, args.s3_prefix)
        print(f"Found {len(keys)} orthomosaic(s) under "
              f"s3://{args.s3_bucket}/{args.s3_prefix}")
        for key in keys:
            try:
                with tempfile.TemporaryDirectory(dir=args.output_dir) as tmp:
                    local_tiff = os.path.join(tmp, os.path.basename(key))
                    print(f"Downloading {key}")
                    s3.download_file(args.s3_bucket, key, local_tiff)
                    tile_dir, n_w, n_s = tile_geotiff(
                        local_tiff, args.output_dir, **tile_opts)
                ortho_name = os.path.basename(tile_dir)
                dest = f"{args.s3_prefix}tiles/{ortho_name}/"
                n_up = upload_directory(s3, tile_dir, args.s3_bucket, dest)
                print(f"{ortho_name}: {n_w} tiles written, {n_s} skipped; "
                      f"{n_up} files uploaded to s3://{args.s3_bucket}/{dest}")
            except Exception as e:
                failures.append((key, e))
                print(f"Error processing {key}: {e}", file=sys.stderr)
    else:
        # Local mode: a single file or every GeoTIFF in a directory
        if os.path.isdir(args.input):
            inputs = sorted(os.path.join(args.input, f)
                            for f in os.listdir(args.input)
                            if f.lower().endswith(TIFF_EXTENSIONS))
        else:
            inputs = [args.input]
        for tiff in inputs:
            try:
                tile_dir, n_w, n_s = tile_geotiff(tiff, args.output_dir,
                                                  **tile_opts)
                print(f"{os.path.basename(tile_dir)}: {n_w} tiles written, "
                      f"{n_s} skipped")
            except Exception as e:
                failures.append((tiff, e))
                print(f"Error processing {tiff}: {e}", file=sys.stderr)

    # Report failures and exit non-zero so batch runs do not fail silently
    if failures:
        print(f"\n{len(failures)} orthomosaic(s) failed:", file=sys.stderr)
        for path, e in failures:
            print(f"  {path}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
