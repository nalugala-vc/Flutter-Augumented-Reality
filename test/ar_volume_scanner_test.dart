import 'package:flutter_test/flutter_test.dart';
import 'package:ar_volume_scanner/ar_volume_scanner.dart';
import 'package:ar_volume_scanner/ar_volume_scanner_platform_interface.dart';
import 'package:ar_volume_scanner/ar_volume_scanner_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockArVolumeScannerPlatform
    with MockPlatformInterfaceMixin
    implements ArVolumeScannerPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ArVolumeScannerPlatform initialPlatform = ArVolumeScannerPlatform.instance;

  test('$MethodChannelArVolumeScanner is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelArVolumeScanner>());
  });

  test('getPlatformVersion', () async {
    ArVolumeScanner arVolumeScannerPlugin = ArVolumeScanner();
    MockArVolumeScannerPlatform fakePlatform = MockArVolumeScannerPlatform();
    ArVolumeScannerPlatform.instance = fakePlatform;

    expect(await arVolumeScannerPlugin.getPlatformVersion(), '42');
  });
}
