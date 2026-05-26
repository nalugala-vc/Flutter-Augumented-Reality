import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/scan_config.dart';
import 'models/volume_result.dart';

abstract class ArVolumeScannerPlatform extends PlatformInterface {
  ArVolumeScannerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ArVolumeScannerPlatform _instance =
      _UnimplementedArVolumeScanner();

  static ArVolumeScannerPlatform get instance => _instance;

  static set instance(ArVolumeScannerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns true when the device supports AR depth / mesh scanning.
  Future<bool> isSupported();

  /// Returns true when the device has a LiDAR sensor.
  Future<bool> hasLidar();

  /// Starts an AR scan session with the given [config].
  /// Resolves with the computed [VolumeResult] when the scan completes.
  Future<VolumeResult> startScan(ScanConfig config);

  /// Stops the current scan early and discards any partial data.
  Future<void> stopScan();

  /// Stream of [Map] events from the native side carrying scan-state updates.
  Stream<Map<Object?, Object?>> get scanStateStream;
}

class _UnimplementedArVolumeScanner extends ArVolumeScannerPlatform {
  @override
  Future<bool> isSupported() => throw UnimplementedError('isSupported()');

  @override
  Future<bool> hasLidar() => throw UnimplementedError('hasLidar()');

  @override
  Future<VolumeResult> startScan(ScanConfig config) =>
      throw UnimplementedError('startScan()');

  @override
  Future<void> stopScan() => throw UnimplementedError('stopScan()');

  @override
  Stream<Map<Object?, Object?>> get scanStateStream =>
      throw UnimplementedError('scanStateStream');
}
