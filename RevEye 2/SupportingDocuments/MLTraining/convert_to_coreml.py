"""
RevEye — Convert trained EfficientNet-B4 to CoreML
Run this AFTER train_efficientnet.py has finished
Output: redeye_cars.mlmodel — drag straight into Xcode
"""

import torch
import timm
import json
import coremltools as ct
from torchvision import transforms

# ─── CONFIG ───────────────────────────────────────────────
MODEL_PATH  = "/Users/user/Documents/FinalYearProject/RevEyeModel/redeye_efficientnet_b4_video_best.pth"
LABELS_PATH = "/Users/user/Documents/FinalYearProject/car_data/class_labels_renamed.json"
OUTPUT_PATH = "/Users/user/Documents/FinalYearProject/RevEyeModel/RevEyeCars.mlpackage"
IMG_SIZE    = 380
# ──────────────────────────────────────────────────────────

print("📂 Loading checkpoint...")
checkpoint = torch.load(MODEL_PATH, map_location="cpu")
classes    = checkpoint["classes"]
NUM_CLASSES = len(classes)
print(f"   Classes: {NUM_CLASSES}")
print(f"   Best accuracy was: {checkpoint['best_acc']:.1f}%")

# Rebuild model and load weights
print("\n🧠 Rebuilding model...")
model = timm.create_model("efficientnet_b4",
                           pretrained=False,
                           num_classes=NUM_CLASSES)
model.load_state_dict(checkpoint["model_state_dict"])
model.eval()
print("   Weights loaded ✅")

# Trace the model with a dummy input
print("\n🔄 Tracing model...")
dummy_input = torch.zeros(1, 3, IMG_SIZE, IMG_SIZE)
traced      = torch.jit.trace(model, dummy_input)
print("   Model traced ✅")

# Convert to CoreML
print("\n⚙️  Converting to CoreML...")
mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(
        name="image",
        shape=(1, 3, IMG_SIZE, IMG_SIZE),
        scale=1/255.0,
        bias=[-0.485/0.229, -0.456/0.224, -0.406/0.225],
        color_layout=ct.colorlayout.RGB,
    )],
    classifier_config=ct.ClassifierConfig(classes),
    minimum_deployment_target=ct.target.iOS15,
    compute_units=ct.ComputeUnit.ALL,
)

# Add metadata
mlmodel.short_description = "RevEye Car Classifier — EfficientNet-B4"
mlmodel.input_description["image"] = "Car image to classify"
mlmodel.output_description["classLabel"] = "Predicted car make, model and year"

# Save
mlmodel.save(OUTPUT_PATH)
print(f"\n✅ CoreML model saved!")
print(f"   Path     : {OUTPUT_PATH}")
print(f"   Classes  : {NUM_CLASSES}")
print(f"\n▶  Drag RevEyeCars.mlpackage into your Xcode project")
print(f"   Xcode auto-generates the Swift class for you")
