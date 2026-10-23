import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/candle.dart';
import '../chart_log.dart';
import '../scale/price_scale.dart';
import '../scale/time_scale.dart';
import 'chart_axes.dart';

/// Body width in device pixels for candles [barSpacing] logical pixels
/// apart, from Lightweight Charts' `optimalCandlestickWidth`: nearly the
/// whole slot when zoomed out, tapering to 80% of it when zoomed in.
int optimalCandleWidth(double barSpacing, double pixelRatio) {
  if (barSpacing >= 2.5 && barSpacing <= 4) return (3 * pixelRatio).floor();
  final coeff =
      1 - 0.2 * math.atan(math.max(4.0, barSpacing) - 4) / (math.pi * 0.5);
  final width = math.min(
    (barSpacing * coeff * pixelRatio).floor(),
    (barSpacing * pixelRatio).floor(),
  );
  return math.max(pixelRatio.floor(), width);
}

/// Draws the candle pane: candles on top, volume bars below, the dashed
/// last-price line and the separator between them. One painter loops over
/// the visible candles only, and repaints straight from [timeScale] and
/// [priceScale] (pan, zoom, price drag) without rebuilding any widget.
class CandlePanePainter extends CustomPainter {
  CandlePanePainter({
    required this.candles,
    required this.timeScale,
    required this.priceScale,
    required this.devicePixelRatio,
    required this.pricePaneFraction,
  }) : super(repaint: Listenable.merge([timeScale, priceScale]));

  final List<Candle> candles;
  final TimeScale timeScale;
  final PriceScale priceScale;
  final double devicePixelRatio;

  /// Share of the height taken by candles; volume gets the rest.
  final double pricePaneFraction;

  static const _upColor = Color(0xFF26A69A);
  static const _downColor = Color(0xFFEF5350);
  static const _upVolumeColor = Color(0x8026A69A);
  static const _downVolumeColor = Color(0x80EF5350);
  static const _upLineColor = Color(0xCC26A69A);
  static const _downLineColor = Color(0xCCEF5350);
  static const _separatorColor = Color(0x1F000000);
  static const _dash = 4.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final priceHeight = size.height * pricePaneFraction;
    final volumeHeight = size.height - priceHeight;
    canvas.drawLine(
      Offset(0, priceHeight + 0.5),
      Offset(size.width, priceHeight + 0.5),
      Paint()..color = _separatorColor,
    );

    final visible = timeScale.visibleRange;
    if (candles.isEmpty || visible == null || size.isEmpty) return;
    final range = priceScale.range(candles, timeScale);
    if (range.isEmpty) return;
    final volumeMax = priceScale.volumeMax(candles, timeScale);

    final dpr = devicePixelRatio;
    double snap(double v) => (v * dpr).roundToDouble() / dpr;

    // Body and wick widths in device pixels. Bodies take the wick's parity
    // (odd/even) so the wick, like the crosshair, sits exactly centred.
    var bodyPx = optimalCandleWidth(timeScale.barSpacing, dpr);
    final wickPx = math.max(1, math.min(dpr.floor(), bodyPx));
    if (bodyPx >= 2 && bodyPx % 2 != wickPx % 2) bodyPx--;
    final bodyWidth = bodyPx / dpr;
    final wickWidth = wickPx / dpr;

    final up = Path();
    final down = Path();
    final upVolume = Path();
    final downVolume = Path();
    final (from, to) = visible;
    final last = math.min(to, candles.length - 1);
    for (var i = from; i <= last; i++) {
      final candle = candles[i];
      final centerPx = (timeScale.indexToX(i) * dpr).roundToDouble();
      final bodyLeft = (centerPx - bodyPx ~/ 2) / dpr;
      final wickLeft = (centerPx - wickPx ~/ 2) / dpr;

      final high = snap(range.priceToY(candle.high, priceHeight));
      final low = snap(range.priceToY(candle.low, priceHeight));
      final top = snap(range.priceToY(math.max(candle.open, candle.close), priceHeight));
      final bottom = math.max(
        snap(range.priceToY(math.min(candle.open, candle.close), priceHeight)),
        top + 1 / dpr,
      );

      (candle.isUp ? up : down)
        ..addRect(Rect.fromLTWH(wickLeft, high, wickWidth, low - high))
        ..addRect(Rect.fromLTRB(bodyLeft, top, bodyLeft + bodyWidth, bottom));

      if (volumeMax > 0) {
        final barHeight =
            candle.volume / (volumeMax * volumeHeadroom) * volumeHeight;
        final barTop = snap(size.height - barHeight);
        (candle.isUp ? upVolume : downVolume).addRect(
          Rect.fromLTRB(bodyLeft, barTop, bodyLeft + bodyWidth, size.height),
        );
      }
    }

    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawPath(upVolume, Paint()..color = _upVolumeColor)
      ..drawPath(downVolume, Paint()..color = _downVolumeColor)
      ..drawPath(up, Paint()..color = _upColor)
      ..drawPath(down, Paint()..color = _downColor);
    _paintLastPriceLine(canvas, size.width, priceHeight, range);
    canvas.restore();

    ChartLog.frame(
      'paint',
      'pane ${last - from + 1} candles $from..$last '
          'barSpacing=${timeScale.barSpacing.toStringAsFixed(2)} '
          'body=${bodyPx}px@${dpr}x $range',
    );
  }

  /// Dashed line at the newest close, lining up with the price axis tag.
  /// Hidden while that price is outside the visible range.
  void _paintLastPriceLine(
    Canvas canvas,
    double width,
    double height,
    PriceRange range,
  ) {
    final last = candles.last;
    final y = range.priceToY(last.close, height);
    if (y < 0 || y > height) return;
    final paint = Paint()
      ..color = last.isUp ? _upLineColor : _downLineColor
      ..strokeWidth = 1;
    for (var x = 0.0; x < width; x += _dash + _gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + _dash, width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CandlePanePainter old) =>
      !identical(old.candles, candles) ||
      old.timeScale != timeScale ||
      old.priceScale != priceScale ||
      old.devicePixelRatio != devicePixelRatio ||
      old.pricePaneFraction != pricePaneFraction;
}
