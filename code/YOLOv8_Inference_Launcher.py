# ----------------------------------------------------------------------------
# YOLOv8_Inference_Launcher.py
# Runs a trained YOLOv8 detection model on the image tiles produced by
# python_tiler.py and writes one YOLO-format label file per tile with at
# least one detection. Tiles with no detections have no label file.
#
# Each label line is: class x_center y_center width height confidence,
# with coordinates normalized to the dimensions of that tile. Edge tiles
# can be smaller than the nominal tile size, so converting detections to
# orthomosaic coordinates must use each tile's actual dimensions.
#
# Detections are retained down to a low confidence threshold (default
# 0.10) so that a survey-specific threshold can be chosen later; the
# optimized threshold cannot be lower than the value used here.
#
# Input is either a local directory of tile sets (one subdirectory per
# orthomosaic, as written by python_tiler.py) or tile sets stored in
# Amazon S3 under s3://<bucket>/<prefix>tiles/<ortho_name>/. In S3 mode,
# tiles are copied to the local work directory with the AWS command-line
# interface (aws s3 sync), and labels are uploaded to
# s3://<bucket>/<prefix>results/<ortho_name>/labels/.
#
# Ultralytics appends to existing label files rather than replacing them,
# so rerunning into an existing output directory would duplicate every
# detection. The script therefore stops if output for an orthomosaic
# already exists, locally or in S3, unless --overwrite is given, in which
# case existing output is deleted first.
#
# Each run appends a summary row per orthomosaic to
# <work_dir>/inference_log.csv (tile and detection counts, settings, and
# processing time).
#
# Requirements: Python 3.10+, ultralytics; boto3 and the AWS CLI for S3
# mode. Paths are relative to the working directory.
#
# Examples:
#   python code/YOLOv8_Inference_Launcher.py \
#       --weights models/ADPE_20250804_adult_sit_best.pt \
#       --tiles-dir data/tiles
#   python code/YOLOv8_Inference_Launcher.py \
#       --weights models/ADPE_20250804_adult_sit_best.pt \
#       --s3-bucket deju-penguinscience --s3-prefix PenguinCounting/bird_20251201/
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# ----------------------------------------------------------------------------

import argparse
import csv
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path

import ultralytics
from ultralytics import YOLO

# ----------------------------------------------------------------------------
# Default parameters (values used for the Ross Island Adélie penguin surveys)
# ----------------------------------------------------------------------------
IMAGE_SIZE = 512
CONF_THRESHOLD = 0.10
BATCH_SIZE = 32
WORK_DIR = "inference"

LOG_FIELDS = ["timestamp", "ortho_name", "model_name", "n_tiles",
              "n_label_files", "n_detections", "max_per_tile", "conf",
              "imgsz", "half", "seconds", "seconds_per_tile",
              "ultralytics_version"]


# ----------------------------------------------------------------------------
# Amazon S3 helpers (boto3 is imported only when S3 mode is used)
# ----------------------------------------------------------------------------
def list_s3_tilesets(s3, bucket, prefix):
    """Return the orthomosaic names that have tile folders under
    <prefix>tiles/. The paginator retrieves every page of results."""
    names = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=f"{prefix}tiles/",
                                   Delimiter="/"):
        for p in page.get("CommonPrefixes", []):
            names.append(p["Prefix"].rstrip("/").split("/")[-1])
    return sorted(names)


def s3_prefix_has_objects(s3, bucket, key_prefix):
    resp = s3.list_objects_v2(Bucket=bucket, Prefix=key_prefix, MaxKeys=1)
    return resp.get("KeyCount", 0) > 0


def aws_sync(src, dest, *extra):
    """Run aws s3 sync; --delete makes the destination mirror the source."""
    subprocess.run(["aws", "s3", "sync", src, dest, "--delete",
                    "--only-show-errors", *extra], check=True)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
