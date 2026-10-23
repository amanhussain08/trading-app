import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/candle.dart';
import '../chart_log.dart';
import '../scale/price_scale.dart';
import '../scale/time_scale.dart';
import 'candle_chart.dart';

const _axisLineColor = Color(0x3D000000);
const _labelStyle = TextStyle(color: Colors.black54, fontSize: 11);
const _tickLength = 4.0;

// ---------------------------------------------------------------------------
// Price axis (y)
// ---------------------------------------------------------------------------

/// Price levels to label on an axis, and how many decimals to print them
/// with so every label has the same precision.
class PriceTicks {
  const PriceTicks({required this.values, required this.decimals});

  /// Levels from low to high, all multiples of the same round step.
  final List<double> values;

  /// Decimals the step needs: 0 for a step of 5, 2 for 0.05.
  final int decimals;
}

/// Round price levels between [low] and [high], at most about [maxTicks] of
/// them, spaced by 1, 2 or 5 times a power of ten.
PriceTicks priceTicks(double low, double high, {required int maxTicks}) {
  if (high <= low || maxTicks < 1) return const PriceTicks(values: [], decimals: 0);

  final raw = (high - low) / maxTicks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final residual = raw / magnitude;
  final step = magnitude *
      (residual <= 1
          ? 1
          : residual <= 2
              ? 2
              : residual <= 5
                  ? 5
                  : 10);

  final first = (low / step).ceil();
  final last = (high / step).floor();
  return PriceTicks(
    values: [for (var i = first; i <= last; i++) i * step],
    decimals: math.max(0, -(math.log(step) / math.ln10).floor()),
  );
}

/// Labels [priceScale]'s range; sits to the right of the candles.
///
/// Dragging it down compresses the candles, dragging up stretches them;
/// double-tap returns to auto-scale.
class PriceAxis extends StatelessWidget {
  const PriceAxis({
    super.key,
    required this.candles,
    required this.timeScale,
    required this.priceScale,
  });

  final List<Candle> candles;
  final TimeScale timeScale;
  final PriceScale priceScale;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: CandleChart.touchDevices,
      onVerticalDragStart: (_) => ChartLog.info('input', 'price axis drag: scaling prices'),
      onVerticalDragUpdate: (details) =>
          priceScale.scaleBy(math.exp(details.delta.dy / 200)),
      onDoubleTap: () {
        ChartLog.info('input', 'price axis double-tap: autoscale');
        priceScale.resetAutoScale();
      },
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _PriceAxisPainter(candles, timeScale, priceScale),
        ),
      ),
    );
  }
}

/// Top of a [labelHeight]-tall label centred on [y], kept inside [height] so
/// a price above or below the visible range stays pinned to that edge.
double pinnedLabelTop({required double y, required double labelHeight, required double height}) =>
    (y - labelHeight / 2).clamp(0.0, math.max(0.0, height - labelHeight));

/// Draws the price axis: the axis line, a tick and label for each round
/// price level, and the newest close in a green or red tag. Labels that
/// would overlap the tag, or fall off the axis, are skipped.
class _PriceAxisPainter extends CustomPainter {
  _PriceAxisPainter(this.candles, this.timeScale, this.priceScale)
      : super(repaint: Listenable.merge([timeScale, priceScale]));

  final List<Candle> candles;
  final TimeScale timeScale;
  final PriceScale priceScale;

  static const _upColor = Color(0xFF26A69A);
  static const _downColor = Color(0xFFEF5350);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = _axisLineColor;
    canvas.drawLine(const Offset(0.5, 0), Offset(0.5, size.height), line);
    final range = priceScale.range(candles, timeScale);
    if (range.isEmpty) return;

    double y(double price) => range.priceToY(price, size.height);
    final ticks = priceTicks(range.low, range.high, maxTicks: (size.height / 40).floor());

