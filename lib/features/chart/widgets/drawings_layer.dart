import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/candle.dart';
import '../bloc/chart_bloc.dart';
import '../drawing/drawings.dart';
import '../scale/price_scale.dart';
import '../scale/time_scale.dart';
import 'candle_chart.dart';
import 'chart_axes.dart';

/// The user's horizontal and trend lines over the whole [CandleChart]: lines
/// clipped to the price pane, and each horizontal line's price tagged on the
/// price axis. Repaints from [controller] and the scales without rebuilding,
/// in its own layer above the candles and below the crosshair.
class DrawingsLayer extends StatelessWidget {
  const DrawingsLayer({
    super.key,
    required this.controller,
    required this.timeScale,
    required this.priceScale,
  });

  final DrawingController controller;
  final TimeScale timeScale;
  final PriceScale priceScale;

  static const color = Color(0xFF2962FF);

  @override
  Widget build(BuildContext context) {
    final candles = context.select((ChartBloc bloc) => bloc.state.candles);
    return CustomPaint(
      size: Size.infinite,
      painter: _DrawingsPainter(
        controller: controller,
        timeScale: timeScale,
        priceScale: priceScale,
        candles: candles,
      ),
    );
  }
}

/// Paints every drawing, then the draft on top, then the price tags. Lines
/// are clipped to the price pane so they never run over the volume bars or
/// the axes; the selected drawing and the draft are thicker, with handles.
class _DrawingsPainter extends CustomPainter {
  _DrawingsPainter({
    required this.controller,
    required this.timeScale,
    required this.priceScale,
    required this.candles,
  }) : super(repaint: Listenable.merge([controller, timeScale, priceScale]));

  final DrawingController controller;
  final TimeScale timeScale;
  final PriceScale priceScale;
  final List<Candle> candles;

  static const _tagStyle = TextStyle(color: Colors.white, fontSize: 11);
  static const _handleRadius = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final drawings = controller.drawings;
    final draft = controller.draft;
    if (drawings.isEmpty && draft == null) return;

    final listWidth = size.width - CandleChart.priceAxisWidth;
    final listHeight = size.height - CandleChart.timeAxisHeight;
    if (listWidth <= 0 || listHeight <= 0) return;
    final pricePaneHeight = listHeight * CandleChart.pricePaneFraction;
    final geometry = DrawingGeometry(
      candles: candles,
      timeScale: timeScale,
      range: priceScale.range(candles, timeScale),
      pricePaneHeight: pricePaneHeight,
    );
    if (geometry.isEmpty) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, listWidth, pricePaneHeight));
    for (var i = 0; i < drawings.length; i++) {
      _paintDrawing(
        canvas,
        geometry,
        drawings[i],
        listWidth,
        selected: i == controller.selectedIndex,
      );
    }
    if (draft != null) {
      _paintDrawing(canvas, geometry, draft, listWidth, selected: true);
    }
    canvas.restore();

    for (final drawing in [...drawings, ?draft]) {
      if (drawing is HorizontalLine) {
        _paintPriceTag(canvas, geometry, drawing.price, listWidth);
      }
    }
  }

  void _paintDrawing(
    Canvas canvas,
    DrawingGeometry geometry,
    Drawing drawing,
    double listWidth, {
    required bool selected,
  }) {
    final line = Paint()
      ..color = DrawingsLayer.color
      ..strokeWidth = selected ? 2 : 1.5
      ..strokeCap = StrokeCap.round;
    switch (drawing) {
      case HorizontalLine(:final price):
        final y = geometry.yOf(price);
        canvas.drawLine(Offset(0, y), Offset(listWidth, y), line);
        if (selected) _paintHandle(canvas, Offset(listWidth / 2, y));
      case TrendLine(:final start, :final end):
        final a = geometry.offsetOf(start);
        final b = geometry.offsetOf(end);
        if (a != b) canvas.drawLine(a, b, line);
        if (selected || a == b) {
          _paintHandle(canvas, a);
          _paintHandle(canvas, b);
        }
    }
  }

  /// A white dot with a blue ring, showing where a line can be grabbed.
  void _paintHandle(Canvas canvas, Offset at) {
    canvas.drawCircle(at, _handleRadius, Paint()..color = Colors.white);
    canvas.drawCircle(
      at,
      _handleRadius,
      Paint()
        ..color = DrawingsLayer.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// The line's price on the axis, while the line is in view.
  void _paintPriceTag(
    Canvas canvas,
    DrawingGeometry geometry,
    double price,
    double listWidth,
  ) {
    final paneHeight = geometry.pricePaneHeight;
    final y = geometry.yOf(price);
    if (y < 0 || y > paneHeight) return;
    final ticks = priceTicks(
      geometry.range.low,
      geometry.range.high,
      maxTicks: math.max(1, (paneHeight / 40).floor()),
    );
    final tag = TextPainter(
      text: TextSpan(
        text: price.toStringAsFixed(math.max(ticks.decimals, 2)),
        style: _tagStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tagHeight = tag.height + 4;
    final top = pinnedLabelTop(
      y: y,
      labelHeight: tagHeight,
      height: paneHeight,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        listWidth + 1,
        top,
        CandleChart.priceAxisWidth - 1,
        tagHeight,
      ),
      Paint()..color = DrawingsLayer.color,
    );
    tag.paint(canvas, Offset(listWidth + 8, top + 2));
    tag.dispose();
  }

  @override
  bool shouldRepaint(_DrawingsPainter old) =>
      old.controller != controller ||
      old.timeScale != timeScale ||
      old.priceScale != priceScale ||
      !identical(old.candles, candles);
}
