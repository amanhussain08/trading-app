import 'package:equatable/equatable.dart';

class Candle extends Equatable {
  const Candle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  /// Parses one row of Binance `/api/v3/klines`, where prices are strings:
  /// `[openTime, "open", "high", "low", "close", "volume", closeTime, ...]`.
  factory Candle.fromKline(List<dynamic> row) => Candle(
        openTime: DateTime.fromMillisecondsSinceEpoch(row[0] as int, isUtc: true),
        open: double.parse(row[1] as String),
        high: double.parse(row[2] as String),
        low: double.parse(row[3] as String),
        close: double.parse(row[4] as String),
        volume: double.parse(row[5] as String),
      );

  /// Parses the `k` object of a Binance `<symbol>@kline_<interval>` stream
  /// message: `{"t": openTime, "o": "open", "h": "high", "l": "low", ...}`.
  factory Candle.fromStreamKline(Map<String, dynamic> k) => Candle(
        openTime: DateTime.fromMillisecondsSinceEpoch(k['t'] as int, isUtc: true),
        open: double.parse(k['o'] as String),
        high: double.parse(k['h'] as String),
        low: double.parse(k['l'] as String),
        close: double.parse(k['c'] as String),
        volume: double.parse(k['v'] as String),
      );

  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  bool get isUp => close >= open;

  @override
  List<Object> get props => [openTime, open, high, low, close, volume];
}
