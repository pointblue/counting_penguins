# ----------------------------------------------------------------------------
# evaluate_test_set.py
# Evaluates the trained detection model on the held-out test set, which was
# not used for training or for selecting the retained weights. Reports
# precision, recall, mAP50, and mAP50-95 using the same definitions as the
# validation metrics recorded during training.
#
# Usage (from the repository root):
#   python code/evaluate_test_set.py \
#       --weights models/ADPE_20250804_adult_sit_best.pt
#   python code/evaluate_test_set.py --weights <path> --device cpu
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# ----------------------------------------------------------------------------
import argparse
from ultralytics import YOLO


def main():
    parser = argparse.ArgumentParser(description="Evaluate the model on the test set.")
    parser.add_argument("--weights", required=True,
                        help="Path to the trained weights (.pt)")
    parser.add_argument("--data", default="training_data/adult_20250804/penguin.yaml",
                        help="Dataset configuration file listing the test folder")
    parser.add_argument("--device", default="0",
                        help="GPU index (e.g., 0) or 'cpu'")
    parser.add_argument("--batch", type=int, default=32,
                        help="Batch size (32 matches training)")
    args = parser.parse_args()

    # ------------------------------------------------------------------------
    # Evaluate at the training input size on the test split
    # ------------------------------------------------------------------------
    model = YOLO(args.weights)
    m = model.val(data=args.data, split="test", imgsz=512, batch=args.batch,
                  device=args.device, plots=False, verbose=False)

    # ------------------------------------------------------------------------
    # Report test-set metrics
    # ------------------------------------------------------------------------
    print(f"\nTest set ({args.data}):")
    print(f"  Precision {m.box.mp:.3f}")
    print(f"  Recall    {m.box.mr:.3f}")
    print(f"  mAP50     {m.box.map50:.3f}")
    print(f"  mAP50-95  {m.box.map:.3f}")


# Worker processes on Windows re-import this file; the guard keeps them from
# re-running the evaluation
if __name__ == "__main__":
    main()