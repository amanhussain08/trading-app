import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/market_data_source.dart';
import '../../../data/models/candle.dart';
import '../chart_log.dart';

part 'chart_event.dart';
part 'chart_state.dart';

/// Loads a symbol's candles and keeps them live. Data only: what is on
/// screen (scroll, zoom, price range) lives in the chart's TimeScale and
/// PriceScale, as Lightweight Charts keeps its model apart from the view.
class ChartBloc extends Bloc<ChartEvent, ChartState> {
  ChartBloc(this._source) : super(const ChartState()) {
    on<ChartStarted>(_onStarted, transformer: restartable());
  }

  /// Binance's maximum candles per klines request.
  static const historyLimit = 1000;

  final MarketDataSource _source;

  Future<void> _onStarted(ChartStarted event, Emitter<ChartState> emit) async {
    ChartLog.info('bloc', 'loading ${event.symbol} ${event.interval}');
    emit(
      ChartState(
        status: ChartStatus.loading,
        symbol: event.symbol,
        interval: event.interval,
      ),
    );
    final List<Candle> candles;
    try {
      candles = await _source.fetch(
        event.symbol,
        event.interval,
        limit: historyLimit,
      );
    } catch (error) {
      ChartLog.info('bloc', 'load failed: $error');
      emit(state.copyWith(status: ChartStatus.failure, error: '$error'));
      return;
    }
    ChartLog.info('bloc', 'loaded ${candles.length} candles, going live');
    emit(
      state.copyWith(
        status: ChartStatus.ready,
        candles: List.unmodifiable(candles),
      ),
    );

    // Runs until the next ChartStarted (restartable) or close cancels it. A
    // dropped connection leaves the chart showing what it has.
    await emit.forEach<Candle>(
      _source.live(event.symbol, event.interval),
      onData: (candle) => _withLiveCandle(state, candle),
      onError: (error, _) {
        ChartLog.info('bloc', 'live stream error, keeping what we have: $error');
        return state;
      },
    );
  }

  /// Merges a live update: replaces the forming candle, or appends the next
  /// one. Older candles than the newest are ignored.
  static ChartState _withLiveCandle(ChartState state, Candle candle) {
    final candles = state.candles;
    if (candles.isNotEmpty && candle.openTime.isBefore(candles.last.openTime)) {
      ChartLog.info('bloc', 'ignored stale candle at ${candle.openTime}');
      return state;
    }
    final appended =
        candles.isEmpty || candle.openTime.isAfter(candles.last.openTime);
    if (appended) {
      ChartLog.info('bloc', 'new candle at ${candle.openTime} close=${candle.close}');
    } else {
      ChartLog.frame('bloc', 'tick close=${candle.close}');
    }
    return state.copyWith(
      candles: List.unmodifiable([
        ...appended ? candles : candles.take(candles.length - 1),
        candle,
      ]),
    );
  }
}
