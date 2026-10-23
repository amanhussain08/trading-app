import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/candle.dart';
import '../bloc/chart_bloc.dart';
import '../chart_log.dart';
import '../scale/price_scale.dart';
import '../scale/time_scale.dart';
import 'candle_chart.dart';
import 'chart_axes.dart';

/// Crosshair over the whole [CandleChart] (candles, price axis and time
/// axis): dashed lines through [point], snapped across to the candle under
/// it, the price (or volume) and time under the pointer tagged on the axes,
/// and that candle's open/high/low/close in the top-left corner.
///
/// [point] is in the candle pane's coordinates, which share their origin
/// with the chart. Repaints straight from [point], [timeScale] and
/// [priceScale] without rebuilding, and only this layer: the candles
/// underneath are not repainted when the crosshair moves.
class CrosshairLayer extends StatelessWidget {
  const CrosshairLayer({
    super.key,
    required this.point,
    required this.timeScale,
    required this.priceScale,
  });

  final ValueListenable<Offset?> point;
  final TimeScale timeScale;
  final PriceScale priceScale;

  @override
  Widget build(BuildContext context) {
    final candles = context.select((ChartBloc bloc) => bloc.state.candles);
    return CustomPaint(
      size: Size.infinite,
      painter: _CrosshairPainter(
        point: point,
        timeScale: timeScale,
        priceScale: priceScale,
        candles: candles,
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({
    required this.point,
    required this.timeScale,
    required this.priceScale,
    required this.candles,
  }) : super(repaint: Listenable.merge([point, timeScale, priceScale]));

  final ValueListenable<Offset?> point;
  final TimeScale timeScale;
  final PriceScale priceScale;
  final List<Candle> candles;

  static const _lineColor = Color(0xFF9598A1);
  static const _tagColor = Color(0xFF363A45);
  static const _upColor = Color(0xFF26A69A);
  static const _downColor = Color(0xFFEF5350);
  static const _tagStyle = TextStyle(color: Colors.white, fontSize: 11);
  static const _legendLabelStyle = TextStyle(
    color: Colors.black54,
    fontSize: 12,
  );
  static const _dash = 4.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final p = point.value;
    final listWidth = size.width - CandleChart.priceAxisWidth;
    final listHeight = size.height - CandleChart.timeAxisHeight;
    if (p == null ||
        candles.isEmpty ||
        timeScale.isEmpty ||
        listWidth <= 0 ||
        listHeight <= 0 ||
        p.dx < 0 ||
        p.dx > listWidth ||
        p.dy < 0 ||
        p.dy > listHeight) {
      return;
    }

    // Snap across to the centre of the candle slot under the pointer.
    final n = candles.length;
    final index = timeScale.xToIndex(p.dx);
    if (index < 0) return;
    final x = timeScale.indexToX(index);
    final range = priceScale.range(candles, timeScale);
    final volumeMax = priceScale.volumeMax(candles, timeScale);

    final line = Paint()
      ..color = _lineColor
      ..strokeWidth = 1;
    _dashed(canvas, Offset(x, 0), Offset(x, listHeight), line);
    _dashed(canvas, Offset(0, p.dy), Offset(listWidth, p.dy), line);

    final pricePaneHeight =
        listHeight *
        CandleChart.pricePaneFlex /
        (CandleChart.pricePaneFlex + CandleChart.volumePaneFlex);
    final valueText = p.dy <= pricePaneHeight
        ? _priceAt(range, p.dy, pricePaneHeight)
        : _volumeAt(volumeMax, p.dy, pricePaneHeight, listHeight);
    ChartLog.frame(
      'crosshair',
      'x=${p.dx.toStringAsFixed(0)} y=${p.dy.toStringAsFixed(0)} -> candle $index, $valueText',
    );
    if (valueText != null) {
      final tag = _text(valueText, _tagStyle);
      final tagHeight = tag.height + 4;
      final top = pinnedLabelTop(
        y: p.dy,
        labelHeight: tagHeight,
        height: listHeight,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          listWidth + 1,
          top,
          CandleChart.priceAxisWidth - 1,
          tagHeight,
        ),
        Paint()..color = _tagColor,
      );
      tag.paint(canvas, Offset(listWidth + 8, top + 2));
      tag.dispose();
    }

    final time = _timeAt(index);
    if (time != null) {
      final tag = _text(crosshairTimeLabel(time, _interval!), _tagStyle);
      final tagWidth = tag.width + 12;
      final left = (x - tagWidth / 2)
          .clamp(0.0, math.max(0.0, listWidth - tagWidth))
          .toDouble();
      canvas.drawRect(
        Rect.fromLTWH(
          left,
          listHeight + 1,
          tagWidth,
          CandleChart.timeAxisHeight - 1,
        ),
        Paint()..color = _tagColor,
      );
      tag.paint(
        canvas,
        Offset(
          left + 6,
          listHeight + (CandleChart.timeAxisHeight - tag.height) / 2,
        ),
      );
      tag.dispose();
    }

    if (index < n) {
      _paintLegend(canvas, candles[index], range, pricePaneHeight);
    }
  }

  /// The price at [y], with at least the decimals the price axis uses.
  String? _priceAt(PriceRange range, double y, double paneHeight) {
    if (range.isEmpty || paneHeight <= 0) return null;
    final price = range.yToPrice(y, paneHeight);
    final ticks = priceTicks(
      range.low,
      range.high,
      maxTicks: (paneHeight / 40).floor(),
    );
    return price.toStringAsFixed(math.max(ticks.decimals, 2));
  }

  String? _volumeAt(
    double volumeMax,
    double y,
    double pricePaneHeight,
    double listHeight,
  ) {
    final paneHeight = listHeight - pricePaneHeight;
    if (volumeMax <= 0 || paneHeight <= 0) return null;
    final volume = (listHeight - y) / paneHeight * volumeMax * volumeHeadroom;
    return formatVolume(math.max(0.0, volume));
  }

  Duration? get _interval => candles.length < 2
      ? null
      : candles.last.openTime.difference(candles[candles.length - 2].openTime);

  DateTime? _timeAt(int index) =>
      candles.length < 2 ? null : candleTimeAt(candles, index);

  void _paintLegend(
    Canvas canvas,
    Candle candle,
    PriceRange range,
    double paneHeight,
  ) {
    final ticks = priceTicks(
      range.low,
      range.high,
      maxTicks: math.max(1, (paneHeight / 40).floor()),
    );
    final decimals = math.max(ticks.decimals, 2);
    final valueStyle = _legendLabelStyle.copyWith(
      color: candle.isUp ? _upColor : _downColor,
    );
    final legend = TextPainter(
      text: TextSpan(
        children: [
          for (final (label, value) in [
            ('O', candle.open),
            ('H', candle.high),
            ('L', candle.low),
            ('C', candle.close),
          ]) ...[
            TextSpan(text: '$label ', style: _legendLabelStyle),
            TextSpan(
              text: '${value.toStringAsFixed(decimals)}  ',
              style: valueStyle,
            ),
          ],
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    legend.paint(canvas, const Offset(8, 6));
    legend.dispose();
  }

  static TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  static void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    final length = (to - from).distance;
    if (length <= 0) return;
    final direction = (to - from) / length;
    for (var d = 0.0; d < length; d += _dash + _gap) {
      canvas.drawLine(
        from + direction * d,
        from + direction * math.min(d + _dash, length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) =>
      old.point != point ||
      old.timeScale != timeScale ||
      old.priceScale != priceScale ||
      !identical(old.candles, candles);
}
