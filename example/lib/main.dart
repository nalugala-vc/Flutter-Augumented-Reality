import 'package:flutter/material.dart';
import 'package:ar_volume_scanner/ar_volume_scanner.dart';

void main() => runApp(const ArVolumeScannerApp());

class ArVolumeScannerApp extends StatelessWidget {
  const ArVolumeScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Volume Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.tealAccent,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _isSupported;
  bool? _hasLidar;
  VolumeResult? _lastResult;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    final supported = await ArVolumeScannerPlatform.instance.isSupported();
    final lidar = await ArVolumeScannerPlatform.instance.hasLidar();
    if (mounted) {
      setState(() {
        _isSupported = supported;
        _hasLidar = lidar;
      });
    }
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScannerScreen(
        onResult: (result) {
          setState(() => _lastResult = result);
          Navigator.of(context).pop();
        },
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Volume Scanner'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CapabilityChips(isSupported: _isSupported, hasLidar: _hasLidar),
            const SizedBox(height: 32),
            if (_lastResult != null) ...[
              VolumeResultCard(
                result: _lastResult!,
                onRescan: _openScanner,
              ),
            ] else ...[
              const _EmptyState(),
            ],
            const Spacer(),
            ElevatedButton.icon(
              onPressed: (_isSupported == true) ? _openScanner : null,
              icon: const Icon(Icons.view_in_ar),
              label: const Text('Start Scanning'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScannerScreen extends StatelessWidget {
  final void Function(VolumeResult) onResult;

  const ScannerScreen({super.key, required this.onResult});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArScannerView(
        config: const ScanConfig(
          preferredAlgorithm: VolumeAlgorithm.convexHull,
          maxScanSeconds: 10,
          showPointCloud: false,
        ),
        onResult: onResult,
        onError: (err) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
          );
        },
      ),
    );
  }
}

class _CapabilityChips extends StatelessWidget {
  final bool? isSupported;
  final bool? hasLidar;

  const _CapabilityChips({required this.isSupported, required this.hasLidar});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      children: [
        _StatusChip(
          label: 'AR Supported',
          active: isSupported,
          icon: Icons.view_in_ar,
        ),
        _StatusChip(
          label: 'LiDAR',
          active: hasLidar,
          icon: Icons.sensors,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool? active;
  final IconData icon;

  const _StatusChip({required this.label, required this.active, required this.icon});

  @override
  Widget build(BuildContext context) {
    final color = active == null
        ? Colors.grey
        : active!
            ? Colors.greenAccent
            : Colors.redAccent;
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      side: BorderSide(color: color),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.view_in_ar_rounded,
            size: 80, color: Colors.cyanAccent.withOpacity(0.4)),
        const SizedBox(height: 16),
        Text(
          'No scan yet',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        const Text(
          'Point your camera at any object\nand tap "Start Scanning"',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ],
    );
  }
}
