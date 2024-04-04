# Note that you need to launch your IDE as administrator for this to run

from pathlib import Path
import os
import torch  # Import PyTorch to check for CUDA availability

# Path to Workspace directory. Must end with a slash!
workspaceDir = 'C:/gballard/s031/analyses/counting_penguins/'

# Path to Yolo:
path_to_yolo = 'C:/gballard/s031/analyses/counting_penguins/yolov5'

# Path to the model you want to use - this doesn't change often!
model_name = "ADPE_20231024_adult_sit"
model_path = workspaceDir+"models/"+model_name+"/weights/best.pt"

# Path to tiles:
path_to_tiles = "D:/PenguinCounting/tiles/croz_20181129/croz_adpe_2018-11-29_lcc169/"

# Initialize paths to output files - note that Python will make these paths if they don't exist already.
output_dir = workspaceDir+"predict/2018/croz_adpe_2018-11-29_lcc169/counts/"+model_name+"/"
label_dir = output_dir+"labels"

# Check if CUDA is available
device_type = '0' if torch.cuda.is_available() else 'cpu'

# Get list of label files
existing_labels = set(Path(label_dir).glob("*.txt"))
existing_labels = {p.stem for p in existing_labels}  # Only the file names, no extensions

# Get list of tile image files
image_files = list(Path(path_to_tiles).glob("*.jpg"))  # Assuming jpg format
image_files_to_process = [img for img in image_files if img.stem not in existing_labels]

# Create a temporary folder to hold the images to be processed
temp_folder = Path(workspaceDir) / 'temp_images'
temp_folder.mkdir(parents=True, exist_ok=True)

# Symlink or copy images to temporary folder
for img in image_files_to_process:
    os.symlink(img, temp_folder / img.name)

# Command to run YOLOv5 object detection
cmd = (
    f"python {path_to_yolo}/detect.py "
    f"--weights {model_path} "
    f"--img 512 "  # Image size - seems you only need to specify the larger dimension
    f"--conf 0.50 "  # Confidence threshold - moving this up as we get more comfortable with a given model
    f"--source {temp_folder} "  # Source images from temp folder
    f"--save-txt "  # Save results to text files
    f"--save-conf "  # Save confidence scores
    f"--nosave "  # Do not save images
    f"--project {output_dir} "  # Output directory
    f"--device {device_type} "  # Set device type based on CUDA availability
)

# Execute the command
os.system(cmd)

# Clean up temporary folder
for img in temp_folder.iterdir():
   img.unlink()
temp_folder.rmdir()
