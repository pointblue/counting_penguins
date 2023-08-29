'''
Pulls brightness, contrast, perhaps other data from an S3 source
Grant Ballard 9/11/2022 (gballard@pointblue.org)
<<<<<<< HEAD
=======
Tim DeBenedictis 10/21/2022 (timd@southernstars.com)
>>>>>>> 6a40ca1b74de708fb02ce4dcc62fb087e36bb3d5
Based on info from:
https://stackoverflow.com/questions/3490727/what-are-some-methods-to-analyze-image-brightness-using-pythonfrom PIL import Image
https://en.wikipedia.org/wiki/Contrast_(vision)

And other sources as indicated in-line below
'''
#get the packages
from PIL import Image
from PIL import ImageStat
import numpy as np #for std()
import math #for sqrt
import csv #for writing the output
import boto3 #AWS SDK for Python
import re #regular expressions for Python
import cv2 #OpenCV

'''specifics about where your tiles are (assumes S3)'''
my_bucket_name = "deju-penguinscience"
my_prefix = "PenguinCounting/croz_20191202/tiles"

#Some general S3 stuff for functions below
s3_paginator = boto3.client('s3').get_paginator('list_objects_v2')
s3 = boto3.resource('s3')

#Function to return 'perceived' brightness value
#specific numbers for perceived brightness conversion according to:
#http://alienryderflex.com/hsp.html and others
def brightness3( im_file ):
   im = Image.open(im_file)
   stat = ImageStat.Stat(im)
   r,g,b = stat.mean
   return round(math.sqrt(0.299*(r**2) + 0.587*(g**2) + 0.114*(b**2)),2)

#Function to return Michelson contrast
def contrast( im_file ):
    img = Image.open(im_file).convert('L')
    min = np.clip(np.min(img), 0, 255)
    max = np.clip(np.max(img), 0, 255)
    # compute contrast
    return round(((max-min) / (max+min)),2)

#Function for RMS Contrast
def contrast2( im_file ):
   im = Image.open(im_file).convert('L')
   return round(np.std(im), 2)

<<<<<<< HEAD
=======
#Function to return focus/sharpness measure (f)
# see https://sites.google.com/view/cvia/focus-measure
# and https://www.mathworks.com/matlabcentral/fileexchange/27314-focus-measure
# and https://www.researchgate.net/profile/Said-Pertuz/publication/234073157_Analysis_of_focus_measure_operators_in_shape-from-focus/links/5cfc076b4585157d159e0289/Analysis-of-focus-measure-operators-in-shape-from-focus.pdf
# and https://stackoverflow.com/questions/7765810/is-there-a-way-to-detect-if-an-image-is-blurry/7767755#7767755

def normalizedLaplacianSigma ( img ):
    lap = cv2.Laplacian ( img, cv2.CV_64F )
    mu, sigma = cv2.meanStdDev ( lap )
    f = sigma[0] / mu[0]
    return math.log10 ( abs ( float ( f ) ) )

'''function for listing all the file names in an S3 object'''

def keys(bucket_name, prefix='/', delimiter='/', start_after=''):
    prefix = prefix[1:] if prefix.startswith(delimiter) else prefix
    start_after = (start_after or prefix) if prefix.endswith(delimiter) else start_after
    for page in s3_paginator.paginate(Bucket=bucket_name, Prefix=prefix, StartAfter=start_after):
        for content in page.get('Contents', ()):
            yield content['Key']

#Main Program below:

#create csv to store image data

header = ['tile', 'brightness', 'contrast_Michelson', 'contrast_RMS', 'min', 'max', 'mean', 'stdev', 'sharpness']

with open('../tile_properties.csv', 'w', encoding='UTF8', newline='') as f:
    writer = csv.writer(f)

    # write the header
    writer.writerow(header)

    # get brightness and write the data to csv
    for images in (list(keys(my_bucket_name,my_prefix))):
        dl_file = 'temp.jpg' #will keep overwriting this file; change if you want all the tiles downloaded
        s3.meta.client.download_file(my_bucket_name, images, dl_file)
        # check if the image ends with jpg
        if (images.endswith(".jpg")):
            image_name = re.search(r'(?<=tiles\/)(.+)(?=.jpg)', images)
            image_name = image_name.group()
            img = cv2.imread ( dl_file, cv2.IMREAD_GRAYSCALE )
            if img is None:
                f = 0
                min, max, min_loc, max_loc = 0
                mean, std = 0
            else:
                f = normalizedLaplacianSigma ( img )
                min, max, min_loc, max_loc = cv2.minMaxLoc ( img )
                mean, std = cv2.meanStdDev ( img )
            data = [image_name, brightness3(dl_file), contrast(dl_file), contrast2(dl_file), min, max, mean[0][0], std[0][0], f]
            writer.writerow(data)
            print(image_name) #if you want to watch progress - but will slow things down probably
