"""
RevEye — EfficientNet-B4 Fine-Tuning Script
Optimised for Apple M1 Mac
Expected accuracy: 85-92% on Stanford Cars 196 classes
"""

import os
import time
import json
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
from torchvision import datasets, transforms
from torch.optim.lr_scheduler import CosineAnnealingLR
import timm

DATA_DIR       = "/Users/user/Documents/FinalYearProject/car_data"
OUTPUT_DIR     = "/Users/user/Documents/FinalYearProject/RevEyeModel"
MODEL_NAME     = "redeye_efficientnet_b4"
NUM_EPOCHS     = 50
BATCH_SIZE     = 32
IMG_SIZE       = 380
NUM_WORKERS    = 0
LR_HEAD        = 1e-3    # Phase 1: head only
LR_FINETUNE    = 1e-4    # Phase 2: full model
UNFREEZE_EPOCH = 10      # when to unfreeze backbone
# ──────────────────────────────────────────────────────────

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ─── DEVICE (M1 MPS > CUDA > CPU) ────────────────────────
if torch.backends.mps.is_available():
    device = torch.device("mps")
    print("Apple M1 MPS GPU detected")
elif torch.cuda.is_available():
    device = torch.device("cuda")
    print("CUDA GPU detected")
else:
    device = torch.device("cpu")
    print("CPU only — training will be slow")

# ─── TRANSFORMS ──────────────────────────────────────────
train_transforms = transforms.Compose([
    transforms.Resize((IMG_SIZE + 32, IMG_SIZE + 32)),
    transforms.RandomCrop(IMG_SIZE),
    transforms.RandomHorizontalFlip(),
    transforms.RandomRotation(15),
    transforms.ColorJitter(brightness=0.3, contrast=0.3,
                           saturation=0.3, hue=0.1),
    transforms.RandomGrayscale(p=0.05),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406],
                         [0.229, 0.224, 0.225]),
])

val_transforms = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406],
                         [0.229, 0.224, 0.225]),
])

# ─── DATASETS ────────────────────────────────────────────
print("\nLoading datasets...")
train_dataset = datasets.ImageFolder(
    os.path.join(DATA_DIR, "train"), transform=train_transforms)
test_dataset  = datasets.ImageFolder(
    os.path.join(DATA_DIR, "test"), transform=val_transforms)

NUM_CLASSES = len(train_dataset.classes)
print(f"   Classes : {NUM_CLASSES}")
print(f"   Train   : {len(train_dataset)} images")
print(f"   Test    : {len(test_dataset)} images")

# Save class labels — needed for Swift app
labels_path = os.path.join(OUTPUT_DIR, "class_labels.json")
with open(labels_path, "w") as f:
    json.dump(train_dataset.classes, f, indent=2)
print(f"   Labels saved → {labels_path}")

train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE,
                          shuffle=True, num_workers=NUM_WORKERS,
                          pin_memory=False)
test_loader  = DataLoader(test_dataset, batch_size=BATCH_SIZE,
                          shuffle=False, num_workers=NUM_WORKERS,
                          pin_memory=False)

# ─── MODEL ───────────────────────────────────────────────
print("\nLoading EfficientNet-B4 pretrained on ImageNet...")
model = timm.create_model(
    "efficientnet_b4",
    pretrained=True,          # downloads ImageNet weights (~74MB)
    num_classes=NUM_CLASSES
)

# Phase 1: freeze backbone, only train the head
for name, param in model.named_parameters():
    if "classifier" not in name:
        param.requires_grad = False

model = model.to(device)
trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
total     = sum(p.numel() for p in model.parameters())
print(f"   Trainable: {trainable:,} / {total:,} params (head only)")

# ─── LOSS / OPTIMISER / SCHEDULER ────────────────────────
criterion = nn.CrossEntropyLoss(label_smoothing=0.1)
optimizer = optim.AdamW(
    filter(lambda p: p.requires_grad, model.parameters()),
    lr=LR_HEAD, weight_decay=1e-4
)
scheduler = CosineAnnealingLR(optimizer, T_max=UNFREEZE_EPOCH)

# ─── TRAINING ────────────────────────────────────────────
best_acc = 0.0
history  = []

print(f"\nPhase 1 — Head only     : epochs 1–{UNFREEZE_EPOCH}")
print(f"   Phase 2 — Full finetune : epochs {UNFREEZE_EPOCH}–{NUM_EPOCHS}\n")
print(f"{'Epoch':>6} {'Train Loss':>12} {'Train Acc':>10} {'Test Acc':>10} {'':>4} {'Time':>7}")
print("─" * 58)

for epoch in range(1, NUM_EPOCHS + 1):
    start = time.time()

    # Unfreeze full backbone at UNFREEZE_EPOCH
    if epoch == UNFREEZE_EPOCH:
        print(f"\n🔓 Epoch {epoch}: Unfreezing full backbone for deep fine-tuning...")
        for param in model.parameters():
            param.requires_grad = True
        optimizer = optim.AdamW(model.parameters(),
                                lr=LR_FINETUNE, weight_decay=1e-4)
        scheduler = CosineAnnealingLR(optimizer,
                                      T_max=NUM_EPOCHS - UNFREEZE_EPOCH)
        total_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
        print(f"   All {total_params:,} params now trainable\n")

    # Train
    model.train()
    train_loss = train_correct = 0

    for images, labels in train_loader:
        images, labels = images.to(device), labels.to(device)
        optimizer.zero_grad()
        outputs = model(images)
        loss    = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
        train_loss    += loss.item() * images.size(0)
        train_correct += (outputs.argmax(1) == labels).sum().item()

    scheduler.step()
    train_loss /= len(train_dataset)
    train_acc   = train_correct / len(train_dataset) * 100

    # Evaluate
    model.eval()
    test_correct = 0
    with torch.no_grad():
        for images, labels in test_loader:
            images, labels = images.to(device), labels.to(device)
            test_correct += (model(images).argmax(1) == labels).sum().item()

    test_acc = test_correct / len(test_dataset) * 100
    elapsed  = time.time() - start
    star     = "⭐" if test_acc > best_acc else ""

    history.append({"epoch": epoch,
                    "train_loss": round(train_loss, 4),
                    "train_acc":  round(train_acc, 2),
                    "test_acc":   round(test_acc, 2)})

    print(f"{epoch:>6} {train_loss:>12.4f} {train_acc:>9.1f}%"
          f" {test_acc:>9.1f}% {star:>4} {elapsed:>6.1f}s")

    if test_acc > best_acc:
        best_acc  = test_acc
        best_path = os.path.join(OUTPUT_DIR, f"{MODEL_NAME}_best.pth")
        torch.save({
            "epoch":                epoch,
            "model_state_dict":     model.state_dict(),
            "optimizer_state_dict": optimizer.state_dict(),
            "best_acc":             best_acc,
            "classes":              train_dataset.classes,
            "num_classes":          NUM_CLASSES,
            "img_size":             IMG_SIZE,
        }, best_path)

# Save history
history_path = os.path.join(OUTPUT_DIR, "training_history.json")
with open(history_path, "w") as f:
    json.dump(history, f, indent=2)

print(f"\nTraining complete!")
print(f"   Best accuracy : {best_acc:.1f}%")
print(f"   Model saved   : {best_path}")
print(f"   Labels saved  : {labels_path}")
