import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../data/models/candle.dart';
import '../chart_log.dart';
import 'time_scale.dart';

/// A price range shown top ([high]) to bottom ([low]) of a pane.
@immutable
class PriceRange {
  const PriceRange(this.low, this.high);

  static const empty = PriceRange(0, 0);

  final double low;
  final double high;

  bool get isEmpty => high <= low;

  /// y of [price] in a pane [height] tall; higher prices sit higher.
  double priceToY(double price, double height) =>
      (high - price) / (high - low) * height;

  double yToPrice(double y, double height) =>
      high - y / height * (high - low);

  @override
  bool operator ==(Object other) =>
      other is PriceRange && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);

  @override
  String toString() =>
      'PriceRange(${low.toStringAsFixed(2)}..${high.toStringAsFixed(2)})';
}

/// Vertical scale of the price pane, after Lightweight Charts' PriceScale.
///
/// In auto-scale (the default) the range fits the visible candles plus
/// [padding], computed lazily when read and cached until the candles or the
/// visible range change. Dragging prices switches to a manual range until
/// [resetAutoScale]. The volume pane is always fitted to the visible candles.
class PriceScale extends ChangeNotifier {
  /// Space above and below the visible candles, as a fraction of their range.
  static const padding = 0.05;

  bool _autoScale = true;
  PriceRange _manual = PriceRange.empty;

  /// What [range] returned last, so a manual drag starts from what is shown.
  PriceRange _shown = PriceRange.empty;

  List<Candle>? _fitCandles;
  (int, int)? _fitVisible;
  PriceRange _fitted = PriceRange.empty;
  double _fittedVolumeMax = 0;

  bool get autoScale => _autoScale;

  /// The price range to draw [candles] with, at [timeScale]'s visible range.
  PriceRange range(List<Candle> candles, TimeScale timeScale) {
    _shown = _autoScale ? _fit(candles, timeScale) : _manual;
    return _shown;
  }

  /// Largest visible volume; the volume pane's scale.
  double volumeMax(List<Candle> candles, TimeScale timeScale) {
    _fit(candles, timeScale);
    return _fittedVolumeMax;
  }

  PriceRange _fit(List<Candle> candles, TimeScale timeScale) {
    final visible = timeScale.visibleRange;
    if (identical(candles, _fitCandles) && visible == _fitVisible) return _fitted;
    _fitCandles = candles;
    _fitVisible = visible;

    if (candles.isEmpty || visible == null) {
      _fitted = PriceRange.empty;
      _fittedVolumeMax = 0;
      return _fitted;
    }
    final (from, to) = visible;
    final last = math.min(to, candles.length - 1);
    var low = candles[from].low;
    var high = candles[from].high;
    var volumeMax = 0.0;
    for (var i = from; i <= last; i++) {
      low = math.min(low, candles[i].low);
      high = math.max(high, candles[i].high);
      volumeMax = math.max(volumeMax, candles[i].volume);
    }
    final pad = high > low
        ? (high - low) * padding
        : math.max(high.abs() * 0.01, 1.0);
    _fitted = PriceRange(low - pad, high + pad);
    _fittedVolumeMax = volumeMax;
    ChartLog.frame('price', 'autoscale fit candles $from..$last -> $_fitted volumeMax=$volumeMax');
    return _fitted;
  }

  /// Shifts prices by [fraction] of the pane height (positive = drag down).
  void panBy(double fraction) {
    final base = _autoScale ? _shown : _manual;
    if (base.isEmpty || fraction == 0) return;
    final shift = fraction * (base.high - base.low);
    _setManual(PriceRange(base.low + shift, base.high + shift), 'pan');
  }

  /// Multiplies the range around its middle by [factor] (> 1 compresses).
  void scaleBy(double factor) {
    final base = _autoScale ? _shown : _manual;
    if (base.isEmpty || factor <= 0 || factor == 1) return;
    final middle = (base.low + base.high) / 2;
    final half = (base.high - base.low) * factor / 2;
    _setManual(PriceRange(middle - half, middle + half), 'scale');
  }

  void _setManual(PriceRange range, String reason) {
    if (_autoScale) ChartLog.info('price', 'autoscale OFF ($reason) from $range');
    ChartLog.frame('price', 'manual $reason -> $range');
    _autoScale = false;
    _manual = range;
    _shown = range;
    notifyListeners();
  }

  /// Fit the visible candles again, and keep doing so.
  void resetAutoScale() {
    if (_autoScale) return;
    _autoScale = true;
    ChartLog.info('price', 'autoscale ON');
    notifyListeners();
  }
}
