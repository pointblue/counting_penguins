# note that yolo comes with a bunch of requirements - to ensure you have them all:
# pip install -r c:/counting_penguins/yolov5/requirements.txt
# yolo does recognize GPU's if they are present - specify them in the device flag (see below)
# note that you need to run pip install torch==2.1.0+cu118 -f https://download.pytorch.org/whl/torch_stable.html
# in the current virtual environment

import os

os.chdir("C:/counting_penguins")

def main():
    yolov5_path = "C:/counting_penguins/yolov5"
    data_yaml = "C:/counting_penguins/training_data/adult_20231024/data.yaml"
    cfg_yaml = "C:/counting_penguins/training_data/adult_20231024/yolo5l_20231024.yaml"
    # weights = f"{yolov5_path}/yolov5l.pt" # to start over
    weights = f"c:/counting_penguins/models/adult_s2_best.pt" # to use prior weights

    cmd = (
        f"python {yolov5_path}/train.py "
        f"--img-size 512 "
        f"--batch 16 "
        f"--epochs 150 "
        f"--data {data_yaml} "
        f"--cfg {cfg_yaml} "
        f"--weights {weights} "
        f"--device cpu "  # Changed from --device 0,1,2,3
        f"--project C:/counting_penguins/yolov5 "
        f"--name ADPE_20231024_adult_sit "
    )
    os.system(cmd)

if __name__ == "__main__":
    main()

