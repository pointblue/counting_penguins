#parses a json file from aws Ground Truth and creates a csv on your local computer

from io import StringIO
import json
import pandas as pd

def parse_gt_output(fin):
    """
    Captures the json Ground Truth bounding box annotations into a pandas dataframe

    Input:
    manifest_path: S3 path to the annotation file
    job_name: name of the Ground Truth job

    Returns:
    df_bbox: pandas dataframe with bounding box coordinates
             for each item in every image
    """
    with fin:
        annot_list = []
        for line in fin.readlines():
            record = json.loads(line)
            job_name = "adpe-label-test3"
            if job_name in record.keys():  # is it necessary?
                print("record: ", record)
                image_file_path = record["source-ref"]
                image_file_name = image_file_path.split("/")[-1]
                class_maps = record[f"{job_name}-metadata"]["class-map"]

                imsize_list = record[job_name]["image_size"]
                assert len(imsize_list) == 1
                image_width = imsize_list[0]["width"]
                image_height = imsize_list[0]["height"]

                for annot in record[job_name]["annotations"]:
                    left = annot["left"]
                    top = annot["top"]
                    height = annot["height"]
                    width = annot["width"]
                    class_name = class_maps[f'{annot["class_id"]}']

                    annot_list.append(
                        [
                            image_file_name,
                            class_name,
                            left,
                            top,
                            height,
                            width,
                            image_width,
                            image_height,
                        ]
                    )

    df_bbox = pd.DataFrame(
        annot_list,
        columns=[
            "img_file",
            "category",
            "box_left",
            "box_top",
            "box_height",
            "box_width",
            "img_width",
            "img_height",
        ],
    )
    df_bbox.to_csv("c:/gballard/s031/analyses/counting_penguins/scripts/output.csv", index=False)
    return df_bbox

def annot_yolo(annot_file, cats):
    """
    Prepares the annotation in YOLO format

    Input:
    annot_file: csv file containing Ground Truth annotations
    ordered_cats: List of object categories in proper order for model training

    Returns:
    df_ann: pandas dataframe with the following columns
            img_file int_category box_center_w box_center_h box_width box_height


    Note:
    YOLO data format: <object-class> <x_center> <y_center> <width> <height>
    """

    df_ann = pd.read_csv(annot_file)

    df_ann["int_category"] = df_ann["category"].apply(lambda x: cats.index(x))
    df_ann["box_center_w"] = df_ann["box_left"] + df_ann["box_width"] / 2
    df_ann["box_center_h"] = df_ann["box_top"] + df_ann["box_height"] / 2

    # scale box dimensions by image dimensions
    df_ann["box_center_w"] = df_ann["box_center_w"] / df_ann["img_width"]
    df_ann["box_center_h"] = df_ann["box_center_h"] / df_ann["img_height"]
    df_ann["box_width"] = df_ann["box_width"] / df_ann["img_width"]
    df_ann["box_height"] = df_ann["box_height"] / df_ann["img_height"]

    df_ann.to_csv("c:/gballard/s031/analyses/counting_penguins/scripts/yolo_output.csv", index=False)
    return df_ann

def save_annots_to_local(df_local):
    """
    For every image in the dataset, save a text file with annotation in YOLO format

    Input:
    df_local: pandas dataframe with the following columns
              img_file int_category box_center_w box_center_h box_width box_height
    """

    unique_images = df_local["img_file"].unique()

    for image_file in unique_images:
        df_single_img_annots = df_local.loc[df_local.img_file == image_file]
        annot_txt_file = "c:/gballard/s031/analyses/counting_penguins/yolo_files/"+image_file.split(".")[0] + ".txt"
        destination = f"{annot_txt_file}"

        #csv_buffer = StringIO()
        df_single_img_annots.to_csv(
            destination,
            index=False,
            header=False,
            sep=" ",
            float_format="%.4f",
            columns=[
                "int_category",
                "box_center_w",
                "box_center_h",
                "box_width",
                "box_height",
            ]
        )

def get_cats(json_file):
    """
    Makes a list of the category names in proper order

    Input:
    json_file: s3 path of the json file containing the category information

    Returns:
    cats: List of category names
    """

    with json_fn:
        line = json_fn.readline()
        record = json.loads(line)
        labels = [item["label"] for item in record["labels"]]

    return labels

#note that the r script "get_manifest.r" will grab the output.manifest for you
#or you can download it from S3. Could re-write to get it direct from S3 here instead?
fn=open("C:/gballard/S031/analyses/counting_penguins/scripts/output.manifest")
#print(fn)
#print(fn.readline)
parse_gt_output(fn)

# The .json file needed to get the labels for this job is stored in this location:
# f"s3://{s3_bucket}/{job_id}/ground_truth_annots/{gt_job_name}/annotation-tool/data.json"
json_fn = open("C:/gballard/S031/analyses/counting_penguins/scripts/data.json")
categories = get_cats(json_fn)
print("\n labels used in Ground Truth job: ")
print(categories, "\n")

outfile = open("c:/gballard/s031/analyses/counting_penguins/scripts/output.csv")
df_annot = annot_yolo(outfile, categories)
save_annots_to_local(df_annot)
