part of 'archive_icons.dart';

/// A complete gesture, not an amount of pointer pressure. All three paper
/// parts leave together, then settle in order. These finite clocks also power
/// exported SVG frames, so the showcase cannot exaggerate the app motion.
abstract final class ArchiveIconMotion {
  // 官方 MD3 Durations.long*，去掉 640/380ms 自研时长。
  static const duration = Durations.long4;
  static const morphDuration = Durations.medium4;
  // 官方 M3 emphasized decelerate，去掉自研过冲 Cubic(.18, 1.28, .32, 1)。
  static const stateCurve = Easing.emphasizedDecelerate;

  static double stateAt(double gesturePhase) => stateCurve.transform(
    (gesturePhase * duration.inMilliseconds / morphDuration.inMilliseconds)
        .clamp(0, 1),
  );

  static ArchiveIconGesture frame(double phase) => ArchiveIconGesture(
    _spring(phase),
    _spring(((phase - .055) / .945).clamp(0, 1)),
    _spring(((phase - .11) / .89).clamp(0, 1)),
  );

  static double _spring(double t) {
    const times = [0.0, .10, .36, .64, .82, 1.0];
    const values = [0.0, -.12, 1.0, -.20, .065, 0.0];
    if (t <= 0 || t >= 1) return 0;
    for (var i = 1; i < times.length; i++) {
      if (t <= times[i]) {
        final x = (t - times[i - 1]) / (times[i] - times[i - 1]);
        // 官方 M3 standard easing；保留 _spring 的折纸关键帧物理仿真。
        final eased = Easing.standard.transform(x);
        return values[i - 1] + (values[i] - values[i - 1]) * eased;
      }
    }
    return 0;
  }
}

@immutable
class ArchiveIconGesture {
  const ArchiveIconGesture(this.lead, this.follow, this.trail);
  static const rest = ArchiveIconGesture(0, 0, 0);
  final double lead, follow, trail;

  ArchiveIconGesture plus(ArchiveIconGesture other, double weight) =>
      ArchiveIconGesture(
        (lead + other.lead * weight).clamp(-.3, 1.2),
        (follow + other.follow * weight).clamp(-.3, 1.2),
        (trail + other.trail * weight).clamp(-.3, 1.2),
      );
}