def expected_tile_count(tiles_dir, ortho_name):
    """Number of tiles listed in the tiler's georeference table, or None
    if the table is not present."""
    table = tiles_dir / f"{ortho_name}_tilesGeorefTable.csv"
    if not table.is_file():
        return None
    with open(table, newline="") as f:
        return sum(1 for _ in f) - 1


def summarize_labels(label_dir):
    """Return (number of label files, total detections, max per tile)."""
    files = list(label_dir.glob("*.txt")) if label_dir.is_dir() else []
    counts = [sum(1 for line in open(f) if line.strip()) for f in files]
    return len(files), sum(counts), max(counts, default=0)


def append_log(log_path, row):
    new = not log_path.is_file()
    with open(log_path, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=LOG_FIELDS)
        if new:
            writer.writeheader()
        writer.writerow(row)


# ----------------------------------------------------------------------------
# Inference for one tile set
# ----------------------------------------------------------------------------
def run_tileset(model, model_name, ortho_name, tiles_dir, out_dir, args):
    """Run inference on one tile set; return the log row and label dir."""
    tiles = sorted(p for p in tiles_dir.iterdir()
                   if p.suffix.lower() in (".jpg", ".jpeg"))
    if not tiles:
        raise FileNotFoundError(f"No tiles found in {tiles_dir}")

    # Guard against leftover or missing tiles from an earlier tiling run
    expected = expected_tile_count(tiles_dir, ortho_name)
    if expected is not None and expected != len(tiles):
        raise ValueError(f"{ortho_name}: {len(tiles)} tiles found but the "
                         f"georeference table lists {expected}.")

    label_dir = out_dir / ortho_name / model_name / "labels"
    start = time.time()
    results = model.predict(
        source=str(tiles_dir),
        imgsz=args.imgsz,
        conf=args.conf,
        batch=args.batch,
        half=args.half,
        device=args.device,
        stream=True,          # process results one at a time to limit memory
        save=False,           # do not write annotated images
        save_txt=True,
        save_conf=True,
        project=str((out_dir / ortho_name).resolve()),
        name=model_name,
        exist_ok=True,        # existing output is cleared before this call
        verbose=False,
    )
    n_tiles = sum(1 for _ in results)   # iterating runs the predictions
    seconds = time.time() - start

    n_files, n_det, max_tile = summarize_labels(label_dir)
    if max_tile >= model.overrides.get("max_det", 300):
        print(f"  Warning: a tile reached the per-image detection limit.")

    row = dict(timestamp=datetime.now().isoformat(timespec="seconds"),
               ortho_name=ortho_name, model_name=model_name,
               n_tiles=n_tiles, n_label_files=n_files, n_detections=n_det,
               max_per_tile=max_tile, conf=args.conf, imgsz=args.imgsz,
               half=args.half, seconds=round(seconds, 1),
               seconds_per_tile=round(seconds / n_tiles, 4),
               ultralytics_version=ultralytics.__version__)
    print(f"  {n_tiles} tiles, {n_det} detections in {n_files} label files, "
          f"{seconds:.0f} s ({row['seconds_per_tile']} s per tile)")
    return row, label_dir


