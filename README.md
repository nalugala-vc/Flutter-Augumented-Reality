# ar_volume_scanner

A Flutter plugin that uses **ARKit** (iOS) and **ARCore** (Android) to scan a real-world object with the device camera and compute its **volume in cm³**.

## Features

| Feature | iOS | Android |
|---|---|---|
| AR depth capture | ARKit depth API | ARCore Depth API |
| LiDAR mesh scanning | ✅ (iPhone 12 Pro+) | ❌ |
| Bounding-box volume | ✅ | ✅ |
| Convex-hull volume | ✅ | ✅ |
| Mesh-tetrahedra volume | ✅ (LiDAR only) | ❌ |
| Live scan progress | ✅ | ✅ |

## Requirements

- **iOS 14+**, Xcode 14+
- **Android API 24+**, ARCore-supported device

## Usage

```dart
import 'package:ar_volume_scanner/ar_volume_scanner.dart';

// Check support
final supported = await ArVolumeScannerPlatform.instance.isSupported();
final hasLidar  = await ArVolumeScannerPlatform.instance.hasLidar();

// Embed the scanner widget
ArScannerView(
  config: ScanConfig(
    preferredAlgorithm: VolumeAlgorithm.convexHull,
    maxScanSeconds: 10,
  ),
  onResult: (VolumeResult result) {
    print('Volume: ${result.volumeCm3} cm³');
    print('Dimensions: ${result.widthCm} x ${result.heightCm} x ${result.depthCm} cm');
  },
  onError: (String error) => print('Error: $error'),
)

// Or drive it programmatically
final result = await ArVolumeScannerPlatform.instance.startScan(
  ScanConfig(preferredAlgorithm: VolumeAlgorithm.meshTetrahedra),
);
print(result.volumeLitres); // litres
```

## Volume Algorithms

| Algorithm | Description | Accuracy |
|---|---|---|
| `boundingBox` | width x height x depth | Fast, rough |
| `convexHull` | Extreme-point hull x 0.6 correction | Good for rounded objects |
| `meshTetrahedra` | Signed tetrahedra on LiDAR mesh | Most accurate |

## iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed for AR volume scanning.</string>
```

## Android Setup

The plugin registers camera and AR permissions automatically via its manifest. Ensure your app targets **minSdk 24** and has ARCore installed on the device.

## Result Object

```dart
VolumeResult(
  volumeCm3: 500.0,     // cm3
  volumeLitres: 0.5,    // litres
  volumeM3: 0.0005,     // m3
  widthCm: 10.0,
  heightCm: 8.0,
  depthCm: 6.25,
  pointCount: 3200,
  algorithm: VolumeAlgorithm.convexHull,
  timestamp: DateTime.now(),
)
```

