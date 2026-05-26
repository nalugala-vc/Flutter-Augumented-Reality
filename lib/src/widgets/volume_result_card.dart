import 'package:flutter/material.dart';
import '../models/volume_result.dart';

/// A card that displays the computed volume and bounding-box dimensions.
class VolumeResultCard extends StatelessWidget {
  final VolumeResult result;
  final VoidCallback? onRescan;

  const VolumeResultCard({
    super.key,
    required this.result,
    this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.view_in_ar, color: Colors.cyan, size: 28),
                const SizedBox(width: 10),
                Text('Volume Result',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            _BigVolume(result: result),
            const SizedBox(height: 16),
            _DimensionRow(
              label: 'Bounding Box',
              value:
                  '${result.widthCm.toStringAsFixed(1)} × '
                  '${result.heightCm.toStringAsFixed(1)} × '
                  '${result.depthCm.toStringAsFixed(1)} cm',
            ),
            _DimensionRow(
              label: 'In litres',
              value: '${result.volumeLitres.toStringAsFixed(3)} L',
            ),
            _DimensionRow(
              label: 'Algorithm',
              value: result.algorithm.name,
            ),
            _DimensionRow(
              label: 'Data points',
              value: result.pointCount.toString(),
            ),
            if (onRescan != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRescan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan Again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BigVolume extends StatelessWidget {
  final VolumeResult result;
  const _BigVolume({required this.result});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Text(
            result.volumeCm3.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: Colors.cyan,
            ),
          ),
          const Text('cm³', style: TextStyle(fontSize: 18, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _DimensionRow extends StatelessWidget {
  final String label;
  final String value;
  const _DimensionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
