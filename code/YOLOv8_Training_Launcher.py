# --------------------------------------------------------------------
# YOLOv8_Training_Launcher.py
# Trains a YOLOv8 object detection model on the annotated penguin tiles
# prepared by yolo_dataset_splitter.R and yolo_file_organizer.R.
#
# Configuration values reproduce the training run for the deployed model
# ADPE_20250804_adult_sit (run name penguin_model_v8_g52): YOLOv8-Large
# initialized from COCO-pretrained weights (yolov8l.pt), 150 epochs,
# batch size 32, 512-pixel input. Rectangular 512 x 256 tiles are
# letterboxed (padded) to 512 x 512. Training hyperparameters not set
# below use Ultralytics defaults; the full set used for a run is written
# to <project>/<run_name>/args.yaml.
#
# Paths are relative to the repository root, which should be the working
# directory when the script is run. Requires the ultralytics package
# (the deployed model was trained with version 8.3.174) and a
# CUDA-capable GPU for practical training times. Run from the repository
# root: python code/YOLOv8_Training_Launcher.py
#
# Note on reproducibility: Ultralytics seeds its random number generators
# (seed = 0 by default), but some GPU operations are not deterministic, so
# a rerun will produce similar but not identical weights. The published
# weights file is the definitive record of the deployed model.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

from pathlib import Path

import ultralytics
import yaml
from ultralytics import YOLO

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
# Dataset definition file (see penguin.yaml)
DATA_YAML = "training_data/adult_20250804/penguin.yaml"

# Starting weights. "yolov8l.pt" downloads the COCO-pretrained YOLOv8-Large
# model. To train without pretrained weights, use "yolov8l.yaml" instead.
# To fine-tune an existing model, give the path to its weights file; this
# starts a new run with a new learning-rate schedule. To continue an
# interrupted run, use YOLO("<run>/weights/last.pt").train(resume=True).
START_WEIGHTS = "yolov8l.pt"

EPOCHS = 150
BATCH_SIZE = 32
IMAGE_SIZE = 512
DEVICE = 0          # GPU index, or "cpu"

# With optimizer = "auto", Ultralytics chooses the optimizer from the
# number of training iterations, ceil(n_train / max(batch, 64)) * epochs:
# AdamW (lr0 = 0.002 for one class, momentum 0.9) at 10,000 iterations or
# fewer, otherwise SGD (lr0 = 0.01, momentum 0.9). For 3,155 training
# tiles and 150 epochs (7,500 iterations) this selects AdamW. Changing
# EPOCHS or the training set size can therefore change the optimizer; set
# it explicitly if that is not intended.
OPTIMIZER = "auto"

# Output location: <PROJECT_DIR>/<RUN_NAME>. An existing run directory is
# not overwritten; Ultralytics appends a number to the run name instead.
PROJECT_DIR = "training_runs"
RUN_NAME = "penguin_model_v8_g52"


# --------------------------------------------------------------------
# Pre-flight check
# --------------------------------------------------------------------
def check_dataset(data_yaml):
    """Confirm that the image and label directories named in the dataset
    file exist, and report the number of images and labels in each."""
    data_yaml = Path(data_yaml)
    if not data_yaml.is_file():
        raise FileNotFoundError(f"Dataset file not found: {data_yaml}")
    with open(data_yaml) as f:
        cfg = yaml.safe_load(f)

    # Dataset root: 'path' if given, otherwise the folder holding the file
    root = Path(cfg["path"]) if cfg.get("path") else data_yaml.parent

    for split in ("train", "val", "test"):
        if split not in cfg:
            continue
        img_dir = root / cfg[split]
        lbl_dir = img_dir.parent / "labels"
        if not img_dir.is_dir() or not lbl_dir.is_dir():
            raise FileNotFoundError(
                f"{split}: expected {img_dir} and {lbl_dir}")
        n_img = sum(1 for p in img_dir.iterdir()
                    if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
        n_lbl = sum(1 for p in lbl_dir.iterdir() if p.suffix == ".txt")
        print(f"  {split:<5} {n_img} images, {n_lbl} labels ({img_dir})")
        if n_img != n_lbl:
            raise ValueError(f"{split}: image and label counts differ.")


# --------------------------------------------------------------------
# Training
# --------------------------------------------------------------------
def main():
    print(f"Ultralytics {ultralytics.__version__}")
    print(f"Dataset: {DATA_YAML}")
    check_dataset(DATA_YAML)
    print(f"Weights: {START_WEIGHTS}; epochs {EPOCHS}, batch {BATCH_SIZE}, "
          f"image size {IMAGE_SIZE}, optimizer {OPTIMIZER}")

    model = YOLO(START_WEIGHTS)
    model.train(
        data=str(Path(DATA_YAML).resolve()),
        epochs=EPOCHS,
        batch=BATCH_SIZE,
        imgsz=IMAGE_SIZE,
        optimizer=OPTIMIZER,
        device=DEVICE,
        project=str(Path(PROJECT_DIR).resolve()),
        name=RUN_NAME,
    )

    # best.pt is the epoch with the highest validation fitness
    # (0.1 * mAP50 + 0.9 * mAP50-95); per-epoch metrics are in results.csv
    print(f"Training complete. Results saved to {model.trainer.save_dir}")


if __name__ == "__main__":
    main()
