import 'package:dio/dio.dart';

import 'market_data_source.dart';
import 'models/candle.dart';

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
  Future<List<Candle>> history(
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
