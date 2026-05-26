import 'package:flutter_test/flutter_test.dart';
import 'package:ar_volume_scanner/ar_volume_scanner.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ─── Mock platform ────────────────────────────────────────────────────────────

class MockArVolumeScannerPlatform
    with MockPlatformInterfaceMixin
    implements ArVolumeScannerPlatform {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> hasLidar() async => false;

  @override
  Future<VolumeResult> startScan(ScanConfig config) async {
    return VolumeResult(
      volumeCm3: 500.0,
      widthCm: 10.0,
      heightCm: 8.0,
      depthCm: 6.25,
      pointCount: 3200,
      algorithm: config.preferredAlgorithm,
      timestamp: DateTime(2025),
    );
  }

  @override
  Future<void> stopScan() async {}

  @override
  Stream<Map<Object?, Object?>> get scanStateStream => const Stream.empty();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('Platform interface', () {
    test('MethodChannelArVolumeScanner can be set as instance', () {
      final mc = MethodChannelArVolumeScanner();
      ArVolumeScannerPlatform.instance = mc;
      expect(ArVolumeScannerPlatform.instance, isInstanceOf<MethodChannelArVolumeScanner>());
    });
  });

  group('VolumeResult model', () {
    late VolumeResult result;

    setUp(() {
      result = VolumeResult(
        volumeCm3: 1000.0,
        widthCm: 10.0,
        heightCm: 10.0,
        depthCm: 10.0,
        pointCount: 500,
        algorithm: VolumeAlgorithm.convexHull,
        timestamp: DateTime(2025),
      );
    });

    test('volumeLitres converts correctly', () {
      expect(result.volumeLitres, closeTo(1.0, 0.001));
    });

    test('volumeM3 converts correctly', () {
      expect(result.volumeM3, closeTo(0.001, 0.000001));
    });

    test('fromMap round-trips', () {
      final map = <Object?, Object?>{
        'volumeCm3': 500.0,
        'widthCm': 10.0,
        'heightCm': 8.0,
        'depthCm': 6.25,
        'pointCount': 3200,
        'algorithm': 'boundingBox',
        'timestampMs': 1_000_000,
      };
      final r = VolumeResult.fromMap(map);
      expect(r.volumeCm3, 500.0);
      expect(r.widthCm, 10.0);
      expect(r.algorithm, VolumeAlgorithm.boundingBox);
      expect(r.pointCount, 3200);
    });

    test('unknown algorithm defaults to boundingBox', () {
      final map = <Object?, Object?>{
        'volumeCm3': 1.0,
        'widthCm': 1.0,
        'heightCm': 1.0,
        'depthCm': 1.0,
        'algorithm': 'unknownAlgo',
        'timestampMs': 0,
      };
      final r = VolumeResult.fromMap(map);
      expect(r.algorithm, VolumeAlgorithm.boundingBox);
    });
  });

  group('ScanConfig model', () {
    test('toMap contains all keys', () {
      const cfg = ScanConfig(
        preferredAlgorithm: VolumeAlgorithm.meshTetrahedra,
        maxScanSeconds: 15,
        minDepthConfidence: 0.7,
        showPointCloud: true,
      );
      final map = cfg.toMap();
      expect(map['preferredAlgorithm'], 'meshTetrahedra');
      expect(map['maxScanSeconds'], 15);
      expect(map['minDepthConfidence'], closeTo(0.7, 0.001));
      expect(map['showPointCloud'], isTrue);
    });
  });

  group('ScanState model', () {
    test('ScanState.idle() has correct defaults', () {
      const s = ScanState.idle();
      expect(s.phase, ScanPhase.idle);
      expect(s.progress, 0.0);
      expect(s.message, isNull);
    });

    test('fromMap parses phase and progress', () {
      final s = ScanState.fromMap(<Object?, Object?>{
        'phase': 'scanning',
        'progress': 0.65,
        'message': 'Keep going',
      });
      expect(s.phase, ScanPhase.scanning);
      expect(s.progress, closeTo(0.65, 0.001));
      expect(s.message, 'Keep going');
    });

    test('unknown phase defaults to idle', () {
      final s = ScanState.fromMap(<Object?, Object?>{'phase': 'flying'});
      expect(s.phase, ScanPhase.idle);
    });
  });

  group('Mock platform startScan', () {
    setUp(() {
      ArVolumeScannerPlatform.instance = MockArVolumeScannerPlatform();
    });

    test('returns VolumeResult with correct algorithm', () async {
      const cfg = ScanConfig(preferredAlgorithm: VolumeAlgorithm.convexHull);
      final result = await ArVolumeScannerPlatform.instance.startScan(cfg);
      expect(result.algorithm, VolumeAlgorithm.convexHull);
      expect(result.volumeCm3, 500.0);
    });

    test('isSupported returns true from mock', () async {
      expect(await ArVolumeScannerPlatform.instance.isSupported(), isTrue);
    });
  });
}
