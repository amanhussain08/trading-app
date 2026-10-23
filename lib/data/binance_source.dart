import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'market_data_source.dart';
import 'models/candle.dart';

/// Binance's public market data, which needs no account or API key: history
/// from the REST endpoint `/api/v3/klines`, live candles from the
/// `<symbol>@kline_<interval>` WebSocket stream.
class BinanceSource implements MarketDataSource {
  BinanceSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://data-api.binance.vision',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;

  @override
  Future<List<Candle>> fetch(
    String symbol,
    String interval, {
    int limit = 1000,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/v3/klines',
        queryParameters: {
          'symbol': symbol,
          'interval': interval,
          'limit': limit,
        },
      );
      final rows = response.data ?? const [];
      return rows
          .map((row) => Candle.fromKline(row as List<dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw MarketDataException(_describe(e));
    }
  }

  /// Opens the kline stream and yields each update to the current candle.
  /// Messages that aren't kline events are skipped. The socket closes when
  /// the listener cancels, or when the server ends the stream; there is no
  /// reconnect.
  @override
  Stream<Candle> live(String symbol, String interval) async* {
    final channel = WebSocketChannel.connect(
      Uri.parse(
        'wss://data-stream.binance.vision/ws/'
        '${symbol.toLowerCase()}@kline_$interval',
      ),
    );
    try {
      await for (final message in channel.stream) {
        final json = jsonDecode(message as String) as Map<String, dynamic>;
        if (json['e'] != 'kline') continue;
        yield Candle.fromStreamKline(json['k'] as Map<String, dynamic>);
      }
    } finally {
      await channel.sink.close();
    }
  }

  /// A message for the chart's error screen: Binance's own error text when
  /// it sent one (e.g. an unknown symbol), otherwise the kind of failure.
  static String _describe(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['msg'] != null) {
      return 'Binance ${e.response?.statusCode}: ${data['msg']}';
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => 'Request timed out',
      DioExceptionType.connectionError => 'No internet connection',
      _ => e.message ?? 'Network error',
    };
  }

  @override
  void dispose() => _dio.close();
}