# ----------------------------------------------------------------------------
# Command-line interface
# ----------------------------------------------------------------------------
def parse_args():
    p = argparse.ArgumentParser(
        description="Run YOLOv8 inference on orthomosaic tile sets.")
    p.add_argument("--weights", required=True,
                   help="Trained model weights file (.pt).")
    p.add_argument("--model-name",
                   help="Name used for output folders; defaults to the "
                        "weights file name without a trailing '_best'.")
    p.add_argument("--tiles-dir",
                   help="Local directory containing one tile folder per "
                        "orthomosaic.")
    p.add_argument("--s3-bucket", help="Read tiles from and write labels "
                                       "to this S3 bucket.")
    p.add_argument("--s3-prefix", default="",
                   help="Survey prefix ending in '/', e.g. "
                        "PenguinCounting/bird_20251201/.")
    p.add_argument("--orthos", nargs="+",
                   help="Orthomosaic names to process; default is all tile "
                        "sets found.")
    p.add_argument("--work-dir", default=WORK_DIR,
                   help="Local directory for downloaded tiles, labels, and "
                        "the run log.")
    p.add_argument("--imgsz", type=int, default=IMAGE_SIZE)
    p.add_argument("--conf", type=float, default=CONF_THRESHOLD)
    p.add_argument("--batch", type=int, default=BATCH_SIZE)
    p.add_argument("--half", action="store_true",
                   help="Use half-precision (FP16) inference. Not used for "
                        "the published Ross Island counts.")
    p.add_argument("--device", default="0", help="GPU index or 'cpu'.")
    p.add_argument("--overwrite", action="store_true",
                   help="Delete existing output for each orthomosaic, "
                        "locally and in S3, before running.")
    args = p.parse_args()
    if (args.tiles_dir is None) == (args.s3_bucket is None):
        p.error("Provide either --tiles-dir or --s3-bucket, not both.")
    return args


def main():
    args = parse_args()
    work_dir = Path(args.work_dir)
    out_dir = work_dir / "predictions"
    out_dir.mkdir(parents=True, exist_ok=True)
    model_name = args.model_name or Path(args.weights).stem.removesuffix("_best")

    # Orthomosaics to process: those named with --orthos, or every tile
    # set found in S3 or in the local tiles directory
    s3 = None
    if args.s3_bucket:
        import boto3
        s3 = boto3.client("s3")
        orthos = args.orthos or list_s3_tilesets(s3, args.s3_bucket,
                                                 args.s3_prefix)
    else:
        tiles_root = Path(args.tiles_dir)
        orthos = args.orthos or sorted(d.name for d in tiles_root.iterdir()
                                       if d.is_dir())
    if not orthos:
        raise SystemExit("No tile sets found.")

    # Check for existing output before any processing starts
    for ortho in orthos:
        local_out = out_dir / ortho / model_name
        s3_out = f"{args.s3_prefix}results/{ortho}/labels/"
        exists_local = local_out.exists() and any(local_out.rglob("*.txt"))
        exists_s3 = s3 is not None and s3_prefix_has_objects(
            s3, args.s3_bucket, s3_out)
        if (exists_local or exists_s3) and not args.overwrite:
            raise SystemExit(
                f"Output already exists for {ortho} "
                f"({'local' if exists_local else 's3://' + args.s3_bucket + '/' + s3_out}). "
                "Use --overwrite to replace it.")
        if exists_local:
            shutil.rmtree(local_out)

    print(f"Ultralytics {ultralytics.__version__}; model {model_name}; "
          f"{len(orthos)} tile set(s)")
    model = YOLO(args.weights)
    log_path = work_dir / "inference_log.csv"
    overall_start = time.time()

    for ortho in orthos:
        print(f"\n{ortho}")
        if s3 is not None:
            tiles_dir = work_dir / "tiles" / ortho
            tiles_dir.mkdir(parents=True, exist_ok=True)
            print("  Syncing tiles from S3")
            aws_sync(f"s3://{args.s3_bucket}/{args.s3_prefix}tiles/{ortho}/",
                     str(tiles_dir), "--exclude", "*", "--include", "*.jpg",
                     "--include", "*_tilesGeorefTable.csv")
        else:
            tiles_dir = tiles_root / ortho

        row, label_dir = run_tileset(model, model_name, ortho, tiles_dir,
                                     out_dir, args)
        append_log(log_path, row)

        if s3 is not None:
            dest = f"s3://{args.s3_bucket}/{args.s3_prefix}results/{ortho}/labels/"
            label_dir.mkdir(parents=True, exist_ok=True)
            aws_sync(str(label_dir), dest)
            print(f"  Labels uploaded to {dest}")

    print(f"\nAll tile sets complete in "
          f"{(time.time() - overall_start) / 60:.1f} min. "
          f"Run log: {log_path}")


if __name__ == "__main__":
    main()