    // The newest candle's close is tagged on the axis as the live price.
    final last = candles.isEmpty ? null : candles.last;
    TextPainter? tag;
    var tagTop = 0.0;
    if (last != null) {
      tag = TextPainter(
        text: TextSpan(
          text: last.close.toStringAsFixed(math.max(ticks.decimals, 2)),
          style: _labelStyle.copyWith(color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tagTop = pinnedLabelTop(y: y(last.close), labelHeight: tag.height + 4, height: size.height);
    }

    for (final price in ticks.values) {
      final tickY = y(price);
      final label = TextPainter(
        text: TextSpan(text: price.toStringAsFixed(ticks.decimals), style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final top = tickY - label.height / 2;
      final underTag =
          tag != null && top < tagTop + tag.height + 4 && top + label.height > tagTop;
      if (top >= 0 && top + label.height <= size.height && !underTag) {
        canvas.drawLine(Offset(0, tickY), Offset(_tickLength, tickY), line);
        label.paint(canvas, Offset(_tickLength + 4, top));
      }
      label.dispose();
    }

    if (last != null && tag != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, tagTop, size.width - 1, tag.height + 4),
          const Radius.circular(2),
        ),
        Paint()..color = last.isUp ? _upColor : _downColor,
      );
      tag.paint(canvas, Offset(_tickLength + 4, tagTop + 2));
      tag.dispose();
    }
  }

  @override
  bool shouldRepaint(_PriceAxisPainter old) =>
      !identical(old.candles, candles) ||
      old.timeScale != timeScale ||
      old.priceScale != priceScale;
}

// ---------------------------------------------------------------------------
// Volume axis
// ---------------------------------------------------------------------------

/// The volume pane's top edge is this many times the largest visible volume,
/// so the tallest bar leaves a gap below the price pane.
const volumeHeadroom = 1.15;

/// Compact volume label: `950`, `1.23K`, `45.6M`, `7B`.
String formatVolume(double volume) {
  String withSuffix(double value, String suffix) {
    final decimals = value < 10
        ? 2
        : value < 100
            ? 1
            : 0;
    return '${value.toStringAsFixed(decimals)}$suffix';
  }

  final abs = volume.abs();
  if (abs >= 1e9) return withSuffix(volume / 1e9, 'B');
  if (abs >= 1e6) return withSuffix(volume / 1e6, 'M');
  if (abs >= 1e3) return withSuffix(volume / 1e3, 'K');
  return withSuffix(volume, '');
}

/// Labels the volume pane; sits under [PriceAxis].
class VolumeAxis extends StatelessWidget {
  const VolumeAxis({
    super.key,
    required this.candles,
    required this.timeScale,
    required this.priceScale,
  });

  final List<Candle> candles;
  final TimeScale timeScale;
  final PriceScale priceScale;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _VolumeAxisPainter(candles, timeScale, priceScale),
      ),
    );
  }
}

/// Draws round volume levels from 0 up to the volume pane's top
/// ([volumeHeadroom] above the largest visible volume), in compact form.
/// Repaints on pan and zoom, since they change which volumes are visible.
class _VolumeAxisPainter extends CustomPainter {
  _VolumeAxisPainter(this.candles, this.timeScale, this.priceScale)
      : super(repaint: timeScale);

  final List<Candle> candles;
  final TimeScale timeScale;
  final PriceScale priceScale;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = _axisLineColor;
    canvas
      ..drawLine(const Offset(0.5, 0), Offset(0.5, size.height), line)
      ..drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), line);
    final volumeMax = priceScale.volumeMax(candles, timeScale);
    if (volumeMax <= 0) return;

    final top = volumeMax * volumeHeadroom;
    final ticks = priceTicks(0, top, maxTicks: math.max(1, (size.height / 30).floor()));
    for (final volume in ticks.values) {
      if (volume == 0) continue;
      final y = size.height - volume / top * size.height;
      final label = TextPainter(
        text: TextSpan(text: formatVolume(volume), style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTop = y - label.height / 2;
      if (labelTop >= 0 && labelTop + label.height <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(_tickLength, y), line);
        label.paint(canvas, Offset(_tickLength + 4, labelTop));
      }
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_VolumeAxisPainter old) =>
      !identical(old.candles, candles) ||
      old.timeScale != timeScale ||
      old.priceScale != priceScale;
}

// ---------------------------------------------------------------------------
// Time axis (x)
// ---------------------------------------------------------------------------

/// Label spacings the time axis can use, smallest first; [timeStepMinutes]
/// picks the first that leaves room between labels.
const _timeStepsMinutes = [
  1, 5, 15, 30, 60, 120, 240, 360, 720, // up to 12h
  1440, 2880, 10080, 20160, 43200, 129600, 525600, // 1d .. 1y
];

