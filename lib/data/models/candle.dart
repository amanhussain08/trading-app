import 'package:equatable/equatable.dart';

/// One candlestick: the open, high, low and close prices over one interval
/// starting at [openTime], and the volume traded in it.
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

  /// Start of the candle's interval, in UTC. Identifies the candle: a live
  /// update with the same open time replaces it rather than adding one.
  final DateTime openTime;
  final double open;
  final double high;
  final double low;

  /// The latest price while the candle is still forming.
  final double close;

  /// Amount of the base asset traded (e.g. BTC for BTCUSDT).
  final double volume;

  /// Whether the candle closed at or above its open: drawn green, else red.
  bool get isUp => close >= open;

  @override
  List<Object> get props => [openTime, open, high, low, close, volume];
}
