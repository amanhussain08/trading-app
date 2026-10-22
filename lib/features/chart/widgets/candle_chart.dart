import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/candle.dart';
import '../bloc/chart_bloc.dart';
import 'chart_axes.dart';

/// Horizontally scrollable candlestick chart backed by [ChartBloc].
///
/// The [ListView] owns scrolling (drag, fling, trackpad); this widget owns the
/// zoom level (pinch, mouse wheel, trackpad pinch), reports which candles are
/// on screen, and the bloc answers with the price range that every candle uses
/// for its vertical position.
class CandleChart extends StatefulWidget {
  const CandleChart({super.key});

  static const priceAxisWidth = 64.0;
  static const timeAxisHeight = 24.0;

  /// Vertical split between the candles and the volume bars below them.
  static const pricePaneFlex = 4;
  static const volumePaneFlex = 1;

  /// Zoom limits, as the number of candles across the chart's width.
  static const minVisibleCount = 5.0;
  static const maxVisibleCount = 200.0;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  final _controller = ScrollController();
  double _visibleCount = ChartBloc.initialVisibleCount.toDouble();
  double _viewportWidth = 0;
  double _candleWidth = 0;
  int? _reportedFrom;
  int? _reportedTo;

  /// Touch points currently on the candle list, for two-finger pinch.
  final _pointers = <int, Offset>{};
  double? _pinchStartDistance;
  double _zoomStartCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportVisibleRange);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reportVisibleRange() {
    if (!_controller.hasClients || _candleWidth <= 0) return;
    final position = _controller.position;
    final count = context.read<ChartBloc>().state.candles.length;

    // reverse: true puts list item 0 (the newest candle) at the right edge.
    // print(
    //   "_reportVisibleRange: $position ${position.pixels} ${position.viewportDimension}",
    // );
    final firstItem = (position.pixels / _candleWidth).floor();
    final lastItem =
        ((position.pixels + position.viewportDimension) / _candleWidth).ceil() -
        1;
    final from = count - 1 - lastItem;
    final to = count - 1 - firstItem;

    if (from == _reportedFrom && to == _reportedTo) return;
    _reportedFrom = from;
    _reportedTo = to;
    context.read<ChartBloc>().add(ChartVisibleRangeChanged(from: from, to: to));
  }

  /// Zooms so that [targetCount] candles fit across the chart, keeping the
  /// candle under [focalX] (in candle-list coordinates) in place.
  void _zoomTo(double targetCount, double focalX) {
    if (_viewportWidth <= 0 || _candleWidth <= 0) return;
    final count = targetCount.clamp(
      CandleChart.minVisibleCount,
      CandleChart.maxVisibleCount,
    );
    if (count == _visibleCount) return;

    final candleCount = context.read<ChartBloc>().state.candles.length;
    final pixels = _controller.hasClients ? _controller.offset : 0.0;
    // The list is reversed, so scroll offsets are measured from the right edge.
    final fromRight = _viewportWidth - focalX;
    final anchorItem = (pixels + fromRight) / _candleWidth;

    final newWidth = _viewportWidth / count;
    final maxPixels = math.max(0.0, candleCount * newWidth - _viewportWidth);

    setState(() => _visibleCount = count);
    _candleWidth = newWidth;
    if (_controller.hasClients) {
      _controller.jumpTo(
        (anchorItem * newWidth - fromRight).clamp(0.0, maxPixels),
      );
    }
    _reportVisibleRange();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      final [a, b] = _pointers.values.toList();
      _pinchStartDistance = (a - b).distance;
      _zoomStartCount = _visibleCount;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final startDistance = _pinchStartDistance;
    if (_pointers.length != 2 || startDistance == null || startDistance < 1) {
      return;
    }

    final [a, b] = _pointers.values.toList();
    final distance = (a - b).distance;
    if (distance < 1) return;
    _zoomTo(_zoomStartCount * startDistance / distance, (a.dx + b.dx) / 2);
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _pinchStartDistance = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    // The horizontal list claims shift+wheel and sideways scrolls first; a
    // plain vertical wheel is left unclaimed, so it zooms.
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      _zoomTo(
        _visibleCount * math.exp(scroll.scrollDelta.dy / 300),
        scroll.localPosition.dx,
      );
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) =>
      _zoomStartCount = _visibleCount;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale == 1) return;
    _zoomTo(_zoomStartCount / event.scale, event.localPosition.dx);
  }

  @override
  Widget build(BuildContext context) {
    final candles = context.select((ChartBloc bloc) => bloc.state.candles);

    final candleList = LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        final candleWidth = constraints.maxWidth / _visibleCount;
        if (candleWidth != _candleWidth) {
          _candleWidth = candleWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reportVisibleRange();
          });
        }

        final pricePaneHeight =
            constraints.maxHeight *
            CandleChart.pricePaneFlex /
            (CandleChart.pricePaneFlex + CandleChart.volumePaneFlex);

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            if (_pointers.length >= 2 || pricePaneHeight <= 0) return;
            context.read<ChartBloc>().add(
              ChartPricePanned(details.delta.dy / pricePaneHeight),
            );
          },
          onDoubleTap: () =>
              context.read<ChartBloc>().add(const ChartAutoScaleReset()),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerEnd,
            onPointerCancel: _onPointerEnd,
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: _onPanZoomStart,
            onPointerPanZoomUpdate: _onPanZoomUpdate,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                dragDevices: PointerDeviceKind.values.toSet(),
              ),
              child: ListView.builder(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemExtent: candleWidth,
                itemCount: candles.length,
                itemBuilder: (context, index) =>
                    CandleItem(candle: candles[candles.length - 1 - index]),
              ),
            ),
          ),
        );
      },
    );

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: candleList),
              const SizedBox(
                width: CandleChart.priceAxisWidth,
                child: Column(
                  children: [
                    Expanded(
                      flex: CandleChart.pricePaneFlex,
                      child: PriceAxis(),
                    ),
                    Expanded(
                      flex: CandleChart.volumePaneFlex,
                      child: VolumeAxis(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: CandleChart.timeAxisHeight,
          child: Row(
            children: [
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: TimeAxisPainter(
                    candles: candles,
                    visibleCount: _visibleCount,
                    scrollController: _controller,
                  ),
                ),
              ),
              const SizedBox(width: CandleChart.priceAxisWidth),
            ],
          ),
        ),
      ],
    );
  }
}

