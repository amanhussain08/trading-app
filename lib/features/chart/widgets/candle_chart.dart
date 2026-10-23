import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/candle.dart';
import '../bloc/chart_bloc.dart';
import '../chart_log.dart';
import '../drawing/drawings.dart';
import '../scale/price_scale.dart';
import '../scale/time_scale.dart';
import 'chart_axes.dart';
import 'crosshair.dart';
import 'drawings_layer.dart';
import 'pane_painter.dart';

/// Candlestick chart over [ChartBloc]'s candles, structured like Lightweight
/// Charts: a [TimeScale] and a [PriceScale] hold the view, input only
/// changes them, and painters listening to them repaint, each in its own
/// layer, so moving the crosshair never repaints the candles.
class CandleChart extends StatefulWidget {
  const CandleChart({
    super.key,
    this.timeScale,
    this.priceScale,
    this.drawings,
  });

  /// Pass your own to drive or read the view from outside (e.g. tests, or a
  /// "scroll to latest" button); the caller then owns and disposes it.
  final TimeScale? timeScale;
  final PriceScale? priceScale;

  /// Pass your own to pick drawing tools from outside the chart, or to keep
  /// drawings when the chart is rebuilt; the caller then owns it.
  final DrawingController? drawings;

  /// Frame around the whole chart, matching the axis lines inside it.
  static const borderColor = Color(0x3D000000);

  static const priceAxisWidth = 64.0;
  static const timeAxisHeight = 24.0;

  /// Vertical split between the candles and the volume bars below them.
  static const pricePaneFlex = 4;
  static const volumePaneFlex = 1;
  static const pricePaneFraction =
      pricePaneFlex / (pricePaneFlex + volumePaneFlex);

  /// Input the chart responds to: fingers and pens only, no mouse or
  /// trackpad.
  static const touchDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  /// The candle pane, for finding it in tests.
  static const paneKey = ValueKey('candle-chart-pane');

  @override
  State<CandleChart> createState() => _CandleChartState();
}

enum _DragAxis { time, price }

