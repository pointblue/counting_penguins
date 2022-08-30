from pathlib import Path
import os
from argparse import Namespace
import sys
import glob
import detect

class Counter(object):
    """docstring for Counter"""

    def __init__(self, output_dir, models, asText=True, addConf=True, notSaveImg=True, Visualize=False, conf_thres=0.01, image_size=(512, 256)):
        super(Counter, self).__init__()
        self.conf_thres = conf_thres
        self.image_size = image_size
        self.outDir = output_dir
        self.outDir = Path(output_dir)
        self.outDir.mkdir(parents=True, exist_ok=True)
        self.asText = asText
        self.addConf = addConf
        self.notSaveImg = notSaveImg
        self.Visualize = Visualize
        self.models = models
        
    def count(self,tileDir):
    
        try:
            for mod in self.models:
                print(mod)
                
                # run_name is the name of the subfodler to create within the project folder.
                # In this case we name it after the model.  The detect function is set up to
                # NOT overwrite a run_name if it already exists and will chreate a new name
                # by adding a number after the runname and incrementing, so if you have many
                # runs they will not over write each other for better or worse!
                run_name=Path(mod).name.split(sep=".")[0]
                print(run_name)
                
                # load all the parameters See the detect.py for more info on these
                opt=Namespace(
                    conf_thres=self.conf_thres,
                    device="cpu",
                    imgsz=self.image_size,
                    iou_thres=0.3,
                    name=run_name,
                    project=str(self.outDir),
                    source=tileDir,
                    save_txt=self.asText,
                    save_conf=self.addConf,
                    nosave=self.notSaveImg,
                    visualize=self.Visualize,
                    weights=mod)
                    
                detect.main(opt)
                
        except OSError:
            print("cannot open", run_name)


