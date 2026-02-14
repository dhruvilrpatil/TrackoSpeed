# TrackoSpeed

A Flutter + Kotlin application that estimates the speed of other vehicles using GPS and camera, detects vehicles, performs OCR on plates, and saves annotated images to the gallery with metadata stored locally in SQLite.

## Features

- Real-time GPS speed tracking.
- Vehicle detection with TensorFlow Lite (fallback detection if model missing).
- OCR for license plate recognition.
- Capture flow that burns bounding box, speed, and plate text directly onto the image.
- Local-only storage using SQLite (no cloud).
- Defensive programming and graceful degradation on failures.

## Project Structure

- `lib/` Flutter UI, BLoC, services, and domain/data layers.
- `android/app/src/main/kotlin/` Native Kotlin platform channels.
- `android/app/src/main/assets/` ML model assets (placeholder README).

## ML Model Assets

Place your TFLite detection model and labels in:

- `android/app/src/main/assets/vehicle_detect.tflite`
- `android/app/src/main/assets/vehicle_labels.txt`

See `android/app/src/main/assets/README.md` for details.

## Permissions

The app requests:

- Camera: vehicle detection and capture.
- Location: GPS speed measurement.
- Storage/Media: saving annotated images to gallery.

## Run

```powershell
cd G:\VictorTerminal\trackospeed
flutter pub get
flutter run
```

## Test

```powershell
cd G:\VictorTerminal\trackospeed
flutter test
```

## Notes

- If ML model assets are missing, the app uses fallback detections so capture still works.
- On Windows, Flutter plugins may require Developer Mode for symlinks.
