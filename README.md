
<!-- README.md is generated from README.Rmd. Please edit that file -->

# penguin-counting-pipeline

[<img src="https://conservationmetrics.com/wp-content/uploads/conservation_metrics_350px-01.png" title="Conservation Metrics" width="350" />](https://www.conservationmetrics.com)[<img src="https://data.pointblue.org/apps/assets/images/pb-logo-full.png" title="Point Blue" width="250" />](https://www.pointblue.org)

<!-- badges: start -->
<!-- badges: end -->

The goal of penguin-counting-pipeline is to house the code for NSF project
1834986, which runs YOLOv5 object detection models to detect 3 classes of
Adele Penguin at colonies in Antarctica. This repo is self-contained and
includes a test image, python code for tiling the image and calculating some 
information about the tiles, the models, ways to validate the models, 
and the code to filter and save predictions as shapefiles for further analysis.
For brief instructions on how to train [see here](training_instuctions.md)

This project is an effort led by [Point Blue
Conservation Science](https://www.pointblue.org "PointBlue") with help from [Conservation
Metrics](https://www.conservationmetrics.com "CMI") and Stanford University.

### Requirements:

-   RStudio (Version &gt;=1.4.1106)
-   Python (Version &gt;=3.10)
-   \~600 mb free harddrive space

Tested on Windows 10, Windows Server 2019, Ubuntu

### To get started:

-   Clone this repository somewhere you would like it to live
-   Run the R notebook `cmi-penguin-pipeline.Rmd` in the newest version
    of RStudio (Version &gt;=1.4.1106)

We recommend using the `Projects` menu in RStudio to create a
`New Project` from `Version Control` using `git`. Paste
`https://github.com/ConservationMetrics/cmi-penguin-pipeline.git` for
the `url` (it should autofill the name) and choose a location on your
computer where you would like to store the repo (I store my git repos in
`D:/git_repos` as git and Dropbox, Google Drive, Box, etc. often do not
get along).

Alternatively you can run the following on the command line:

    cd some/folder/where/you/want/to/clone
    git clone https://github.com/ConservationMetrics/cmi-penguin-pipeline.git

The notebook `cmi-penguin-pipeline.Rmd` is setup to run both `R` and
`python` code chunks from within `RStudio` using the `retriculated`
package. We are using `miniconda` + `conda` environment to avoid
changing anything about your base `python` installation. Everything
about the environment is configured from within the notebook.

### Have questions or a problem?

If you have questions or run into a problem running this notebook,
please open an issue on Github
[here](https://github.com/ConservationMetrics/cmi-penguin-pipeline/issues).
