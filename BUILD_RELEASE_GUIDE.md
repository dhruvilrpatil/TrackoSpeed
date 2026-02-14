# TrackoSpeed - Build & Release Guide

## Build Information
- **App Name**: TrackoSpeed
- **Package**: com.example.trackospeed
- **Version**: 1.0.0+1
- **Build Date**: February 12, 2026

## Prerequisites

### Required Tools
- Flutter SDK 3.10.7+
- Android SDK 36 (API Level 36)
- Android NDK 27.0.12077973
- Java JDK 17
- Kotlin

### Required Permissions (Android)
The app requires the following permissions in AndroidManifest.xml:
- `CAMERA` - For vehicle detection and AR mode
- `ACCESS_FINE_LOCATION` - For GPS speed tracking
- `ACCESS_COARSE_LOCATION` - Fallback location
- `INTERNET` - For future features
- `WRITE_EXTERNAL_STORAGE` - For saving captures (Android < 10)
- `READ_EXTERNAL_STORAGE` - For reading captures (Android < 10)

## Build Commands

### Quick Build (Recommended)
```bash
# Build split APKs (one per ABI - smaller size)
flutter build apk --split-per-abi --release

# Output: 
# - build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# - build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# - build/app/outputs/flutter-apk/app-x86_64-release.apk
```

### Universal APK
```bash
# Build universal APK (larger size, compatible with all devices)
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk
```

### App Bundle (for Google Play Store)
```bash
# Build Android App Bundle (AAB)
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

### Debug Build
```bash
# Build debug APK for testing
flutter build apk --debug

# Or run directly on device
flutter run
```

## Build Script

A Windows batch script is provided for easy building:
```bash
build_release.bat
```

This script will:
1. Clean previous builds
2. Get dependencies
3. Build split APKs for release
4. Show output location

## Configuration Changes Made

### Android Configuration Updates
**File**: `android/app/build.gradle.kts`

Updated to support latest plugins:
```kotlin
android {
    compileSdk = 36
    ndkVersion = "27.0.12077973"
    
    defaultConfig {
        targetSdk = 36
        minSdk = 24
    }
}
```

### Fixed Issues
1. ✅ Removed non-existent font assets from pubspec.yaml
2. ✅ Updated Android SDK from 34 to 36
3. ✅ Updated NDK from 25.1.8937393 to 27.0.12077973
4. ✅ Fixed targetSdk to match compileSdk

## APK Sizes (Estimated)

### Split APKs
- **arm64-v8a** (64-bit ARM): ~25-35 MB (most modern devices)
- **armeabi-v7a** (32-bit ARM): ~20-30 MB (older devices)
- **x86_64** (Intel 64-bit): ~30-40 MB (emulators/tablets)

### Universal APK
- **All architectures**: ~80-110 MB

### App Bundle (AAB)
- **Bundle size**: ~50-70 MB
- Google Play will generate optimized APKs per device

## Testing Before Release

### Pre-flight Checklist
- [ ] Test on Android device with API 24+ (Android 7.0+)
- [ ] Verify GPS tracking works
- [ ] Verify camera preview displays
- [ ] Test dashboard speedometer animation
- [ ] Test tab navigation (Digital → AR Mode)
- [ ] Test vehicle detection (if model available)
- [ ] Test permissions flow
- [ ] Test on different screen sizes
- [ ] Verify no crashes on app lifecycle changes
- [ ] Check app size is acceptable

### Test Commands
```bash
# Install and test on connected device
flutter install

# Run in release mode
flutter run --release

# Run tests
flutter test
```

## Release Channels

### Alpha/Beta Testing
1. Build App Bundle (AAB)
2. Upload to Google Play Console
3. Create internal/closed testing track
4. Add testers via email

### Production Release
1. Build signed App Bundle
2. Complete Play Store listing:
   - App name, description
   - Screenshots (dashboard + camera mode)
   - Feature graphic
   - Privacy policy URL
   - App category: Tools
3. Set pricing (Free/Paid)
4. Select countries
5. Submit for review

## Signing Configuration

### Current Setup
Using debug signing (for testing only)

### Production Signing (Required for Play Store)

1. **Generate upload key**:
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. **Create key.properties** in `android/` folder:
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<path-to-upload-keystore.jks>
```

