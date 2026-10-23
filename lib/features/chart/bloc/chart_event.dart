part of 'chart_bloc.dart';

sealed class ChartEvent {
  const ChartEvent();
}

final class ChartStarted extends ChartEvent {
  const ChartStarted({required this.symbol, required this.interval});

  final String symbol;
  final String interval;
}
