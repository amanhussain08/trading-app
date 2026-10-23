part of 'chart_bloc.dart';

/// Where the chart is in loading its data, which picks what the screen shows.
enum ChartStatus {
  /// Nothing requested yet.
  initial,

  /// Fetching history; the screen shows a spinner.
  loading,

  /// Candles loaded and the live stream running; the screen shows the chart.
  ready,

  /// The history request failed; the screen shows [ChartState.error].
  failure,
}

/// The chart's data: which market, and its candles. Holds nothing about the
/// view, which lives in the chart's TimeScale and PriceScale.
final class ChartState extends Equatable {
  const ChartState({
    this.status = ChartStatus.initial,
    this.symbol = '',
    this.interval = '',
    this.candles = const [],
    this.error,
  });

  final ChartStatus status;

  /// Market shown, e.g. `BTCUSDT`.
  final String symbol;

  /// Binance interval code, e.g. `1h`; case matters (`1m` vs `1M`).
  final String interval;

  /// Oldest first. Replaced (never mutated) on every update, so widgets can
  /// tell a change with `identical`.
  final List<Candle> candles;

  /// Why loading failed, ready to show; set with [ChartStatus.failure].
  final String? error;

  /// Same market with some fields changed. Symbol and interval can't change
  /// here: a new market starts from a fresh state in [ChartBloc].
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
