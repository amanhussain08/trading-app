import 'package:flutter/foundation.dart';

/// Debug logging for the chart, printed as `[chart.<area>] message`.
///
/// On in debug builds, compiled out of release builds. [verbose] adds the
/// messages that fire on every frame or pointer move (paints, autoscale
/// refits, pan updates); leave it off unless you are tracing one of those.
abstract final class ChartLog {
  static bool enabled = kDebugMode;
  static bool verbose = false;

  /// A one-off event: data loaded, a gesture started or ended, a mode changed.
  static void info(String area, String message) {
    if (enabled) debugPrint('[chart.$area] $message');
  }

  /// A per-frame event, only printed when [verbose] is on.
  static void frame(String area, String message) {
    if (enabled && verbose) debugPrint('[chart.$area] $message');
  }
}
