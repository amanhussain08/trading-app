import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../data/models/candle.dart';
import '../chart_log.dart';
import '../scale/price_scale.dart';
import '../scale/time_scale.dart';

/// A spot on the chart in data terms, a moment and a price, so drawings stay
/// on their candles through panning, zooming, new candles and interval
/// changes.
@immutable
class ChartPoint {
  const ChartPoint(this.time, this.price);

  final DateTime time;
  final double price;

  /// This point moved [dt] later and [dPrice] higher.
  ChartPoint shift(Duration dt, double dPrice) =>
      ChartPoint(time.add(dt), price + dPrice);

  @override
  bool operator ==(Object other) =>
      other is ChartPoint && other.time == time && other.price == price;

  @override
  int get hashCode => Object.hash(time, price);

  @override
  String toString() =>
      '(${time.toIso8601String()}, ${price.toStringAsFixed(2)})';
}

/// Something the user drew on the chart. Immutable: editing one replaces it
/// in the [DrawingController] with a new value.
sealed class Drawing {
  const Drawing();

  /// The whole drawing moved [dt] later and [dPrice] higher.
  Drawing moveBy(Duration dt, double dPrice);
}

/// A price level across the whole chart. Has no time, so moving it in time
/// does nothing.
final class HorizontalLine extends Drawing {
  const HorizontalLine(this.price);

  final double price;

  @override
  HorizontalLine moveBy(Duration dt, double dPrice) =>
      HorizontalLine(price + dPrice);

  @override
  String toString() => 'HorizontalLine(${price.toStringAsFixed(2)})';
}

/// A segment between two points. Each end is a time and a price, so the
/// line keeps its slope through zooming and stays on its candles.
final class TrendLine extends Drawing {
  const TrendLine(this.start, this.end);

  final ChartPoint start;
  final ChartPoint end;

  @override
  TrendLine moveBy(Duration dt, double dPrice) =>
      TrendLine(start.shift(dt, dPrice), end.shift(dt, dPrice));

  @override
  String toString() => 'TrendLine($start -> $end)';
}

/// What the next tap or drag on the chart places.
enum DrawingTool {
  /// One tap or drag sets the price.
  horizontalLine,

  /// Two taps, or one drag from start to end.
  trendLine,
}

/// The part of a drawing under a finger: the line itself moves the whole
/// drawing, an end moves just that end.
enum DrawingPart { body, start, end }

/// A drawing under a finger: its position in [DrawingController.drawings],
/// and which part of it was touched.
typedef DrawingHit = ({int index, DrawingPart part});

/// Converts between [ChartPoint]s and candle-pane pixels for one frame of
/// [candles], [timeScale] and the price [range].
class DrawingGeometry {
  const DrawingGeometry({
    required this.candles,
    required this.timeScale,
    required this.range,
    required this.pricePaneHeight,
  });

  /// How close, in logical pixels, a finger must be to grab a drawing.
  static const touchSlop = 16.0;

  final List<Candle> candles;
  final TimeScale timeScale;
  final PriceRange range;
  final double pricePaneHeight;

  /// Nothing to convert with yet: positions need at least two candles (to
  /// know the interval), a laid-out time scale and a price range.
  bool get isEmpty =>
      candles.length < 2 ||
      timeScale.isEmpty ||
      range.isEmpty ||
      pricePaneHeight <= 0;

  /// y of [price] in the price pane.
  double yOf(double price) => range.priceToY(price, pricePaneHeight);

  /// Price at [y] in the price pane.
  double priceAt(double y) => range.yToPrice(y, pricePaneHeight);

  /// Where [p] is on screen, between candles if its time falls between them.
  Offset offsetOf(ChartPoint p) =>
      Offset(timeScale.logicalToX(_logicalOf(p.time)), yOf(p.price));

  /// The time and price under [o]; inverse of [offsetOf].
  ChartPoint pointAt(Offset o) =>
      ChartPoint(_timeOf(timeScale.xToLogical(o.dx)), priceAt(o.dy));

  /// Topmost drawing within [touchSlop] of [p], preferring the ends of a
  /// trend line over its body so a short line can still be stretched.
  DrawingHit? hitTest(List<Drawing> drawings, Offset p) {
    if (isEmpty) return null;
    for (var i = drawings.length - 1; i >= 0; i--) {
      switch (drawings[i]) {
        case HorizontalLine(:final price):
          if ((yOf(price) - p.dy).abs() <= touchSlop) {
            return (index: i, part: DrawingPart.body);
          }
        case TrendLine(:final start, :final end):
          final a = offsetOf(start);
          final b = offsetOf(end);
          if ((a - p).distance <= touchSlop) {
            return (index: i, part: DrawingPart.start);
          }
          if ((b - p).distance <= touchSlop) {
            return (index: i, part: DrawingPart.end);
          }
          if (_distanceToSegment(p, a, b) <= touchSlop) {
            return (index: i, part: DrawingPart.body);
          }
      }
    }
    return null;
  }

