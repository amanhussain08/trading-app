import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../chart_log.dart';

/// Horizontal position of every candle, the way Lightweight Charts' TimeScale
/// does it: candles are slots counted by index (no gaps for missing time),
/// laid out from the right edge.
///
/// Three numbers describe the whole view:
/// * [barSpacing]: width of one candle slot, in logical pixels (zoom).
/// * [rightOffset]: slots of empty space past the newest candle (scroll);
///   negative when scrolled back into history.
/// * [width]: the candle pane's width.
///
/// Candle `i`'s centre is at
/// `width - (newestIndex + rightOffset - i + 0.5) * barSpacing`.
class TimeScale extends ChangeNotifier {
  TimeScale({
    this.initialVisibleCount = defaultInitialVisibleCount,
    this.minVisibleCount = defaultMinVisibleCount,
    this.maxVisibleCount = defaultMaxVisibleCount,
  });

  /// How many candles fit across the chart before any zooming.
  static const defaultInitialVisibleCount = 50;

  /// Zoom limits, as the number of candles across the chart's width.
  static const defaultMinVisibleCount = 5.0;
  static const defaultMaxVisibleCount = 200.0;

  final int initialVisibleCount;
  final double minVisibleCount;
  final double maxVisibleCount;

  double _width = 0;
  double _barSpacing = 0;
  double _rightOffset = 0;
  int _count = 0;

  /// Width of the candle pane, in logical pixels; set by layout.
  double get width => _width;

  /// Width of one candle slot, in logical pixels: bigger is zoomed in.
  double get barSpacing => _barSpacing;

  /// Slots between the newest candle and the right edge: positive is empty
  /// space past it, negative is scrolled back into history.
  double get rightOffset => _rightOffset;

  /// Number of candles the scale lays out.
  int get count => _count;

  /// Candles that fit across the width at the current zoom (fractional).
  double get visibleCount => _barSpacing > 0 ? _width / _barSpacing : 0;

  /// True until there is both a width and candles; nothing can be drawn yet.
  bool get isEmpty => _width <= 0 || _barSpacing <= 0 || _count == 0;

  int get _newestIndex => _count - 1;

  /// Centre x of candle [index]; works past either end too (empty slots).
  double indexToX(int index) =>
      _width - (_newestIndex + _rightOffset - index + 0.5) * _barSpacing;

  /// Index of the candle slot under [x]; may be outside `0..count-1`.
  int xToIndex(double x) => _round6(_floatIndexAt(x)).ceil();

  /// x of a fractional candle position: candle `i`'s centre is at exactly
  /// `i`, so `logicalToX(i) == indexToX(i)`.
  double logicalToX(double logical) =>
      _width - (_newestIndex + _rightOffset - logical + 0.5) * _barSpacing;

  /// Inverse of [logicalToX].
  double xToLogical(double x) => _floatIndexAt(x) + 0.5;

  /// Fractional index at [x]: slot `i` covers `(i - 1, i]`.
  double _floatIndexAt(double x) =>
      _newestIndex + _rightOffset - (_width - x) / _barSpacing;

  /// Slots that overlap the pane, including empty ones past the newest
  /// candle; null while there is nothing to lay out.
  (int, int)? get visibleSlots {
    if (isEmpty) return null;
    final right = _newestIndex + _rightOffset;
    final from = _round6(right - visibleCount).floor() + 1;
    final to = _round6(right).ceil();
    return (from, to);
  }

  /// Indices of the candles on screen (inclusive), clamped to real candles.
  (int, int)? get visibleRange {
    final slots = visibleSlots;
    if (slots == null) return null;
    final from = slots.$1.clamp(0, _newestIndex);
    final to = slots.$2.clamp(from, _newestIndex);
    return (from, to);
  }

  /// Sets the pane width from layout, keeping the same number of candles
  /// across. Doesn't notify: whoever lays out at the new width repaints anyway.
  void setWidth(double width) {
    if (width == _width || width <= 0) return;
    final keepCount = _barSpacing > 0 ? visibleCount : initialVisibleCount.toDouble();
    _width = width;
    _barSpacing = width / keepCount;
    _clampRightOffset();
    ChartLog.info(
      'time',
      'width=${width.toStringAsFixed(1)} barSpacing=${_barSpacing.toStringAsFixed(2)} '
          'visibleCount=${keepCount.toStringAsFixed(1)}',
    );
  }

  /// A fresh set of [count] candles: newest at the right edge, default zoom.
  void reset(int count) {
    _count = count;
    _rightOffset = 0;
    if (_width > 0) _barSpacing = _width / initialVisibleCount;
    ChartLog.info('time', 'reset count=$count, newest candle at the right edge');
    notifyListeners();
  }

  /// [added] candles were appended. If the newest candle sat at the right
  /// edge the view follows it (the new candle scrolls in); otherwise the
  /// offset shrinks by the same amount so the same candles stay on screen.
  void candlesAppended(int added) {
    if (added <= 0) return;
    _count += added;
    final following = _rightOffset.abs() < 0.5;
    if (!following) _rightOffset -= added;
    _clampRightOffset();
    ChartLog.info(
      'time',
      '+$added candle(s), count=$_count, '
          '${following ? 'following live' : 'view kept still, rightOffset=${_rightOffset.toStringAsFixed(2)}'}',
    );
    notifyListeners();
  }

  /// Scrolls by [dx] pixels; positive drags the candles right (into history).
  /// Returns whether anything moved, so a fling can stop at an edge.
  bool panBy(double dx) {
    if (isEmpty || dx == 0) return false;
    final before = _rightOffset;
    _rightOffset -= dx / _barSpacing;
    _clampRightOffset();
    final moved = _rightOffset != before;
    if (moved) {
      ChartLog.frame(
        'time',
        'pan dx=${dx.toStringAsFixed(1)} rightOffset=${_rightOffset.toStringAsFixed(2)} '
            'visible=$visibleRange',
      );
      notifyListeners();
    }
    return moved;
  }

  /// Zooms so about [targetCount] candles fit across, keeping the candle
  /// under [focalX] in place. Only opens empty space past the newest candle
  /// if there already was some.
  void zoomTo(double targetCount, double focalX) {
    if (isEmpty) return;
    final count = targetCount.clamp(minVisibleCount, maxVisibleCount);
    final newSpacing = _width / count;
    if (newSpacing == _barSpacing) return;

    final anchor = _floatIndexAt(focalX);
    final hadSpacePastNewest = _rightOffset > 0;
    _barSpacing = newSpacing;
    _rightOffset = anchor - _newestIndex + (_width - focalX) / _barSpacing;
    if (!hadSpacePastNewest) _rightOffset = math.min(_rightOffset, 0);
    _clampRightOffset();
    ChartLog.frame(
      'time',
      'zoom visibleCount=${count.toStringAsFixed(1)} barSpacing=${_barSpacing.toStringAsFixed(2)} '
          'anchor=${anchor.toStringAsFixed(1)} visible=$visibleRange',
    );
    notifyListeners();
  }

  /// Keeps at least one candle on screen past the newest one, and never
  /// scrolls further back than the oldest candle at the left edge.
  void _clampRightOffset() {
    if (_barSpacing <= 0) return;
    final maxOffset = math.max(0.0, visibleCount - 1);
    final minOffset = math.min(0.0, visibleCount - _count);
    _rightOffset = _rightOffset.clamp(minOffset, math.max(minOffset, maxOffset));
  }

  /// Rounds away floating-point noise (e.g. 249.0000000001) before floor/ceil.
  static double _round6(double v) => (v * 1e6).roundToDouble() / 1e6;
}
