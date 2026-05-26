import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/scan_config.dart';
import '../models/scan_state.dart';
import '../models/volume_result.dart';
import '../ar_volume_scanner_platform_interface.dart';

/// Embeds the native AR camera view and drives a scan session.
///
/// ```dart
/// ArScannerView(
///   config: ScanConfig(preferredAlgorithm: VolumeAlgorithm.convexHull),
///   onResult: (result) => print(result),
/// )
/// ```
class ArScannerView extends StatefulWidget {
  final ScanConfig config;
  final void Function(VolumeResult result) onResult;
  final void Function(String error)? onError;
  final void Function(ScanState state)? onStateChanged;

  const ArScannerView({
    super.key,
    required this.config,
    required this.onResult,
    this.onError,
    this.onStateChanged,
  });

  @override
  State<ArScannerView> createState() => _ArScannerViewState();
}

class _ArScannerViewState extends State<ArScannerView> {
  ScanState _state = const ScanState.idle();
  StreamSubscription<Map<Object?, Object?>>? _eventSub;

  @override
  void initState() {
    super.initState();
    _eventSub = ArVolumeScannerPlatform.instance.scanStateStream.listen(
      (event) {
        final newState = ScanState.fromMap(event);
        setState(() => _state = newState);
        widget.onStateChanged?.call(newState);
      },
      onError: (e) => widget.onError?.call(e.toString()),
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    ArVolumeScannerPlatform.instance.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      final result =
          await ArVolumeScannerPlatform.instance.startScan(widget.config);
      widget.onResult(result);
    } on PlatformException catch (e) {
      widget.onError?.call(e.message ?? e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _NativeArView(config: widget.config),
        _ScanOverlay(state: _state),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: _ScanButton(state: _state, onPressed: _startScan),
          ),
        ),
      ],
    );
  }
}

/// Hosts the platform-native AR view via a PlatformView.
class _NativeArView extends StatelessWidget {
  final ScanConfig config;
  const _NativeArView({required this.config});

  @override
  Widget build(BuildContext context) {
    const viewType = 'com.nalugala.ar_volume_scanner/ar_view';
    final creationParams = config.toMap();

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    // Android
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) => PlatformViewsService
          .initSurfaceAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create(),
    );
  }
}

/// Translucent HUD drawn on top of the AR view.
class _ScanOverlay extends StatelessWidget {
  final ScanState state;
  const _ScanOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: [
          const SizedBox(height: 60),
          _PhaseLabel(state: state),
          if (state.phase == ScanPhase.scanning ||
              state.phase == ScanPhase.processing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
              child: LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                backgroundColor: Colors.white30,
                color: Colors.cyanAccent,
                minHeight: 4,
              ),
            ),
        ],
      ),
    );
  }
}

class _PhaseLabel extends StatelessWidget {
  final ScanState state;
  const _PhaseLabel({required this.state});

  String get _label {
    switch (state.phase) {
      case ScanPhase.idle:
        return 'Point the camera at an object and tap Scan';
      case ScanPhase.initialising:
        return 'Initialising AR session…';
      case ScanPhase.detecting:
        return 'Move around the object slowly';
      case ScanPhase.scanning:
        return state.message ?? 'Scanning — keep moving…';
      case ScanPhase.processing:
        return 'Calculating volume…';
      case ScanPhase.complete:
        return 'Scan complete';
      case ScanPhase.error:
        return state.errorMessage ?? 'An error occurred';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  final ScanState state;
  final VoidCallback onPressed;
  const _ScanButton({required this.state, required this.onPressed});

  bool get _busy =>
      state.phase == ScanPhase.scanning ||
      state.phase == ScanPhase.processing ||
      state.phase == ScanPhase.initialising;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.radar),
      label: Text(_busy ? 'Scanning…' : 'Scan Object'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.cyanAccent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}
