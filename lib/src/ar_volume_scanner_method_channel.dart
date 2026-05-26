import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ar_volume_scanner_platform_interface.dart';
import 'models/scan_config.dart';
import 'models/volume_result.dart';

class MethodChannelArVolumeScanner extends ArVolumeScannerPlatform {
  @visibleForTesting
  final methodChannel =
      const MethodChannel('com.nalugala.ar_volume_scanner/methods');

  final _eventChannel =
      const EventChannel('com.nalugala.ar_volume_scanner/events');

  @override
  Future<bool> isSupported() async {
    return await methodChannel.invokeMethod<bool>('isSupported') ?? false;
  }

  @override
  Future<bool> hasLidar() async {
    return await methodChannel.invokeMethod<bool>('hasLidar') ?? false;
  }

  @override
  Future<VolumeResult> startScan(ScanConfig config) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'startScan',
      config.toMap(),
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_RESULT',
        message: 'startScan returned null',
      );
    }
    return VolumeResult.fromMap(result);
  }

  @override
  Future<void> stopScan() async {
    await methodChannel.invokeMethod<void>('stopScan');
  }

  @override
  Stream<Map<Object?, Object?>> get scanStateStream {
    return _eventChannel
        .receiveBroadcastStream()
        .cast<Map<Object?, Object?>>();
  }
}
