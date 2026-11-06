# Counting penguins: UAV imagery to calibrated colony counts

Code for an automated pipeline that estimates the size of Adélie penguin breeding colonies from uncrewed aerial vehicle (UAV) imagery, as applied to the colonies at Cape Crozier, Cape Bird, and Cape Royds, Ross Island, Antarctica, in 2018–2025. A YOLOv8 object detection model finds sitting adults on tiles cut from survey orthomosaics; detections are thresholded, de-duplicated, filtered spatially, and calibrated against manual counts of sampled grid cells to give candidate nest, occupied territory, total individual, and active nest estimates with 95% confidence intervals.

Developed by Point Blue Conservation Science.

## Citation

If you use this code, please cite:

Schmidt, A. E., D. Anderson, C. Burnham, M. Elrod, A. B. Fleishman, D. J. Klein, M. McKown, M. Meredyth-Young, E. Robinson, M. Schwager, K. Shah, and G. Ballard. 2026. Counting Penguins: pipeline code (version 1.0). Zenodo. https://doi.org/[Zenodo DOI]

The methods are described in:

Schmidt, A. E., D. Anderson, C. Burnham, M. Elrod, A. B. Fleishman, D. J. Klein, M. McKown, M. Meredyth-Young, E. Robinson, M. Schwager, K. Shah, and G. Ballard. Counting Penguins: a multi-UAV and deep learning pipeline for georeferenced whole-colony Adélie penguin breeding population counts. Submitted to Ecological Informatics.

Data (orthomosaics, tiles, training data, and the trained model): https://deju-penguinscience.s3.us-east-2.amazonaws.com/PenguinCounting/index.html

## Scripts

Scripts are listed in the order they are run. Steps 1 and 2 of the pipeline (survey planning and image acquisition) and orthomosaic processing are not covered by this code.

| Pipeline step | Script | Purpose |
| --- | --- | --- |
| 3. Image processing | `python_tiler.py` | Cut each orthomosaic into overlapping 512 x 256 pixel JPEG tiles, with a georeference table, orthomosaic metadata, and a tile footprint shapefile |
| 4. Deep learning model | `yolo_dataset_splitter.R` | Split annotated tiles 70/15/15 into training, validation, and test sets |
| | `yolo_file_organizer.R` | Copy tiles and labels into the folder structure YOLO expects |
| | `YOLOv8_Training_Launcher.py`, `penguin.yaml` | Train the detection model (configuration of the deployed model, ADPE_20250804_adult_sit) |
| | `evaluate_test_set.py` | Evaluate the trained model on the held-out test set (precision, recall, mAP50, mAP50-95) |
| | `YOLOv8_Inference_Launcher.py` | Run the trained model on every tile of a survey (detections with confidence above 0.10 are kept) |
| 5. Confidence threshold | `get_validation_tiles_from_S3_stratified.R` | Draw a stratified sample of tiles with and without detections and stage them, with the predicted boxes, for expert review |
| | `validation_functions.R`, `calculate_validation_stats.R` | Compare detections with expert-reviewed labels on sampled tiles and select the threshold that maximizes F1 |
| 6. Spatial filtering | `consolidate_labels_remove_duplicates.R` | Apply the threshold, convert detections to map coordinates, remove duplicates from tile overlaps, and remove isolated detections |
| | `create_nesting_boundaries_clip.R` | Draft nesting-area boundary polygons from the filtered detections, for review in GIS |
| | `clip_detections_to_nesting_areas_batch.R` | Keep detections inside the reviewed boundaries (candidate nests) |
| 7. Calibration | `create_calibration_files_batch.R` | Lay a 10 m grid over the colony, sample 30 cells, and prepare layers for two observers |
| | `calibrate_counts.R` | Compute calibration ratios from the manual counts and the colony estimates, with uncertainty |
| Database archive | `create_archive_database.R`, `export_database_sql.R` | Copy the published tables to an archive database and export it as `data/UAVSurveys.sql` |

Each script begins with a header describing its inputs, outputs, and settings.

The analyses, tables, and figures in the paper that are not produced by the pipeline itself are reproduced by the scripts in `code/analysis_code/`, which has its own README mapping each script to the results it produces.

## Requirements

**Python 3.10 or later:** numpy, rasterio, fiona, shapely, Pillow, PyYAML, and ultralytics (the deployed model was trained and run with version 8.3.174). boto3 and the AWS command-line interface are needed only to read from and write to Amazon S3. Training and inference need a CUDA-capable graphics processing unit for practical run times.

