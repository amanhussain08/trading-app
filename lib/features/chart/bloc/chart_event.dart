part of 'chart_bloc.dart';

sealed class ChartEvent {
  const ChartEvent();
}

final class ChartStarted extends ChartEvent {
  const ChartStarted({required this.symbol, required this.interval});

  final String symbol;
  final String interval;
}

/// The chart scrolled so that candles [from]..[to] (inclusive) are on screen.
final class ChartVisibleRangeChanged extends ChartEvent {
  const ChartVisibleRangeChanged({required this.from, required this.to});

  final int from;
  final int to;
}

/// The user dragged the chart vertically by [fraction] of the price pane's
/// height (positive = down). Turns auto-scale off.
final class ChartPricePanned extends ChartEvent {
  const ChartPricePanned(this.fraction);

  final double fraction;
}

/// The user dragged the price axis; the price range is multiplied by [factor]
/// around its middle (> 1 compresses the candles). Turns auto-scale off.
final class ChartPriceScaled extends ChartEvent {
  const ChartPriceScaled(this.factor);

  final double factor;
}

/// Fit the price range to the visible candles again, and keep doing so.
final class ChartAutoScaleReset extends ChartEvent {
  const ChartAutoScaleReset();
}
