import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trading_app/data/market_data_source.dart';
import 'package:trading_app/data/models/candle.dart';
import 'package:trading_app/features/chart/bloc/chart_bloc.dart';
import 'package:trading_app/features/chart/widgets/candle_chart.dart';
import 'package:trading_app/features/chart/widgets/chart_axes.dart';

class _MockSource extends Mock implements MarketDataSource {}

const _chartWidth = 500.0;
const _candleWidth = (_chartWidth - CandleChart.priceAxisWidth) / ChartBloc.initialVisibleCount;

List<Candle> _candles(int count) => [
      for (var i = 0; i < count; i++)
        Candle(
          openTime: DateTime.utc(2026).add(Duration(hours: i)),
          open: 100.0 + i,
          high: 102.0 + i,
          low: 99.0 + i,
          close: 101.0 + i,
          volume: 1,
        ),
    ];

Future<ChartBloc> _pumpChart(WidgetTester tester, List<Candle> candles) async {
  final source = _MockSource();
  when(() => source.history(any(), any(), limit: any(named: 'limit'))).thenAnswer((_) async => candles);
  final bloc = ChartBloc(source)..add(const ChartStarted(symbol: 'BTCUSDT', interval: '1h'));
  addTearDown(bloc.close);

  await tester.pumpWidget(MaterialApp(
    home: BlocProvider.value(
      value: bloc,
      child: const Center(child: SizedBox(width: _chartWidth, height: 300, child: CandleChart())),
    ),
  ));
  await tester.pumpAndSettle();
  return bloc;
}

