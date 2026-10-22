import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trading_app/data/market_data_source.dart';
import 'package:trading_app/data/models/candle.dart';
import 'package:trading_app/features/chart/bloc/chart_bloc.dart';

class _MockSource extends Mock implements MarketDataSource {}

// Newest visible window of the 300 test candles (candle i: low 99 + i, high 102 + i).
const double _low = 99.0 + 300 - ChartBloc.initialVisibleCount;
const double _pad = (401 - _low) * 0.05;

void main() {
  test('Candle.fromKline parses Binance string prices', () {
    final candle = Candle.fromKline([1792591260000, '83740.01', '83786.01', '83720.00', '83720.00', '10.396', 1792591319999]);
    expect(candle.openTime, DateTime.fromMillisecondsSinceEpoch(1792591260000, isUtc: true));
    expect(candle.high, 83786.01);
    expect(candle.isUp, isFalse);
  });

  group('ChartBloc', () {
    late _MockSource source;
    final candles = [
      Candle(openTime: DateTime.utc(2026, 10, 21), open: 1, high: 2, low: 0.5, close: 1.5, volume: 10),
    ];

    setUp(() => source = _MockSource());

    blocTest<ChartBloc, ChartState>(
      'emits loading then ready with candles',
      build: () {
        when(() => source.history('BTCUSDT', '1h', limit: 1000)).thenAnswer((_) async => candles);
        return ChartBloc(source);
      },
      act: (bloc) => bloc.add(const ChartStarted(symbol: 'BTCUSDT', interval: '1h')),
      expect: () => [
        const ChartState(status: ChartStatus.loading, symbol: 'BTCUSDT', interval: '1h'),
        isA<ChartState>()
            .having((s) => s.status, 'status', ChartStatus.ready)
            .having((s) => s.candles, 'candles', candles)
            .having((s) => (s.visibleFrom, s.visibleTo), 'visible range', (0, 0))
            .having((s) => s.priceLow, 'priceLow', closeTo(0.425, 1e-9))
            .having((s) => s.priceHigh, 'priceHigh', closeTo(2.075, 1e-9)),
      ],
    );

    blocTest<ChartBloc, ChartState>(
      'switching interval cancels a load that is still in flight',
      build: () {
        final slow = Completer<List<Candle>>();
        when(() => source.history('BTCUSDT', '1m', limit: 1000)).thenAnswer((_) => slow.future);
        when(() => source.history('BTCUSDT', '4h', limit: 1000)).thenAnswer((_) async {
          slow.complete(candles);
          return candles;
        });
        return ChartBloc(source);
      },
      act: (bloc) async {
        bloc.add(const ChartStarted(symbol: 'BTCUSDT', interval: '1m'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ChartStarted(symbol: 'BTCUSDT', interval: '4h'));
      },
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const ChartState(status: ChartStatus.loading, symbol: 'BTCUSDT', interval: '1m'),
        const ChartState(status: ChartStatus.loading, symbol: 'BTCUSDT', interval: '4h'),
        isA<ChartState>()
            .having((s) => s.status, 'status', ChartStatus.ready)
            .having((s) => s.interval, 'interval', '4h'),
      ],
    );

    group('visible range', () {
      // Candle i has low 99 + i and high 102 + i.
      final many = [
        for (var i = 0; i < 300; i++)
          Candle(
            openTime: DateTime.utc(2026).add(Duration(hours: i)),
            open: 100.0 + i,
            high: 102.0 + i,
            low: 99.0 + i,
            close: 101.0 + i,
            volume: 1,
          ),
      ];

      blocTest<ChartBloc, ChartState>(
        'starts on the newest visibleCount candles',
        build: () {
          when(() => source.history('BTCUSDT', '1h', limit: 1000)).thenAnswer((_) async => many);
          return ChartBloc(source);
        },
        act: (bloc) => bloc.add(const ChartStarted(symbol: 'BTCUSDT', interval: '1h')),
        skip: 1,
        expect: () => [
          isA<ChartState>()
              .having((s) => (s.visibleFrom, s.visibleTo), 'visible range', (300 - ChartBloc.initialVisibleCount, 299))
              .having((s) => s.priceLow, 'priceLow', closeTo(_low - _pad, 1e-9))
              .having((s) => s.priceHigh, 'priceHigh', closeTo(401 + _pad, 1e-9)),
        ],
      );

      blocTest<ChartBloc, ChartState>(
        'rescales prices to the candles scrolled into view',
        build: () => ChartBloc(source),
        seed: () => ChartState(status: ChartStatus.ready, candles: many),
        act: (bloc) => bloc.add(const ChartVisibleRangeChanged(from: 0, to: 99)),
        expect: () => [
          isA<ChartState>()
              .having((s) => (s.visibleFrom, s.visibleTo), 'visible range', (0, 99))
              .having((s) => s.priceLow, 'priceLow', closeTo(99 - 5.1, 1e-9))
              .having((s) => s.priceHigh, 'priceHigh', closeTo(201 + 5.1, 1e-9)),
        ],
      );

      blocTest<ChartBloc, ChartState>(
        'tracks the largest visible volume',
        build: () => ChartBloc(source),
        seed: () => ChartState(
          status: ChartStatus.ready,
          candles: [
            for (var i = 0; i < 10; i++)
              Candle(
                openTime: DateTime.utc(2026).add(Duration(hours: i)),
                open: 1,
                high: 2,
                low: 0.5,
                close: 1.5,
                volume: i == 7 ? 500 : 10.0 + i,
              ),
          ],
        ),
        act: (bloc) => bloc
          ..add(const ChartVisibleRangeChanged(from: 0, to: 5))
          ..add(const ChartVisibleRangeChanged(from: 3, to: 9)),
        expect: () => [
          isA<ChartState>().having((s) => s.volumeMax, 'volumeMax', 15),
          isA<ChartState>().having((s) => s.volumeMax, 'volumeMax', 500),
        ],
      );

      group('manual price range', () {
        ChartState ready() => ChartState(
              status: ChartStatus.ready,
              candles: many,
              visibleFrom: 0,
              visibleTo: 99,
              priceLow: 100,
              priceHigh: 200,
            );

        blocTest<ChartBloc, ChartState>(
          'vertical pan shifts the range and turns auto-scale off',
          build: () => ChartBloc(source),
          seed: ready,
          act: (bloc) => bloc.add(const ChartPricePanned(0.1)),
          expect: () => [
            isA<ChartState>()
                .having((s) => (s.priceLow, s.priceHigh), 'range', (110, 210))
                .having((s) => s.autoScale, 'autoScale', false),
          ],
        );

        blocTest<ChartBloc, ChartState>(
          'price-axis drag scales the range around its middle',
          build: () => ChartBloc(source),
          seed: ready,
          act: (bloc) => bloc.add(const ChartPriceScaled(2)),
          expect: () => [
            isA<ChartState>()
                .having((s) => (s.priceLow, s.priceHigh), 'range', (50, 250))
                .having((s) => s.autoScale, 'autoScale', false),
          ],
        );

        blocTest<ChartBloc, ChartState>(
          'scrolling after a manual pan or scale returns to auto-scale',
          build: () => ChartBloc(source),
          seed: () => ready().copyWith(autoScale: false),
          act: (bloc) => bloc.add(const ChartVisibleRangeChanged(from: 200, to: 299)),
          expect: () => [
            isA<ChartState>()
                .having((s) => (s.visibleFrom, s.visibleTo), 'visible range', (200, 299))
                .having((s) => s.autoScale, 'autoScale', true)
                .having((s) => s.priceLow, 'priceLow', closeTo(299 - 5.1, 1e-9))
                .having((s) => s.priceHigh, 'priceHigh', closeTo(401 + 5.1, 1e-9))
                .having((s) => s.volumeMax, 'volumeMax', 1),
          ],
        );

        blocTest<ChartBloc, ChartState>(
          'reset fits the visible candles again',
          build: () => ChartBloc(source),
          seed: () => ready().copyWith(autoScale: false),
          act: (bloc) => bloc.add(const ChartAutoScaleReset()),
          expect: () => [
            isA<ChartState>()
                .having((s) => s.autoScale, 'autoScale', true)
                .having((s) => s.priceLow, 'priceLow', closeTo(99 - 5.1, 1e-9))
                .having((s) => s.priceHigh, 'priceHigh', closeTo(201 + 5.1, 1e-9)),
          ],
        );
      });

      blocTest<ChartBloc, ChartState>(
        'clamps out-of-bounds ranges from overscroll',
        build: () => ChartBloc(source),
        seed: () => ChartState(status: ChartStatus.ready, candles: many),
        act: (bloc) => bloc.add(const ChartVisibleRangeChanged(from: -20, to: 5000)),
        expect: () => [
          isA<ChartState>().having((s) => (s.visibleFrom, s.visibleTo), 'visible range', (0, 299)),
        ],
      );
    });

    blocTest<ChartBloc, ChartState>(
      'emits failure when the request throws',
      build: () {
        when(() => source.history('BTCUSDT', '1h', limit: 1000)).thenThrow(const MarketDataException('offline'));
        return ChartBloc(source);
      },
      act: (bloc) => bloc.add(const ChartStarted(symbol: 'BTCUSDT', interval: '1h')),
      expect: () => [
        const ChartState(status: ChartStatus.loading, symbol: 'BTCUSDT', interval: '1h'),
        const ChartState(status: ChartStatus.failure, symbol: 'BTCUSDT', interval: '1h', error: 'offline'),
      ],
    );
  });
}
