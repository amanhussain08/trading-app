import 'models/candle.dart';

abstract interface class MarketDataSource {
  /// Most recent [limit] candles, oldest first.
  Future<List<Candle>> fetch(
    String symbol,
    String interval, {
    int limit = 1000,
  });

  void dispose();
}

class MarketDataException implements Exception {
  const MarketDataException(this.message);

  final String message;

  @override
  String toString() => message;
}
