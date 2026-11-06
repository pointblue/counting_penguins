## Analysis code (`code/analysis_code/`)

The scripts in `code/analysis_code/` produce the figures, tables, and statistics reported in the manuscript that are not direct outputs of the survey-and-analysis pipeline (Table S3). They read the pipeline's outputs (the survey database, per-orthomosaic GIS layers, and prediction files) and write summary tables to `data/` and figures to `figs/` (JPG and PDF).

All scripts are run from the root of the R project, for example `source("code/analysis_code/create_table2_population_estimates.R")`. Each script sources `analysis_helpers.R`, which holds the shared configuration (database path, deployed model name `ADPE_20250804_adult_sit`, helicopter census file), the functions that combine a survey's orthomosaics into survey totals, and the figure styling. The scripts are independent of one another and can be run in any order. `summarize_threshold_performance.R` also uses the matching functions in `code/validation_functions.R`.

### Scripts and the results they produce

| Manuscript item | Script | Outputs |
|---|---|---|
| Methods, Step 4: training tiles, labeled individuals, train/validation/test split, and overlap between training and evaluation tiles; Section 3.2: test tiles without penguins | `summarize_training_data.R` | `data/training_label_summary.csv`, `data/tile_adjacency_assessment.csv` |
| Section 3.1: survey area, images, execution time, coverage efficiency, ground sample distance (from Table S2) | `summarize_field_survey_metrics.R` | `data/field_survey_metrics_summary.csv` |
| Section 3.3: selected confidence thresholds and F1 scores; Methods, Step 5: number of tiles reviewed; Table S4 | `summarize_threshold_performance.R` | `data/threshold_performance_by_survey.csv`, `data/threshold_performance_curves.csv` |
| Section 3.4: reduction from raw detections to candidate nests, 2025 surveys | `summarize_spatial_filtering.R` | `data/detection_attrition_2025.csv` |
| Section 3.5: detection correction and margins of error; Section 3.6: occupied-territory conversion and ratio of active nests to occupied territories | `summarize_calibration_ratios.R` | `data/calibration_ratios_by_survey.csv` |
| Table 2 | `create_table2_population_estimates.R` | `data/table2_population_estimates.csv` |
| Section 3.6: active nests vs. adjusted candidate nests, Cape Royds whole-colony manual count, helicopter census comparisons, directional agreement, and timing of paired surveys | `compare_census_units.R` | `data/census_unit_comparisons.csv`, `data/helicopter_comparison_by_survey.csv`, `data/helicopter_direction_by_interval.csv` |
| Figures 4, 5, and 6 | `plot_population_metrics.R` | `figs/fig4_uav_metrics_by_year`, `figs/fig5_royds_occupied_vs_manual`, `figs/fig6_uav_vs_helicopter_by_year` (`.jpg`, `.pdf`) |
| Section 3.7 and Abstract: decline, recovery, year-to-year change, and changes exceeding combined uncertainty; Discussion 4.2: Cape Crozier changes | `summarize_interannual_variability.R` | `data/population_summary_by_colony.csv`, `data/year_to_year_change.csv` |
| Section 3.8: subcolonies, nearest-neighbor spacing, isolation-filter check; Discussion 4.3: change in spacing and nest density at Cape Crozier | `summarize_colony_spatial_structure.R` | `data/colony_spatial_structure.csv`, `data/isolation_filter_sensitivity.csv` |

### Inputs

- `data/UAVSurveys.db`: survey database written by the pipeline (tables `ModelPredictions`, `CalibratedCounts`, `ManualCountsOccupied`).
- `data/ross_sea_adelie_penguin_census_record_1981_2025.csv`: helicopter census of Adélie penguin breeding pairs by colony section and season, 1981–2025, from Antarctica New Zealand and Manaaki Whenua – Landcare Research (https://doi.org/10.7931/kf06-x745), redistributed here under its CC BY-NC 4.0 license. The dataset behind this DOI is updated as new seasons are added and earlier counts are corrected; the file included here is the version used for the manuscript, downloaded on [date].
- `data/survey_dates.csv`: UAV and helicopter survey dates (Table 1).
- `data/table_s2_survey_metrics.csv`: per-survey UAV deployment metrics (Table S2).
- `data/<survey>/`: per-survey pipeline outputs (prediction CSVs, YOLO label files, GIS layers, and the expert-reviewed threshold-selection tiles and labels).
- `data/training_data/adult_20250804/`: annotated training dataset and split lists.

### Results not produced by code

Figure 1 (map) was produced in QGIS; Figures 2 and 3 are diagrams and an annotated image. The year-to-year change in the historical helicopter census cited in Discussion Section 4.2 was calculated directly from the helicopter census file listed above. Survey effort in person-hours, the time to produce estimates after a survey, and the absence of duplicates in manual GIS checks come from field and processing records.

### Software

Scripts were developed in R 4.3 with dplyr, tidyr, ggplot2, readxl, DBI, RSQLite, sf, RANN, and data.table.