/// Smallest time step (in minutes) that keeps labels at least
/// [minLabelSpacing] pixels apart for candles of [interval] drawn
/// [candleWidth] pixels wide.
int timeStepMinutes({
  required Duration interval,
  required double candleWidth,
  double minLabelSpacing = 80,
}) {
  final candleMinutes = math.max(1, interval.inMinutes);
  for (final step in _timeStepsMinutes) {
    if (step >= candleMinutes && step / candleMinutes * candleWidth >= minLabelSpacing) {
      return step;
    }
  }
  return _timeStepsMinutes.last;
}

/// Minutes since the epoch in local time, so labels fall on local hours and
/// midnights rather than UTC ones.
int _localEpochMinutes(DateTime time) =>
    (time.millisecondsSinceEpoch + time.toLocal().timeZoneOffset.inMilliseconds) ~/ 60000;

/// Whether candle [index] is the first one in a new [stepMinutes] bucket of
/// local time, i.e. where a time-axis label belongs. [index] may be past the
/// newest candle; see [candleTimeAt].
bool isTimeTick(List<Candle> candles, int index, int stepMinutes) {
  if (index <= 0 || candles.length < 2) return false;
  return _localEpochMinutes(candleTimeAt(candles, index)) ~/ stepMinutes !=
      _localEpochMinutes(candleTimeAt(candles, index - 1)) ~/ stepMinutes;
}

/// Open time of candle [index] in [candles] (oldest first, at least two).
/// Past the newest candle, where the chart shows empty space, times continue
/// at the latest interval: by calendar month for monthly candles, since
/// months differ in length.
DateTime candleTimeAt(List<Candle> candles, int index) {
  final n = candles.length;
  if (index < n) return candles[index].openTime;
  final last = candles[n - 1].openTime;
  final ahead = index - (n - 1);
  final interval = last.difference(candles[n - 2].openTime);
  if (interval >= const Duration(days: 28)) {
    return DateTime.utc(last.year, last.month + ahead, last.day, last.hour, last.minute);
  }
  return last.add(interval * ahead);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `2026` at a new year, `21 Oct` at a new day, otherwise `14:30` (local time).
String timeLabel(DateTime previous, DateTime current) {
  final p = previous.toLocal();
  final c = current.toLocal();
  if (c.year != p.year) return '${c.year}';
  if (c.month != p.month || c.day != p.day) return '${c.day} ${_months[c.month - 1]}';
  return '${c.hour.toString().padLeft(2, '0')}:${c.minute.toString().padLeft(2, '0')}';
}

/// Full local time of a candle for the crosshair: `22 Oct 2026 14:30`, or
/// just the date for daily and longer candles.
String crosshairTimeLabel(DateTime time, Duration interval) {
  final t = time.toLocal();
  final date = '${t.day} ${_months[t.month - 1]} ${t.year}';
  if (interval >= const Duration(days: 1)) return date;
  return '$date ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Labels candle times under the candle pane at [timeScale]'s positions,
/// including the empty slots past the newest candle; repaints whenever the
/// time scale pans or zooms.
class TimeAxisPainter extends CustomPainter {
  TimeAxisPainter({required this.candles, required this.timeScale})
      : super(repaint: timeScale);

  final List<Candle> candles;
  final TimeScale timeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = _axisLineColor;
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), line);
    final slots = timeScale.visibleSlots;
    if (candles.length < 2 || size.isEmpty || slots == null) return;

    final candleWidth = timeScale.barSpacing;
    final step = timeStepMinutes(
      interval: candles[1].openTime.difference(candles[0].openTime),
      candleWidth: candleWidth,
    );

    // A few extra slots each side keep edge labels whole.
    final margin = (60 / candleWidth).ceil();
    final from = math.max(1, slots.$1 - margin);
    final to = slots.$2 + margin;

    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    for (var i = from; i <= to; i++) {
      if (!isTimeTick(candles, i, step)) continue;

      final x = timeScale.indexToX(i);
      final label = TextPainter(
        text: TextSpan(
          text: timeLabel(candleTimeAt(candles, i - 1), candleTimeAt(candles, i)),
          style: _labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.drawLine(Offset(x, 0), Offset(x, _tickLength), line);
      label.paint(canvas, Offset(x - label.width / 2, _tickLength + 2));
      label.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TimeAxisPainter old) =>
      !identical(old.candles, candles) || old.timeScale != timeScale;
}