/// One candle and its volume bar, scaled to the bloc's visible price and
/// volume ranges. Uses the same flex split as the axis column so both panes
/// line up with [PriceAxis] and [VolumeAxis].
class CandleItem extends StatelessWidget {
  const CandleItem({super.key, required this.candle});

  final Candle candle;

  @override
  Widget build(BuildContext context) {
    final (low, high, volumeMax) = context.select(
      (ChartBloc bloc) =>
          (bloc.state.priceLow, bloc.state.priceHigh, bloc.state.volumeMax),
    );
    return Column(
      children: [
        Expanded(
          flex: CandleChart.pricePaneFlex,
          child: CustomPaint(
            size: Size.infinite,
            painter: _CandlePainter(candle, low, high),
          ),
        ),
        Expanded(
          flex: CandleChart.volumePaneFlex,
          child: CustomPaint(
            size: Size.infinite,
            painter: _VolumePainter(candle, volumeMax),
          ),
        ),
      ],
    );
  }
}

class _VolumePainter extends CustomPainter {
  _VolumePainter(this.candle, this.volumeMax);

  final Candle candle;
  final double volumeMax;

  static const _upColor = Color(0x8026A69A);
  static const _downColor = Color(0x80EF5350);
  static const _separatorColor = Color(0x1FFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawLine(
      const Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()..color = _separatorColor,
    );
    if (volumeMax <= 0) return;

    final barHeight =
        candle.volume / (volumeMax * volumeHeadroom) * size.height;
    final barWidth = math.max(1.0, size.width * 0.7);
    final left = (size.width - barWidth) / 2;
    canvas.drawRect(
      Rect.fromLTRB(
        left,
        size.height - barHeight,
        left + barWidth,
        size.height,
      ),
      Paint()..color = candle.isUp ? _upColor : _downColor,
    );
  }

  @override
  bool shouldRepaint(_VolumePainter old) =>
      old.candle != candle || old.volumeMax != volumeMax;
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candle, this.priceLow, this.priceHigh);

  final Candle candle;
  final double priceLow;
  final double priceHigh;

  static const _upColor = Color(0xFF26A69A);
  static const _downColor = Color(0xFFEF5350);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || priceHigh <= priceLow) return;

    double y(double price) =>
        (priceHigh - price) / (priceHigh - priceLow) * size.height;

    final color = candle.isUp ? _upColor : _downColor;
    final centerX = size.width / 2;
    final bodyWidth = math.max(1.0, size.width * 0.7);
    final top = y(math.max(candle.open, candle.close));
    final bottom = math.max(y(math.min(candle.open, candle.close)), top + 1);

    canvas
      ..drawLine(
        Offset(centerX, y(candle.high)),
        Offset(centerX, y(candle.low)),
        Paint()
          ..color = color
          ..strokeWidth = 1,
      )
      ..drawRect(
        Rect.fromLTRB(
          centerX - bodyWidth / 2,
          top,
          centerX + bodyWidth / 2,
          bottom,
        ),
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candle != candle ||
      old.priceLow != priceLow ||
      old.priceHigh != priceHigh;
}
