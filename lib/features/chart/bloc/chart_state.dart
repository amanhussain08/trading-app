part of 'chart_bloc.dart';

enum ChartStatus { initial, loading, ready, failure }

final class ChartState extends Equatable {
  const ChartState({
    this.status = ChartStatus.initial,
    this.symbol = '',
    this.interval = '',
    this.candles = const [],
    this.visibleFrom = 0,
    this.visibleTo = -1,
    this.priceLow = 0,
    this.priceHigh = 0,
    this.volumeMax = 0,
    this.autoScale = true,
    this.error,
  });

  final ChartStatus status;
  final String symbol;
  final String interval;
  final List<Candle> candles;

  /// Inclusive indices into [candles] of what is currently on screen.
  final int visibleFrom;
  final int visibleTo;

  /// Price range shown in the price pane, top to bottom.
  final double priceLow;
  final double priceHigh;

  /// Largest volume among the visible candles; scales the volume pane.
  final double volumeMax;

  /// Whether [priceLow]/[priceHigh] fit the visible candles. Turned off when
  /// the user pans or scales prices by hand; back on as soon as the visible
  /// candles change (scroll or zoom) or on double-tap.
  final bool autoScale;

  final String? error;

  ChartState copyWith({
    ChartStatus? status,
    List<Candle>? candles,
    int? visibleFrom,
    int? visibleTo,
    double? priceLow,
    double? priceHigh,
    double? volumeMax,
    bool? autoScale,
    String? error,
  }) =>
      ChartState(
        status: status ?? this.status,
        symbol: symbol,
        interval: interval,
        candles: candles ?? this.candles,
        visibleFrom: visibleFrom ?? this.visibleFrom,
        visibleTo: visibleTo ?? this.visibleTo,
        priceLow: priceLow ?? this.priceLow,
        priceHigh: priceHigh ?? this.priceHigh,
        volumeMax: volumeMax ?? this.volumeMax,
        autoScale: autoScale ?? this.autoScale,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [
        status,
        symbol,
        interval,
        candles,
        visibleFrom,
        visibleTo,
        priceLow,
        priceHigh,
        volumeMax,
        autoScale,
        error,
      ];
}