3. **Update build.gradle.kts** to use signing config:
```kotlin
signingConfigs {
    create("release") {
        // Load from key.properties
    }
}

buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

## Build Optimization

### Enabled Optimizations
- ✅ Code minification (ProGuard)
- ✅ Resource shrinking
- ✅ Tree-shaking (removes unused code)
- ✅ Icon tree-shaking (reduces MaterialIcons size by 99.8%)
- ✅ Multi-dex enabled (for large app)
- ✅ Split APKs per ABI

### ProGuard Rules
Custom rules in `android/app/proguard-rules.pro`:
- Keep TFLite classes
- Keep Kotlin metadata
- Keep platform channel classes

## Known Limitations

### ML Model Assets
The app expects vehicle detection model at:
- `android/app/src/main/assets/vehicle_detect.tflite`
- `android/app/src/main/assets/vehicle_labels.txt`

If not present, app will use fallback detection (mock data).

### Fonts
Custom Inter fonts are commented out. App uses system default fonts.

## Troubleshooting

### Build Fails with Gradle Error
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter build apk --release
```

### "Execution failed for task ':app:minifyReleaseWithR8'"
- Check ProGuard rules
- Disable minification temporarily: `isMinifyEnabled = false`

### APK too large
- Use split APKs: `--split-per-abi`
- Check asset sizes in `android/app/src/main/assets/`
- Remove unused dependencies

### Camera not working
- Check camera permissions in AndroidManifest.xml
- Ensure device has camera
- Test on physical device (not all emulators support camera)

## Distribution Options

### 1. Google Play Store
- Most popular distribution
- Requires Google Play Console account ($25 one-time fee)
- App review process (1-7 days)
- Automatic updates for users

### 2. Direct Distribution (APK)
- Share APK file directly
- Users must enable "Install from unknown sources"
- No automatic updates
- Good for beta testing

### 3. Alternative Stores
- Amazon Appstore
- Samsung Galaxy Store
- Huawei AppGallery
- F-Droid (open source only)

## Version Management

### Updating Version
Edit `pubspec.yaml`:
```yaml
version: 1.0.0+1  # version+build_number
```

- **Version**: Major.Minor.Patch (e.g., 1.0.0)
- **Build Number**: Incremental integer (e.g., 1, 2, 3...)

For each release:
1. Increment build number (+1)
2. Update version if features changed
3. Update changelog

## File Locations

### Build Outputs
```
build/
├── app/
│   ├── outputs/
│   │   ├── flutter-apk/          # APK files
│   │   │   ├── app-release.apk
│   │   │   ├── app-arm64-v8a-release.apk
│   │   │   ├── app-armeabi-v7a-release.apk
│   │   │   └── app-x86_64-release.apk
│   │   └── bundle/
│   │       └── release/
│   │           └── app-release.aab  # App Bundle
```

### Configuration Files
- `pubspec.yaml` - Dependencies and version
- `android/app/build.gradle.kts` - Android build config
- `android/app/src/main/AndroidManifest.xml` - Permissions
- `android/app/proguard-rules.pro` - ProGuard rules

## Support & Contact

For build issues or questions:
1. Check Flutter documentation: https://flutter.dev/docs
2. Check plugin issues on GitHub
3. Review build logs for specific errors

## Changelog

### Version 1.0.0 (Build 1) - February 12, 2026
- ✅ Initial release
- ✅ Dashboard with circular speedometer
- ✅ Camera/AR mode with vehicle detection
- ✅ GPS speed tracking
- ✅ Statistics tracking (AVG, MAX, DIST)
- ✅ Three view modes (Digital, Map, AR)
- ✅ Modern UI with gradient backgrounds
- ✅ Permission handling
- ✅ Error handling and recovery