  /// Fractional candle position of [time]: between two candles it
  /// interpolates, past either end it extrapolates by the nearest spacing.
  double _logicalOf(DateTime time) {
    final ms = time.millisecondsSinceEpoch;
    final n = candles.length;
    final first = _ms(0);
    final last = _ms(n - 1);
    if (ms <= first) return (ms - first) / (_ms(1) - first);
    if (ms >= last) return n - 1 + (ms - last) / (last - _ms(n - 2));
    var lo = 0;
    var hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_ms(mid) <= ms) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo + (ms - _ms(lo)) / (_ms(hi) - _ms(lo));
  }

  /// Inverse of [_logicalOf].
  DateTime _timeOf(double logical) {
    final n = candles.length;
    final int lo;
    if (logical <= 0) {
      lo = 0;
    } else if (logical >= n - 1) {
      lo = n - 2;
    } else {
      lo = logical.floor();
    }
    final ms = _ms(lo) + (logical - lo) * (_ms(lo + 1) - _ms(lo));
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }

  int _ms(int index) => candles[index].openTime.millisecondsSinceEpoch;

  /// Shortest distance from [p] to the segment from [a] to [b]: to the
  /// nearest point on the line, or to an end if [p] lies beyond it.
  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.distanceSquared;
    if (lengthSquared == 0) return (p - a).distance;
    final t =
        (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared)
            .clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// The drawings on a chart, the tool being placed and the selection, kept
/// outside the chart widget so they survive it being rebuilt (e.g. on an
/// interval change). Painters listen to it like they do to the scales.
class DrawingController extends ChangeNotifier {
  List<Drawing> _drawings = const [];
  DrawingTool? _tool;
  Drawing? _draft;
  int? _selected;

  /// Placed drawings, oldest first; later ones paint on top and are hit
  /// first. Replaced, never mutated, on every change.
  List<Drawing> get drawings => _drawings;

  /// The tool the next tap or drag places; null when panning as usual.
  DrawingTool? get tool => _tool;

  /// A drawing still being placed: a trend line's first point after one
  /// tap, or whatever is under the finger while dragging one out.
  Drawing? get draft => _draft;

  /// Index into [drawings] of the selected drawing, which shows its handles
  /// and can be dragged or deleted; null when none is.
  int? get selectedIndex => _selected;

  /// Picks [tool], or puts it down if it is already picked.
  void selectTool(DrawingTool? tool) {
    _tool = tool == _tool ? null : tool;
    _draft = null;
    _selected = null;
    ChartLog.info('draw', 'tool ${_tool?.name ?? 'none'}');
    notifyListeners();
  }

  /// Shows [draft] as the drawing being placed, or clears it with null.
  void setDraft(Drawing? draft) {
    if (draft == _draft) return;
    _draft = draft;
    notifyListeners();
  }

  /// Adds [drawing], selected, and puts the tool down.
  void add(Drawing drawing) {
    _drawings = List.unmodifiable([..._drawings, drawing]);
    _tool = null;
    _draft = null;
    _selected = _drawings.length - 1;
    ChartLog.info('draw', 'added $drawing');
    notifyListeners();
  }

  /// Swaps the drawing at [index] for [drawing], e.g. while it is dragged;
  /// the selection stays on it.
  void replace(int index, Drawing drawing) {
    _drawings = List.unmodifiable([..._drawings]..[index] = drawing);
    notifyListeners();
  }

  /// Selects the drawing at [index], or clears the selection with null.
  void select(int? index) {
    if (index == _selected) return;
    _selected = index;
    ChartLog.info(
      'draw',
      index == null ? 'selection cleared' : 'selected ${_drawings[index]}',
    );
    notifyListeners();
  }

  /// Removes the selected drawing, if any; nothing is selected afterwards.
  void deleteSelected() {
    final index = _selected;
    if (index == null) return;
    ChartLog.info('draw', 'deleted ${_drawings[index]}');
    _drawings = List.unmodifiable([..._drawings]..removeAt(index));
    _selected = null;
    notifyListeners();
  }

  /// Removes every drawing and any draft. The picked tool stays picked.
  void clear() {
    if (_drawings.isEmpty && _draft == null) return;
    _drawings = const [];
    _draft = null;
    _selected = null;
    ChartLog.info('draw', 'cleared all');
    notifyListeners();
  }
}

/// Moves one part of [drawing] by the finger's travel in time and price.
Drawing dragDrawing(
  Drawing drawing,
  DrawingPart part,
  Duration dt,
  double dPrice,
) => switch ((drawing, part)) {
  (TrendLine(:final start, :final end), DrawingPart.start) => TrendLine(
    start.shift(dt, dPrice),
    end,
  ),
  (TrendLine(:final start, :final end), DrawingPart.end) => TrendLine(
    start,
    end.shift(dt, dPrice),
  ),
  _ => drawing.moveBy(dt, dPrice),
};
