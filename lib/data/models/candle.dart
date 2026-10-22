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