**R:** sf (with GEOS 3.11 or later), dplyr, purrr, readr, stringr, tibble, glue, ggplot2, jsonlite, data.table, RANN, foreach, doParallel, terra, dbscan, RSQLite, fs, and aws.s3. `validation_functions.R` reads tile tables and orthomosaic headers from S3, so it also needs AWS credentials in the R session.

## Project layout

All scripts use paths relative to the project root, which should be the working directory. Scripts, both R and Python, are expected in `code/`.

```
code/                                 pipeline scripts
  analysis_code/                      scripts for the paper's analyses, tables, and figures
models/                               trained weights (downloaded; see below)
training_data/adult_20250804/         penguin.yaml; annotated tiles (images/, labels/) from the data repository
training_runs/ADPE_20250804_adult_sit/ args.yaml and results.csv from training the deployed model
data/
  UAVSurveys.sql                      the database, as SQL (see below)
  UAVSurveys.db                       SQLite database created from the SQL file
  CalibrationCountTracking.csv        observer initials and counting times
  <survey>/
    predict/                          tile georeference tables and orthomosaic metadata
      counts/<model>/labels/          detection label files from inference
      counts/<model>/csv/<ortho>/     combined and de-duplicated detections
      counts/<model>/GIS/<ortho>/     filtered detections, boundaries, candidate nests
    validate/                         threshold selection inputs and outputs
    calibration_counts_survey_names/  sampled cells and observer layers
figs/validation/                      threshold selection figures
```

**Naming.** A survey is named `<colony>_<species>_<YYYY-MM-DD>` with the date of its first day, e.g. `croz_adpe_2024-11-27`. Orthomosaic names extend the survey name with a projection code, and with a section name where a survey has several orthomosaics, e.g. `royd_adpe_2019-12-04_lcc169` or `bird_north_adpe_2025-12-01_lcc169`. In S3, files for a survey are under `<prefix>/<colony>_<YYYYmmdd>/`.

**Database.** The SQLite database `data/UAVSurveys.db` links the steps. The scripts read and write these tables:

| Table | Used for |
| --- | --- |
| `Surveys` | Survey IDs |
| `SurveyImagery` | Orthomosaics (`OrthomosaicName`, with `.tif`) belonging to each survey |
| `ModelPredictions` | One row per orthomosaic and model: selected threshold, F1, precision, recall, and the filtered detection count (`MaskedCleaned`) |
| `CalibratedCounts` | One row per orthomosaic and model: candidate nest total and all calibration results |
| `GroundCounts` | Ground counts of active nests, occupied territories, and total individuals by subcolony, used for the active nest estimate |

Rows in `Surveys`, `SurveyImagery`, and `ModelPredictions` for a new survey are created before threshold selection.

The database is provided as a SQL file, `data/UAVSurveys.sql`, containing these tables with the values used in the published analysis, along with the other tables the analysis drew on (such as `ManualCountsOccupied`, manual counts of occupied territories from the orthomosaics). The tables are limited to the three Ross Island colonies and the deployed model, and free-text notes and local file locations are not included. To create the database:

```
sqlite3 data/UAVSurveys.db < data/UAVSurveys.sql
```

or, in R, use `rebuild_from_sql()` in `export_database_sql.R`. The published file was made with `create_archive_database.R`, which copies the selected tables and columns from the working database, followed by `export_database_sql.R`.

## Running the pipeline

The steps below follow one survey. Several scripts process every survey in the database by default; each has a `surveys_to_run` setting to limit a run to selected surveys.

### Tile the orthomosaic

```
python code/python_tiler.py --s3-bucket <bucket> --s3-prefix PenguinCounting/<colony>_<YYYYmmdd>/ data/tiles
```

Tiles and their metadata are written to `data/tiles/<ortho>/` and uploaded to `<prefix>tiles/<ortho>/`. A local file or folder of orthomosaics can be given instead of S3 options.

**Hand-off:** copy `<ortho>_tilesGeorefTable.csv` and `<ortho>_OrthoInfo.csv` for each orthomosaic to `data/<survey>/predict/`.

### Train the model (once)

Annotated tiles and their YOLO label files go in `training_data/adult_20250804/images/` and `labels/`, with an empty label file for each tile without penguins. Then run `yolo_dataset_splitter.R`, `yolo_file_organizer.R`, and the training launcher, in that order:

```
python code/YOLOv8_Training_Launcher.py
```

To evaluate the trained model on the held-out test set, which was not used for training or for selecting the retained weights:

```
python code/evaluate_test_set.py --weights models/ADPE_20250804_adult_sit_best.pt
```

