import 'package:flutter_test/flutter_test.dart';
import 'package:trading_app/data/models/candle.dart';
import 'package:trading_app/features/chart/widgets/chart_axes.dart';

Candle _at(DateTime time) =>
    Candle(openTime: time, open: 1, high: 1, low: 1, close: 1, volume: 1);

void main() {
  group('priceTicks', () {
    test('uses round steps for BTC-sized prices', () {
      final ticks = priceTicks(83213, 84987, maxTicks: 6);
      expect(ticks.values, [83500, 84000, 84500]);
      expect(ticks.decimals, 0);
    });

    test('uses decimals for small prices', () {
      // Range 0.0259 / 5 ticks = 0.00518 per tick -> rounds up to a 0.01 step.
      final ticks = priceTicks(0.5132, 0.5391, maxTicks: 5);
      expect(ticks.values, [closeTo(0.52, 1e-12), closeTo(0.53, 1e-12)]);
      expect(ticks.decimals, 2);
      expect(ticks.values.last.toStringAsFixed(ticks.decimals), '0.53');
    });

    test('returns nothing for an empty range', () {
      expect(priceTicks(10, 10, maxTicks: 5).values, isEmpty);
    });
  });

  group('formatVolume', () {
    test('uses K / M / B suffixes with sensible decimals', () {
      expect(formatVolume(950), '950');
      expect(formatVolume(7.5), '7.50');
      expect(formatVolume(1234), '1.23K');
      expect(formatVolume(45600000), '45.6M');
      expect(formatVolume(7e9), '7.00B');
    });
  });

  group('timeStepMinutes', () {
    test('picks the smallest step that keeps labels 80px apart', () {
      // 1h candles at 10px: 8 candles needed -> 12h is the first step >= 8h.
      expect(timeStepMinutes(interval: const Duration(hours: 1), candleWidth: 10), 720);
      // 1m candles at 20px: 4 candles needed -> 5m.
      expect(timeStepMinutes(interval: const Duration(minutes: 1), candleWidth: 20), 5);
    });

    test('never picks a step shorter than one candle', () {
      expect(timeStepMinutes(interval: const Duration(days: 1), candleWidth: 200), 1440);
    });
  });

  group('time labels', () {
    test('ticks where a new local-time bucket starts', () {
      final start = DateTime(2026, 10, 21, 10).toUtc();
      final candles = [for (var h = 0; h < 6; h++) _at(start.add(Duration(hours: h)))];
      // 2h buckets in local time: 10-11, 12-13, 14-15.
      final ticks = [for (var i = 0; i < 6; i++) if (isTimeTick(candles, i, 120)) i];
      expect(ticks, [2, 4]);
    });

    test('shows time, date at a new day, year at a new year', () {
      expect(timeLabel(DateTime(2026, 10, 21, 13), DateTime(2026, 10, 21, 14, 30)), '14:30');
      expect(timeLabel(DateTime(2026, 10, 21, 23), DateTime(2026, 10, 22)), '22 Oct');
      expect(timeLabel(DateTime(2026, 12, 31, 23), DateTime(2027)), '2027');
    });
  });
}
