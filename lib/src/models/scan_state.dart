/// Represents the current state of an AR scan session.
enum ScanPhase {
  idle,
  initialising,
  detecting,   // looking for a flat surface / target object
  scanning,    // actively capturing depth/mesh data
  processing,  // computing volume
  complete,
  error,
}

class ScanState {
  final ScanPhase phase;
  final double progress; // 0.0 – 1.0 during scanning/processing
  final String? message;
  final String? errorMessage;

  const ScanState({
    required this.phase,
    this.progress = 0.0,
    this.message,
    this.errorMessage,
  });

  const ScanState.idle()
      : phase = ScanPhase.idle,
        progress = 0.0,
        message = null,
        errorMessage = null;

  factory ScanState.fromMap(Map<Object?, Object?> map) {
    return ScanState(
      phase: ScanPhase.values.firstWhere(
        (e) => e.name == (map['phase'] as String? ?? 'idle'),
        orElse: () => ScanPhase.idle,
      ),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      message: map['message'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}
