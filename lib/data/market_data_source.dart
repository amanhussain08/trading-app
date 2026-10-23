import 'models/candle.dart';

/// Where the chart gets its candles: a one-off history request, then a live
/// stream. [BinanceSource] is the real one; tests pass a mock.
abstract interface class MarketDataSource {
  /// Most recent [limit] candles, oldest first. [symbol] is a market such as
  /// `BTCUSDT`, [interval] a Binance code such as `1m`, `1h` or `1M`.
  /// Throws [MarketDataException] with a readable message on failure.
  Future<List<Candle>> fetch(
    String symbol,
    String interval, {
    int limit = 1000,
  });

  /// Updates to the newest candle as they happen: the forming candle again
  /// whenever it changes, then the next one once its interval starts.
  /// Cancelling the subscription closes the connection.
  Stream<Candle> live(String symbol, String interval);

  /// Releases connections; the source can't be used afterwards.
  void dispose();
}

/// A failed request, with a [message] short enough to show on screen as is.
class MarketDataException implements Exception {
  const MarketDataException(this.message);

  final String message;

  @override
  String toString() => message;
}
