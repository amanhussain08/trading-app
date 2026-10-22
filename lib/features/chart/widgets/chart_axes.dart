import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/candle.dart';
import '../bloc/chart_bloc.dart';

const _axisLineColor = Color(0x3DFFFFFF);
const _labelStyle = TextStyle(color: Colors.white60, fontSize: 11);
const _tickLength = 4.0;

// ---------------------------------------------------------------------------
// Price axis (y)
// ---------------------------------------------------------------------------

class PriceTicks {
  const PriceTicks({required this.values, required this.decimals});

  final List<double> values;
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

/// Labels the visible price range of [ChartBloc]; sits to the right of the candles.
///
/// Dragging it down compresses the candles, dragging up stretches them;
/// double-tap returns to auto-scale.
class PriceAxis extends StatelessWidget {
  const PriceAxis({super.key});

  @override
  Widget build(BuildContext context) {
    final (low, high) = context.select(
      (ChartBloc bloc) => (bloc.state.priceLow, bloc.state.priceHigh),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) =>
          context.read<ChartBloc>().add(ChartPriceScaled(math.exp(details.delta.dy / 200))),
      onDoubleTap: () => context.read<ChartBloc>().add(const ChartAutoScaleReset()),
      child: CustomPaint(size: Size.infinite, painter: _PriceAxisPainter(low, high)),
    );
  }
}

class _PriceAxisPainter extends CustomPainter {
  _PriceAxisPainter(this.priceLow, this.priceHigh);

  final double priceLow;
  final double priceHigh;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = _axisLineColor;
    canvas.drawLine(const Offset(0.5, 0), Offset(0.5, size.height), line);
    if (priceHigh <= priceLow) return;

    final ticks = priceTicks(priceLow, priceHigh, maxTicks: (size.height / 40).floor());
    for (final price in ticks.values) {
      final y = (priceHigh - price) / (priceHigh - priceLow) * size.height;
      final label = TextPainter(
        text: TextSpan(text: price.toStringAsFixed(ticks.decimals), style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final top = y - label.height / 2;
      if (top >= 0 && top + label.height <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(_tickLength, y), line);
        label.paint(canvas, Offset(_tickLength + 4, top));
      }
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_PriceAxisPainter old) =>
      old.priceLow != priceLow || old.priceHigh != priceHigh;
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

/// Labels the volume pane of [ChartBloc]; sits under [PriceAxis].
class VolumeAxis extends StatelessWidget {
  const VolumeAxis({super.key});

  @override
  Widget build(BuildContext context) {
    final volumeMax = context.select((ChartBloc bloc) => bloc.state.volumeMax);
    return CustomPaint(size: Size.infinite, painter: _VolumeAxisPainter(volumeMax));
  }
}

class _VolumeAxisPainter extends CustomPainter {
  _VolumeAxisPainter(this.volumeMax);

  final double volumeMax;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = _axisLineColor;
    canvas
      ..drawLine(const Offset(0.5, 0), Offset(0.5, size.height), line)
      ..drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), line);
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
  bool shouldRepaint(_VolumeAxisPainter old) => old.volumeMax != volumeMax;
}

// ---------------------------------------------------------------------------
// Time axis (x)
// ---------------------------------------------------------------------------

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

int _localEpochMinutes(DateTime time) =>
    (time.millisecondsSinceEpoch + time.toLocal().timeZoneOffset.inMilliseconds) ~/ 60000;

/// Whether candle [index] is the first one in a new [stepMinutes] bucket of
/// local time, i.e. where a time-axis label belongs.
bool isTimeTick(List<Candle> candles, int index, int stepMinutes) {
  if (index <= 0 || index >= candles.length) return false;
  return _localEpochMinutes(candles[index].openTime) ~/ stepMinutes !=
      _localEpochMinutes(candles[index - 1].openTime) ~/ stepMinutes;
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

/// Labels candle times under a reversed horizontal candle [ListView]; repaints
/// on every scroll tick of [scrollController] so labels move with the candles.
class TimeAxisPainter extends CustomPainter {
  TimeAxisPainter({
    required this.candles,
    required this.visibleCount,
    required this.scrollController,
  }) : super(repaint: scrollController);

  final List<Candle> candles;
  final double visibleCount;
  final ScrollController scrollController;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = _axisLineColor;
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), line);
    if (candles.length < 2 || size.isEmpty) return;

    final candleWidth = size.width / visibleCount;
    final pixels = scrollController.hasClients ? scrollController.offset : 0.0;
    final step = timeStepMinutes(
      interval: candles[1].openTime.difference(candles[0].openTime),
      candleWidth: candleWidth,
    );

    // Same mapping as the candle list: list item k is candle (n - 1 - k), and
    // item 0 sits at the right edge. A few extra items keep edge labels whole.
    final n = candles.length;
    final margin = (60 / candleWidth).ceil();
    final firstItem = math.max(0, (pixels / candleWidth).floor() - margin);
    final lastItem = math.min(n - 1, ((pixels + size.width) / candleWidth).ceil() + margin);

    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    for (var k = firstItem; k <= lastItem; k++) {
      final i = n - 1 - k;
      if (!isTimeTick(candles, i, step)) continue;

      final x = size.width - (k + 0.5) * candleWidth + pixels;
      final label = TextPainter(
        text: TextSpan(
          text: timeLabel(candles[i - 1].openTime, candles[i].openTime),
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
      !identical(old.candles, candles) ||
      old.visibleCount != visibleCount ||
      old.scrollController != scrollController;
}