class _CandleChartState extends State<CandleChart>
    with SingleTickerProviderStateMixin {
  late final TimeScale _time = widget.timeScale ?? TimeScale();
  late final PriceScale _price = widget.priceScale ?? PriceScale();
  late final DrawingController _drawings =
      widget.drawings ?? DrawingController();

  /// Where the crosshair is, in chart coordinates; null hides it.
  final _crosshair = ValueNotifier<Offset?>(null);

  /// Candles the time scale was last synced with.
  late List<Candle> _candles;

  late final AnimationController _fling;
  double _flingLast = 0;

  double _pricePaneHeight = 0;

  // The gesture in progress.
  _DragAxis? _axis;
  bool _zooming = false;
  double _gestureStartCount = 0;
  Offset _gestureTotal = Offset.zero;

  /// Where the last finger went down; a scale gesture only starts once the
  /// finger has moved a little, and drawings should start where it touched.
  Offset? _pointerDown;

  /// Dragging out the active tool's drawing (the controller's draft).
  bool _placing = false;

  /// Dragging the selected drawing: which part, the drawing as it was, and
  /// where the finger started.
  ({int index, DrawingPart part, Drawing original, ChartPoint from})? _moving;

  @override
  void initState() {
    super.initState();
    _fling = AnimationController.unbounded(vsync: this)
      ..addListener(_onFlingTick);
    _candles = context.read<ChartBloc>().state.candles;
    _time.reset(_candles.length);
  }

  @override
  void dispose() {
    _fling.dispose();
    _crosshair.dispose();
    if (widget.timeScale == null) _time.dispose();
    if (widget.priceScale == null) _price.dispose();
    if (widget.drawings == null) _drawings.dispose();
    super.dispose();
  }

  /// A live tick keeps the count; an appended candle extends it; anything
  /// else (a different series) starts the view over.
  void _syncCandles(List<Candle> next) {
    final previous = _candles;
    _candles = next;
    final continues =
        previous.isNotEmpty &&
        next.length >= previous.length &&
        next[previous.length - 1].openTime == previous.last.openTime;
    if (!continues) {
      _time.reset(next.length);
    } else if (next.length > previous.length) {
      _time.candlesAppended(next.length - previous.length);
    }
  }

  // --- Time scale changes made by the user ---------------------------------

  /// Pans time; prices refit as soon as different candles come into view,
  /// even after a manual price drag. Returns whether anything moved.
  bool _panTime(double dx) {
    final before = _time.visibleRange;
    final moved = _time.panBy(dx);
    if (moved && _time.visibleRange != before) _price.resetAutoScale();
    return moved;
  }

  void _zoomTime(double targetCount, double focalX) {
    final before = _time.visibleRange;
    _time.zoomTo(targetCount, focalX);
    if (_time.visibleRange != before) _price.resetAutoScale();
  }

  // --- Drag and pinch (one scale gesture covers both) ------------------------

  void _onScaleStart(ScaleStartDetails details) {
    if (_fling.isAnimating) ChartLog.info('input', 'fling interrupted');
    _fling.stop();
    _axis = null;
    _zooming = false;
    _gestureStartCount = _time.visibleCount;
    _gestureTotal = Offset.zero;
    _placing = false;
    _moving = null;
    ChartLog.info(
      'input',
      'gesture start: ${details.pointerCount} pointer(s), ${details.kind?.name}',
    );
    if (details.pointerCount == 1) {
      _startDrawingDrag(_pointerDown ?? details.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_placing || _moving != null) {
      if (details.pointerCount == 1) {
        _updateDrawingDrag(details.localFocalPoint);
        return;
      }
      _cancelDrawingDrag();
    }
    if (details.pointerCount >= 2 || details.scale != 1) {
      if (!_zooming) {
        ChartLog.info(
          'input',
          'pinch zoom from ${_gestureStartCount.toStringAsFixed(1)} candles',
        );
      }
      _zooming = true;
      if (details.scale != 1) {
        _zoomTime(
          _gestureStartCount / details.scale,
          details.localFocalPoint.dx,
        );
      }
      return;
    }

    final delta = details.focalPointDelta;
    if (delta == Offset.zero) return;
    _gestureTotal += delta;
    if (_axis == null) {
      _axis = delta.dx.abs() >= delta.dy.abs()
          ? _DragAxis.time
          : _DragAxis.price;
      ChartLog.info('input', 'drag locked to ${_axis!.name}');
    }
    switch (_axis!) {
      case _DragAxis.time:
        _panTime(delta.dx);
      case _DragAxis.price:
        if (_pricePaneHeight > 0) _price.panBy(delta.dy / _pricePaneHeight);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_placing || _moving != null) {
      _endDrawingDrag();
      return;
    }
    final velocity = details.velocity.pixelsPerSecond.dx;
    ChartLog.info(
      'input',
      'gesture end: ${_zooming ? 'zoom to ${_time.visibleCount.toStringAsFixed(1)} candles' : 'dragged ${_axis?.name} by ${_gestureTotal.dx.toStringAsFixed(0)},${_gestureTotal.dy.toStringAsFixed(0)}px'} '
          'visible=${_time.visibleRange}',
    );
    if (_axis == _DragAxis.time &&
        !_zooming &&
        velocity.abs() > kMinFlingVelocity) {
      _startFling(velocity);
    }
    _axis = null;
    _zooming = false;
  }

  /// Momentum after a horizontal drag, with the same friction ListView used.
  void _startFling(double velocity) {
    ChartLog.info('input', 'fling at ${velocity.toStringAsFixed(0)}px/s');
    _flingLast = 0;
    _fling.animateWith(
      ClampingScrollSimulation(position: 0, velocity: velocity),
    );
  }

  void _onFlingTick() {
    final value = _fling.value;
    final dx = value - _flingLast;
    _flingLast = value;
    if (dx == 0) return;
    if (!_panTime(dx)) {
      _fling.stop();
      ChartLog.info(
        'input',
        'fling stopped at the edge, visible=${_time.visibleRange}',
      );
    }
  }

  // --- Drawings ---------------------------------------------------------------

  DrawingGeometry _geometry() => DrawingGeometry(
    candles: _candles,
    timeScale: _time,
    range: _price.range(_candles, _time),
    pricePaneHeight: _pricePaneHeight,
  );

  /// With a tool picked, a tap places a horizontal line, or one end of a
  /// trend line (the second tap places the other). Without one, a tap
  /// selects the drawing under it, or clears the selection.
  void _onTap(Offset position) {
    final geometry = _geometry();
    final inPricePane = !geometry.isEmpty && position.dy <= _pricePaneHeight;
    final tool = _drawings.tool;
    if (tool == null) {
      _drawings.select(
        inPricePane
            ? geometry.hitTest(_drawings.drawings, position)?.index
            : null,
      );
      return;
    }
    if (!inPricePane) return;
    final at = geometry.pointAt(position);
    switch (tool) {
      case DrawingTool.horizontalLine:
        _drawings.add(HorizontalLine(at.price));
      case DrawingTool.trendLine:
        if (_drawings.draft case TrendLine(:final start)) {
          _drawings.add(TrendLine(start, at));
        } else {
          _drawings.setDraft(TrendLine(at, at));
        }
    }
  }

  /// A one-finger drag that starts on the price pane drags out the picked
  /// tool's drawing, or moves the selected drawing if it starts on it;
  /// anything else pans as usual.
  void _startDrawingDrag(Offset position) {
    final geometry = _geometry();
    if (geometry.isEmpty || position.dy > _pricePaneHeight) return;
    final at = geometry.pointAt(position);
    final tool = _drawings.tool;
    if (tool != null) {
      _placing = true;
      _drawings.setDraft(switch (tool) {
        DrawingTool.horizontalLine => HorizontalLine(at.price),
        DrawingTool.trendLine => TrendLine(at, at),
      });
      ChartLog.info('draw', 'dragging out a ${tool.name}');
      return;
    }
    final selected = _drawings.selectedIndex;
    if (selected == null) return;
    final hit = geometry.hitTest(_drawings.drawings, position);
    if (hit == null || hit.index != selected) return;
    _moving = (
      index: hit.index,
      part: hit.part,
      original: _drawings.drawings[hit.index],
      from: at,
    );
    ChartLog.info('draw', 'moving ${hit.part.name} of ${_moving!.original}');
  }

  void _updateDrawingDrag(Offset position) {
    final geometry = _geometry();
    if (geometry.isEmpty) return;
    final at = geometry.pointAt(
      Offset(position.dx, position.dy.clamp(0.0, _pricePaneHeight)),
    );
    if (_placing) {
      _drawings.setDraft(switch (_drawings.draft) {
        TrendLine(:final start) => TrendLine(start, at),
        _ => HorizontalLine(at.price),
      });
    } else if (_moving case final moving?) {
      _drawings.replace(
        moving.index,
        dragDrawing(
          moving.original,
          moving.part,
          at.time.difference(moving.from.time),
          at.price - moving.from.price,
        ),
      );
    }
  }

  /// A trend line dragged too short to see is kept as its first point, as
  /// if tapped, so the next tap can finish it.
  void _endDrawingDrag() {
    if (_placing) {
      final draft = _drawings.draft;
      final geometry = _geometry();
      switch (draft) {
        case TrendLine(:final start, :final end)
            when !geometry.isEmpty &&
                (geometry.offsetOf(start) - geometry.offsetOf(end)).distance <
                    DrawingGeometry.touchSlop:
          _drawings.setDraft(TrendLine(start, start));
        case final Drawing drawing:
          _drawings.add(drawing);
        case null:
          break;
      }
    } else if (_moving case final moving?) {
      ChartLog.info('draw', 'moved to ${_drawings.drawings[moving.index]}');
    }
    _placing = false;
    _moving = null;
  }

  /// A second finger turns the gesture into a pinch zoom: a drawing being
  /// dragged out is dropped, one being moved stays where it got to.
  void _cancelDrawingDrag() {
    if (_placing) _drawings.setDraft(null);
    ChartLog.info('draw', 'drawing drag cancelled by a second finger');
    _placing = false;
    _moving = null;
  }

  // --- Crosshair and auto-scale reset ---------------------------------------

  void _showCrosshair(Offset position) => _crosshair.value = position;

  void _hideCrosshair() {
    if (_crosshair.value != null) ChartLog.info('input', 'crosshair hidden');
    _crosshair.value = null;
  }

  void _resetAutoScale() {
    ChartLog.info('input', 'double-tap: autoscale');
    _price.resetAutoScale();
  }

  @override
  Widget build(BuildContext context) {
    final candles = context.select((ChartBloc bloc) => bloc.state.candles);

    return BlocListener<ChartBloc, ChartState>(
      listenWhen: (previous, current) =>
          !identical(previous.candles, current.candles),
      listener: (context, state) => _syncCandles(state.candles),
      // Painted over the edges instead of padding them, so the candle pane
      // keeps its origin at the chart's, which the crosshair relies on.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: CandleChart.borderColor),
        ),
        child: Stack(
          children: [
            _layout(_pane(context, candles), candles),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: DrawingsLayer(
                    controller: _drawings,
                    timeScale: _time,
                    priceScale: _price,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CrosshairLayer(
                    point: _crosshair,
                    timeScale: _time,
                    priceScale: _price,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The candle pane with all its input handling.
  Widget _pane(BuildContext context, List<Candle> candles) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _time.setWidth(constraints.maxWidth);
        _pricePaneHeight =
            constraints.maxHeight * CandleChart.pricePaneFraction;

        return Listener(
          onPointerDown: (event) => _pointerDown = event.localPosition,
          // Rebuilt when a tool is picked: placing a trend line by two quick
          // taps must not count as a double-tap.
          child: ListenableBuilder(
            listenable: _drawings,
            builder: (context, child) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              supportedDevices: CandleChart.touchDevices,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: (details) => _onTap(details.localPosition),
              onDoubleTap: _drawings.tool == null ? _resetAutoScale : null,
              onLongPressStart: (details) {
                ChartLog.info('input', 'long press: crosshair');
                _showCrosshair(details.localPosition);
              },
              onLongPressMoveUpdate: (details) =>
                  _showCrosshair(details.localPosition),
              onLongPressEnd: (_) => _hideCrosshair(),
              onLongPressCancel: _hideCrosshair,
              child: child,
            ),
            child: _panePaint(candles, dpr),
          ),
        );
      },
    );
  }

  Widget _panePaint(List<Candle> candles, double dpr) => RepaintBoundary(
    child: CustomPaint(
      key: CandleChart.paneKey,
      size: Size.infinite,
      painter: CandlePanePainter(
        candles: candles,
        timeScale: _time,
        priceScale: _price,
        devicePixelRatio: dpr,
        pricePaneFraction: CandleChart.pricePaneFraction,
      ),
    ),
  );

  /// Candle pane with the price and volume axes on the right, and the time
  /// axis below.
  Widget _layout(Widget pane, List<Candle> candles) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: pane),
              SizedBox(
                width: CandleChart.priceAxisWidth,
                child: Column(
                  children: [
                    Expanded(
                      flex: CandleChart.pricePaneFlex,
                      child: PriceAxis(
                        candles: candles,
                        timeScale: _time,
                        priceScale: _price,
                      ),
                    ),
                    Expanded(
                      flex: CandleChart.volumePaneFlex,
                      child: VolumeAxis(
                        candles: candles,
                        timeScale: _time,
                        priceScale: _price,
                      ),
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
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: TimeAxisPainter(
                      candles: candles,
                      timeScale: _time,
                    ),
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