The trained model used for the published counts, `ADPE_20250804_adult_sit_best.pt` (MD5 056487524e3875e7c44105f5196224cd), is attached to the version 1.0 release of this repository and is available from the data repository. Place it in `models/`. `training_runs/ADPE_20250804_adult_sit/` holds the training configuration (`args.yaml`) and per-epoch metrics (`results.csv`) for this model; file paths in `args.yaml` refer to the training machine.

### Run inference

```
python code/YOLOv8_Inference_Launcher.py --weights <weights file> \
    --s3-bucket <bucket> --s3-prefix PenguinCounting/<colony>_<YYYYmmdd>/
```

Label files (one per tile with at least one detection) are written to `inference/predictions/<ortho>/<model>/labels/` and uploaded to `<prefix>results/<ortho>/labels/`. The launcher stops rather than add to existing output; use `--overwrite` to replace it.

**Hand-off:** copy the label files for all orthomosaics of the survey into `data/<survey>/predict/counts/<model>/labels/`.

### Select the confidence threshold

1. Run `get_validation_tiles_from_S3_stratified.R` for the survey. It draws a stratified random sample of tiles with and without model detections (75 and 125 by default) and copies each tile, with its predicted boxes, to `data/<survey>/validate/tiles/`. This is the procedure used for Cape Bird and Cape Royds in 2025; samples for the other published surveys were random samples of 200 (Cape Crozier) or 400 (Cape Bird and Cape Royds) tiles, in which tiles without detections have no label file.
2. Load the folder into [makesense.ai](https://www.makesense.ai), review every predicted box (delete false positives, add missed penguins), and export the result as CSV to `data/<survey>/validate/reviewed_<...>.csv`.
3. Set the colony, species, and date in `calculate_validation_stats.R` and run it.

Every sampled tile counts in the evaluation, including tiles without penguins, so predictions on those tiles are counted as false positives. The selected threshold, F1, precision, and recall are written to `ModelPredictions` for all orthomosaics of the survey; figures go to `figs/validation/`.

### Filter detections

1. Run `consolidate_labels_remove_duplicates.R` once per orthomosaic, setting `ortho_name_full`. It reads the threshold from the database and records the filtered count as `MaskedCleaned`. De-duplication runs in parallel batches; results can differ by a few detections with the number of cores (`cn`), which is recorded in the output file name.
2. Run `create_nesting_boundaries_clip.R`, then review and edit the draft boundaries in GIS. Existing boundary files are not overwritten unless `overwrite = TRUE`.
3. Run `clip_detections_to_nesting_areas_batch.R`. The candidate nest total for each orthomosaic is recorded in `CalibratedCounts`.

### Calibrate

1. Run `create_calibration_files_batch.R`. Surveys that already have sampled cells are skipped.
2. Two observers each count their assigned cells in GIS, digitizing candidate nests into `<survey>_candidate_nests_Observer_<n>.shp` (deleting the placeholder point first), then copying that layer to add standing birds on territories (`<survey>_occupied_territories_Observer_<n>.shp`) and all remaining individuals (`<survey>_total_individuals_Observer_<n>.shp`). Record observer initials and counting times in `data/CalibrationCountTracking.csv`, one row per survey with columns `SurveyId`, `Observer1`, `Observer2`, `Obs1TimeToComplete`, and `Obs2TimeToComplete`.
3. Run `calibrate_counts.R`. Results, including the adjusted candidate nest total, occupied territory and total individual estimates, active nest estimates, and their margins of error, are written to `CalibratedCounts`.

`calibrate_counts.R` checks that the saved model counts in the sampled cells match the current candidate nests. If the candidate nests have changed since the cells were sampled (for example after a threshold change), it stops; setting `refresh_snapshot = TRUE` updates the saved counts.

**Rerunning a survey.** After a change to a survey's threshold, rerun consolidation, clipping, and calibration in that order, with `refresh_snapshot = TRUE` for calibration. Existing reviewed boundaries and sampled cells are kept. Clipping updates only the candidate nest total, so calibration must be rerun after it.

## AI assistance

The code in this repository was developed with assistance from Claude (Anthropic), and `consolidate_labels_remove_duplicates.R` also with assistance from Gemini (Google). All code was reviewed and tested by the authors, and each script's header includes the same acknowledgement.

## License

The code in this repository is released under the MIT License (see `LICENSE`).

The detection model is trained and run with Ultralytics YOLOv8, which is distributed under the GNU Affero General Public License v3.0 (AGPL-3.0). The MIT License covers only the code written for this project. Use of Ultralytics, including the Python scripts that call it and the trained model weights (`ADPE_20250804_adult_sit_best.pt`), is subject to the Ultralytics license terms; see https://www.ultralytics.com/license.
