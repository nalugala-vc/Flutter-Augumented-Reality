/// Result returned after a completed AR volume scan.
class VolumeResult {
  /// Volume in cubic centimetres (cm³).
  final double volumeCm3;

  /// Bounding-box dimensions in centimetres.
  final double widthCm;
  final double heightCm;
  final double depthCm;

  /// How many depth/mesh points were used in the calculation.
  final int pointCount;

  /// Algorithm used to derive the volume.
  final VolumeAlgorithm algorithm;

  /// Timestamp of the scan.
  final DateTime timestamp;

  const VolumeResult({
    required this.volumeCm3,
    required this.widthCm,
    required this.heightCm,
    required this.depthCm,
    required this.pointCount,
    required this.algorithm,
    required this.timestamp,
  });

  /// Volume converted to litres.
  double get volumeLitres => volumeCm3 / 1000.0;

  /// Volume converted to cubic metres.
  double get volumeM3 => volumeCm3 / 1_000_000.0;

  factory VolumeResult.fromMap(Map<Object?, Object?> map) {
    return VolumeResult(
      volumeCm3: (map['volumeCm3'] as num).toDouble(),
      widthCm: (map['widthCm'] as num).toDouble(),
      heightCm: (map['heightCm'] as num).toDouble(),
      depthCm: (map['depthCm'] as num).toDouble(),
      pointCount: (map['pointCount'] as int?) ?? 0,
      algorithm: VolumeAlgorithm.values.firstWhere(
        (e) => e.name == (map['algorithm'] as String? ?? 'boundingBox'),
        orElse: () => VolumeAlgorithm.boundingBox,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMs'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  String toString() =>
      'VolumeResult(${volumeCm3.toStringAsFixed(2)} cm³, '
      '${widthCm.toStringAsFixed(1)}×${heightCm.toStringAsFixed(1)}×${depthCm.toStringAsFixed(1)} cm, '
      'algorithm: ${algorithm.name})';
}

enum VolumeAlgorithm {
  /// Fast axis-aligned bounding box — width × height × depth.
  boundingBox,

  /// Convex hull — more accurate for convex objects.
  convexHull,

  /// Signed-tetrahedra mesh sum — most accurate, requires LiDAR mesh.
  meshTetrahedra,
}
