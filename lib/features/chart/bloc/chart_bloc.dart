import 'dart:math' as math;

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/market_data_source.dart';
import '../../../data/models/candle.dart';

part 'chart_event.dart';
part 'chart_state.dart';

class ChartBloc extends Bloc<ChartEvent, ChartState> {
  ChartBloc(this._source) : super(const ChartState()) {
    on<ChartStarted>(_onStarted, transformer: restartable());
    on<ChartVisibleRangeChanged>(_onVisibleRangeChanged);
    on<ChartPricePanned>(_onPricePanned);
    on<ChartPriceScaled>(_onPriceScaled);
    on<ChartAutoScaleReset>(_onAutoScaleReset);
  }

  /// Binance's maximum candles per klines request.
  static const historyLimit = 1000;

  /// How many candles fit across the chart's width before any zooming.
  static const initialVisibleCount = 50;

  final MarketDataSource _source;

  Future<void> _onStarted(ChartStarted event, Emitter<ChartState> emit) async {
    emit(
      ChartState(
        status: ChartStatus.loading,
        symbol: event.symbol,
        interval: event.interval,
      ),
    );
    try {
      final candles = await _source.history(
        event.symbol,
        event.interval,
        limit: historyLimit,
      );
      final loaded = state.copyWith(
        status: ChartStatus.ready,
        candles: candles,
      );
      emit(
        _withVisibleRange(
          loaded,
          candles.length - initialVisibleCount,
          candles.length - 1,
        ),
      );
    } catch (error) {
      emit(state.copyWith(status: ChartStatus.failure, error: '$error'));
    }
  }

  void _onVisibleRangeChanged(
    ChartVisibleRangeChanged event,
    Emitter<ChartState> emit,
  ) {
    if (state.candles.isEmpty) return;
    emit(_withVisibleRange(state, event.from, event.to));
  }

  static ChartState _withVisibleRange(ChartState state, int from, int to) {
    final candles = state.candles;
    if (candles.isEmpty) return state;

    final last = candles.length - 1;
    final start = from.clamp(0, last);
    final end = to.clamp(start, last);

    var low = candles[start].low;
    var high = candles[start].high;
    var volumeMax = 0.0;
    for (var i = start; i <= end; i++) {
      low = math.min(low, candles[i].low);
      high = math.max(high, candles[i].high);
      volumeMax = math.max(volumeMax, candles[i].volume);
    }
    final padding = high > low
        ? (high - low) * 0.05
        : math.max(high.abs() * 0.01, 1.0);

    return state.copyWith(
      visibleFrom: start,
      visibleTo: end,
      priceLow: low - padding,
      priceHigh: high + padding,
      volumeMax: volumeMax,
      autoScale: true,
    );
  }

  void _onPricePanned(ChartPricePanned event, Emitter<ChartState> emit) {
    final range = state.priceHigh - state.priceLow;
    if (range <= 0) return;
    final shift = event.fraction * range;
    emit(
      state.copyWith(
        priceLow: state.priceLow + shift,
        priceHigh: state.priceHigh + shift,
        autoScale: false,
      ),
    );
  }

  void _onPriceScaled(ChartPriceScaled event, Emitter<ChartState> emit) {
    final range = state.priceHigh - state.priceLow;
    if (range <= 0 || event.factor <= 0) return;
    final middle = (state.priceLow + state.priceHigh) / 2;
    final half = range * event.factor / 2;
    emit(
      state.copyWith(
        priceLow: middle - half,
        priceHigh: middle + half,
        autoScale: false,
      ),
    );
  }

  void _onAutoScaleReset(ChartAutoScaleReset event, Emitter<ChartState> emit) {
    emit(_withVisibleRange(state, state.visibleFrom, state.visibleTo));
  }
}
