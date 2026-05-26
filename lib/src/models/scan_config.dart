import 'volume_result.dart';

/// Configuration passed to the AR scanner before a session begins.
class ScanConfig {
  /// Preferred algorithm. The native side may fall back if the device
  /// lacks LiDAR or the Depth API.
  final VolumeAlgorithm preferredAlgorithm;

  /// Maximum scan duration in seconds before auto-stopping.
  final int maxScanSeconds;

  /// Minimum confidence (0–1) for depth pixels to be included.
  final double minDepthConfidence;

  /// Whether to show the debug point-cloud overlay.
  final bool showPointCloud;

  const ScanConfig({
    this.preferredAlgorithm = VolumeAlgorithm.convexHull,
    this.maxScanSeconds = 10,
    this.minDepthConfidence = 0.5,
    this.showPointCloud = false,
  });

  Map<String, Object> toMap() => {
        'preferredAlgorithm': preferredAlgorithm.name,
        'maxScanSeconds': maxScanSeconds,
        'minDepthConfidence': minDepthConfidence,
        'showPointCloud': showPointCloud,
      };
}
