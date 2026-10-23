part of 'chart_bloc.dart';

enum ChartStatus { initial, loading, ready, failure }

final class ChartState extends Equatable {
  const ChartState({
    this.status = ChartStatus.initial,
    this.symbol = '',
    this.interval = '',
    this.candles = const [],
    this.error,
  });

  final ChartStatus status;
  final String symbol;
  final String interval;

  /// Oldest first. Replaced (never mutated) on every update, so widgets can
  /// tell a change with `identical`.
  final List<Candle> candles;

  final String? error;

  ChartState copyWith({
    ChartStatus? status,
    List<Candle>? candles,
    String? error,
  }) =>
      ChartState(
        status: status ?? this.status,
        symbol: symbol,
        interval: interval,
        candles: candles ?? this.candles,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [status, symbol, interval, candles, error];
}
