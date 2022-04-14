## Training

We used the Ultralytics' [YOLOv5](https://github.com/ultralytics/yolov5)
repo to train our penguin detection models. This repo has many built-in
image augmentation options. We tried training from scratch and by
starting with a model checkpoint pre-trained on the [MS
COCO](https://cocodataset.org/#home) dataset.

## Training Options

The final models were trained using a pre-trained model with the
[large](https://github.com/ultralytics/yolov5/blob/master/models/yolov5l.yaml)
model size for `150` epochs with a batch size of `16`. We used the
[default
hyperparameters](https://github.com/ultralytics/yolov5/blob/master/data/hyps/hyp.scratch.yaml).
and trained using the following command with each dataset:

```{sh}
python train.py --img-size 512 --batch 16 --epochs 150 --data '../datasets/PB2021_yolo_adult/data.yaml' --cfg ./models/PB2021_adult_yolov5l.yaml --weights yolov5l.pt --project runs/train/PB2021_yolo_adult_stand --name PB2021_yolo_adult_s --single-cls --rect --cache
```

### Data structure

The datasets are organized into image folders and labels folders.  For each image there is a label txt. The data.yaml dictates the paths to the images and labels as well as class map for the label files. The train_img.txt has the list of images in the training data. The val_img.txt has the list of images in the validation data. The test_img.txt has the list of images in the test data. For more information see [this guide](https://github.com/ultralytics/yolov5/wiki/Train-Custom-Data)

### Label Creation
To prepare the training data for YOLOv5 we had to translate the labels generated with VoTT and stored at CMI as `csv` tables into the format needed for YOLO. For each image in the training dataset, there must be a label file with the same relative path as that image file:
```
~/images/some/path/to/image1.jpg
~/labels/some/path/to/image1.txt
```
The label specifications are outlined [here](https://github.com/ultralytics/yolov5/wiki/Train-Custom-Data#2-create-labels)

In the future label file creation is completely dependent on the format and structure of the labels coming out of the labeling tools so there will be separate code needed depending on what software labels were generated in and the format they are exported to. 