void main() {
  testWidgets('shows the newest visibleCount candles in one view', (tester) async {
    final bloc = await _pumpChart(tester, _candles(300));

    expect((bloc.state.visibleFrom, bloc.state.visibleTo), (300 - ChartBloc.initialVisibleCount, 299));
    expect(tester.getSize(find.byType(CandleItem).first).width, _candleWidth);
  });

  testWidgets('lays out a price axis on the right and a time axis below', (tester) async {
    await _pumpChart(tester, _candles(300));

    final chart = tester.getRect(find.byType(CandleChart));
    final priceAxis = tester.getRect(find.byType(PriceAxis));
    final list = tester.getRect(find.byType(ListView));

    expect(priceAxis.width, CandleChart.priceAxisWidth);
    expect(priceAxis.right, chart.right);
    expect(list.right, priceAxis.left);
    expect(list.bottom, chart.bottom - CandleChart.timeAxisHeight);
    expect(priceAxis.top, list.top);
  });

  testWidgets('volume pane sits under the candles and lines up with its axis', (tester) async {
    await _pumpChart(tester, _candles(300));

    final list = tester.getRect(find.byType(ListView));
    final priceAxis = tester.getRect(find.byType(PriceAxis));
    final volumeAxis = tester.getRect(find.byType(VolumeAxis));

    expect(volumeAxis.top, priceAxis.bottom);
    expect(volumeAxis.bottom, list.bottom);
    expect(
      volumeAxis.height / list.height,
      closeTo(CandleChart.volumePaneFlex / (CandleChart.pricePaneFlex + CandleChart.volumePaneFlex), 0.01),
    );

    // Each candle item splits at the same height as the axis column.
    final item = find.byType(CandleItem).first;
    final panes = find.descendant(of: item, matching: find.byType(CustomPaint));
    expect(tester.getRect(panes.at(0)).bottom, priceAxis.bottom);
    expect(tester.getRect(panes.at(1)).height, volumeAxis.height);
  });

  testWidgets('dragging right scrolls into history and updates the bloc', (tester) async {
    final bloc = await _pumpChart(tester, _candles(300));

    // Holding still before release keeps fling momentum out of the measurement;
    // the tolerance covers the touch slop consumed before the drag starts.
    final gesture = await tester.startGesture(tester.getCenter(find.byType(CandleChart)));
    for (var i = 0; i < 25; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    // 250px dragged; up to ~18px of touch slop is consumed before scrolling.
    expect(bloc.state.visibleTo.toDouble(), closeTo(299 - 250 / _candleWidth + 1, 3));
    expect(
      bloc.state.visibleTo - bloc.state.visibleFrom,
      inInclusiveRange(ChartBloc.initialVisibleCount - 1, ChartBloc.initialVisibleCount),
    );
    expect(bloc.state.priceLow, lessThan(99.0 + bloc.state.visibleFrom));
  });

  group('zoom', () {
    double candleWidth(WidgetTester tester) => tester.getSize(find.byType(CandleItem).first).width;
    double visibleMiddle(ChartBloc bloc) => (bloc.state.visibleFrom + bloc.state.visibleTo) / 2;

    Future<void> wheel(WidgetTester tester, double dy) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byType(ListView));
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pumpAndSettle();
    }

    testWidgets('mouse wheel up zooms in around the cursor', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));
      final middleBefore = visibleMiddle(bloc);

      await wheel(tester, -300); // count * e^-1, about 18 candles

      expect(candleWidth(tester), greaterThan(_candleWidth * 2));
      expect(bloc.state.visibleTo - bloc.state.visibleFrom, inInclusiveRange(17, 20));
      expect(visibleMiddle(bloc), closeTo(middleBefore, 1.5));
    });

    testWidgets('mouse wheel down zooms out, limited to maxVisibleCount', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));

      await wheel(tester, 3000);

      final listWidth = tester.getSize(find.byType(ListView)).width;
      expect(candleWidth(tester), closeTo(listWidth / CandleChart.maxVisibleCount, 1e-9));
      expect(bloc.state.visibleTo, 299);
    });

    testWidgets('two-finger pinch out zooms in around the fingers', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));
      final middleBefore = visibleMiddle(bloc);
      final center = tester.getCenter(find.byType(ListView));

      final left = await tester.startGesture(center - const Offset(40, 0), pointer: 1);
      final right = await tester.startGesture(center + const Offset(40, 0), pointer: 2);
      for (var i = 0; i < 10; i++) {
        await left.moveBy(const Offset(-4, 0));
        await right.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await left.up();
      await right.up();
      await tester.pumpAndSettle();

      // Finger distance 80px -> 160px halves the visible candle count.
      final visible = bloc.state.visibleTo - bloc.state.visibleFrom;
      expect(visible, closeTo(ChartBloc.initialVisibleCount / 2, 2));
      expect(visibleMiddle(bloc), closeTo(middleBefore, 3));
    });

    testWidgets('never zooms in past minVisibleCount', (tester) async {
      await _pumpChart(tester, _candles(300));

      await wheel(tester, -5000);

      final listWidth = tester.getSize(find.byType(ListView)).width;
      expect(candleWidth(tester), closeTo(listWidth / CandleChart.minVisibleCount, 1e-9));
    });
  });

  group('pan', () {
    testWidgets('dragging the chart down moves prices down and keeps time', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));
      final before = bloc.state;

      await tester.drag(find.byType(ListView), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(bloc.state.autoScale, isFalse);
      expect(bloc.state.priceHigh, greaterThan(before.priceHigh));
      expect(
        bloc.state.priceHigh - bloc.state.priceLow,
        closeTo(before.priceHigh - before.priceLow, 1e-6),
      );
      expect(bloc.state.visibleTo, before.visibleTo);
    });

    testWidgets('dragging sideways still scrolls and does not pan prices', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));

      await tester.drag(find.byType(ListView), const Offset(150, 0));
      await tester.pumpAndSettle();

      expect(bloc.state.autoScale, isTrue);
      expect(bloc.state.visibleTo, lessThan(299));
    });

    testWidgets('dragging the price axis down compresses the candles', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));
      final range = bloc.state.priceHigh - bloc.state.priceLow;

      await tester.drag(find.byType(PriceAxis), const Offset(0, 80));
      await tester.pumpAndSettle();

      expect(bloc.state.autoScale, isFalse);
      expect(bloc.state.priceHigh - bloc.state.priceLow, greaterThan(range));
    });

    testWidgets('scrolling after a pan returns to auto-scale', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));

      await tester.drag(find.byType(ListView), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(bloc.state.autoScale, isFalse);

      await tester.drag(find.byType(ListView), const Offset(150, 0));
      await tester.pumpAndSettle();

      expect(bloc.state.autoScale, isTrue);
      final visible = bloc.state.candles.sublist(bloc.state.visibleFrom, bloc.state.visibleTo + 1);
      final lowest = visible.map((c) => c.low).reduce(math.min);
      final highest = visible.map((c) => c.high).reduce(math.max);
      expect(bloc.state.priceLow, lessThan(lowest));
      expect(bloc.state.priceHigh, greaterThan(highest));
      expect(bloc.state.priceHigh - bloc.state.priceLow, lessThan((highest - lowest) * 1.2));
    });

    testWidgets('double-tap restores auto-scale', (tester) async {
      final bloc = await _pumpChart(tester, _candles(300));
      final fitted = (bloc.state.priceLow, bloc.state.priceHigh);

      await tester.drag(find.byType(PriceAxis), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(bloc.state.autoScale, isFalse);

      final axis = tester.getCenter(find.byType(PriceAxis));
      await tester.tapAt(axis);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(axis);
      await tester.pumpAndSettle();

      expect(bloc.state.autoScale, isTrue);
      expect((bloc.state.priceLow, bloc.state.priceHigh), fitted);
    });
  });

  testWidgets('fling stops at the oldest candle', (tester) async {
    final bloc = await _pumpChart(tester, _candles(300));

    await tester.fling(find.byType(CandleChart), const Offset(400, 0), 5000);
    await tester.pumpAndSettle();

    expect(bloc.state.visibleFrom, 0);
  });
}
