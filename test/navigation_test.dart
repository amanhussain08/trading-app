import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trading_app/data/market_data_source.dart';
import 'package:trading_app/data/models/candle.dart';
import 'package:trading_app/features/chart/view/chart_screen.dart';
import 'package:trading_app/features/chart/widgets/candle_chart.dart';
import 'package:trading_app/features/home/view/home_screen.dart';
import 'package:trading_app/main.dart';

class _MockSource extends Mock implements MarketDataSource {}

void main() {
  testWidgets('landing page opens the chart screen and back returns', (
    tester,
  ) async {
    await tester.pumpWidget(const TradingApp());
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.text('Open BTC/USDT chart'));
    await tester.pumpAndSettle();

    expect(find.byType(ChartScreen), findsOneWidget);
    expect(find.text('BTCUSDT'), findsOneWidget);
    expect(find.text('1H'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ChartScreen), findsNothing);
  });

  testWidgets('chart route draws candles from the given source', (
    tester,
  ) async {
    final source = _MockSource();
    when(() => source.fetch('BTCUSDT', '1h', limit: 1000)).thenAnswer(
      (_) async => [
        Candle(
          openTime: DateTime.utc(2026, 10, 21),
          open: 1,
          high: 2,
          low: 0.5,
          close: 1.5,
          volume: 10,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              ChartScreen.route(
                symbol: 'BTCUSDT',
                interval: '1h',
                source: source,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(CandleChart), findsOneWidget);
    verify(() => source.fetch('BTCUSDT', '1h', limit: 1000)).called(1);
    verifyNever(() => source.dispose());
  });

  testWidgets('interval dropdown reloads the chart with the chosen interval', (
    tester,
  ) async {
    final source = _MockSource();
    when(() => source.fetch('BTCUSDT', any(), limit: 1000)).thenAnswer(
      (_) async => [
        Candle(
          openTime: DateTime.utc(2026, 10, 21),
          open: 1,
          high: 2,
          low: 0.5,
          close: 1.5,
          volume: 10,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              ChartScreen.route(
                symbol: 'BTCUSDT',
                interval: '1h',
                source: source,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    for (final label in ChartScreen.intervals.values) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('4H').last);
    await tester.pumpAndSettle();

    verify(() => source.fetch('BTCUSDT', '4h', limit: 1000)).called(1);
    expect(find.text('4H'), findsOneWidget);
    expect(find.byType(CandleChart), findsOneWidget);
  });
}
