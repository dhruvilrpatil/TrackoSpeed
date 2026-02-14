# TrackoSpeed ML Assets

This folder should contain the TensorFlow Lite models for vehicle detection.

## Required Files

1. `vehicle_detect.tflite` - Vehicle detection model (MobileNet-SSD or YOLOv8 quantized)
2. `vehicle_labels.txt` - Class labels for the model

## Model Specifications

The app expects a model with the following characteristics:
- Input: 320x320 RGB image
- Output: Bounding boxes, class IDs, confidence scores
- Classes should include: car (2), motorcycle (3), bus (5), truck (7)

## Getting a Model

You can download a pre-trained model from:
1. TensorFlow Hub: https://tfhub.dev/
2. Google's Model Garden: https://github.com/tensorflow/models

Or train your own using:
1. TensorFlow Lite Model Maker
2. YOLOv8 with export to TFLite

## Note

The app will function with fallback detection if the model is not present,
but vehicle detection accuracy will be reduced.

