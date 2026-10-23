part of 'chart_bloc.dart';

/// Input to [ChartBloc]. View changes (pan, zoom, price drag) aren't events:
/// they stay in the chart's scales and never reach the bloc.
sealed class ChartEvent {
  const ChartEvent();
}

/// Load [symbol] at [interval] and keep it live. Sent when the chart opens
/// and again when the interval changes; the new one cancels the previous
/// load and live stream.
final class ChartStarted extends ChartEvent {
  const ChartStarted({required this.symbol, required this.interval});

  final String symbol;
  final String interval;
}
