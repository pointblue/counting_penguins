#Plots labels on tiles for checking accuracy
#requires yolo-formatted bounding boxes with one txt file per tile (in a dir called "yolo_files")
#(run parse_json_labels_make_yolo.py to get those)
#and image directory with one URL per tile, with .txt and .jpg file names matching -
#these are downloaded to local directory called "img_files" (could skip saving them locally)
#update lines 68-71 to reflect your working setup
#11/10/2022 - Grant Ballard (gballard@pointblue.org)

import matplotlib.pyplot as plt
import matplotlib.image as mpimg
import matplotlib.colors as mcolors
import urllib.request
import os
import random

def visualize_bbox(img_file, yolo_ann_file, label_dict, figure_size=(6, 8)):
    """
    Plots bounding boxes on images

    Input:
    img_file : numpy.array
    yolo_ann_file: Text file containing annotations in YOLO format
    label_dict: Dictionary of image categories
    figure_size: Figure size
    """

    img = mpimg.imread(img_file)
    fig, ax = plt.subplots(1, 1, figsize=figure_size)
    ax.imshow(img)

    im_height, im_width, _ = img.shape

    palette = mcolors.TABLEAU_COLORS
    colors = [c for c in palette.keys()]
    with open(yolo_ann_file, "r") as fin:
        for line in fin:
            cat, center_w, center_h, width, height = line.split()
            cat = int(cat)
            category_name = label_dict[cat]
            left = (float(center_w) - float(width) / 2) * im_width
            top = (float(center_h) - float(height) / 2) * im_height
            width = float(width) * im_width
            height = float(height) * im_height

            rect = plt.Rectangle(
                (left, top),
                width,
                height,
                fill=False,
                linewidth=1.5,
                edgecolor=colors[cat],
            )
            ax.add_patch(rect)
            props = dict(boxstyle="round", facecolor=colors[cat], alpha=0.5)
            ax.text(
                left,
                top,
                category_name,
                fontsize=7,
                verticalalignment="top",
                bbox=props,
            )
    plt.show()


def main():
    """
    Plots bounding boxes
    """
    #user-specified stuff here:
    #labels = {0: "your_label", 1: "your_next_label", 2: "another_label"}
    #yolo_dir = "directory where you store yolo-formatted labels"
    #img_url_dir = "URL to tiles that have matching yolo labels"
    #img_file_dir = "local directory to put tiles (probably doesn't need to store them but...)"

    #example:
    labels = {0: "ADPE_a", 1: "ADPE_a_stand", 2: "no_ADPE"}
    yolo_dir = "C:/gballard/S031/analyses/counting_penguins/yolo_files/"
    img_url_dir = "https://deju-penguinscience.s3.us-east-2.amazonaws.com/PenguinCounting/croz_20211127/label_sample/"
    img_file_dir = "C:/gballard/S031/analyses/counting_penguins/img_files/"

    n = 0
    while n < 1:
        #to pick n random tiles from the list:
        #fntxt = random.choice(os.listdir(yolo_dir))
        #to pick a specific file (needs to be foud in yolo_dir):
        fntxt = "croz_20211127_328_693.txt"
        fn = fntxt.strip(".txt")
        print(fn)
        fnjpg = fn+".jpg"
        img_url = img_url_dir+fnjpg
        print(img_url)
        img_filename = img_file_dir+fnjpg
        urllib.request.urlretrieve(img_url, img_filename)
        ann_file = yolo_dir + fntxt
        visualize_bbox(img_filename, ann_file, labels, figure_size=(12, 8))
        n += 1

if __name__ == "__main__":
    main()