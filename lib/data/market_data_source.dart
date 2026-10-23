import 'models/candle.dart';

abstract interface class MarketDataSource {
  /// Most recent [limit] candles, oldest first.
  Future<List<Candle>> fetch(
    String symbol,
    String interval, {
    int limit = 1000,
  });

  /// Updates to the newest candle as they happen: the forming candle again
  /// whenever it changes, then the next one once its interval starts.
  /// Cancelling the subscription closes the connection.
  Stream<Candle> live(String symbol, String interval);

  void dispose();
}

class MarketDataException implements Exception {
  const MarketDataException(this.message);

  final String message;

  @override
  String toString() => message;
}
