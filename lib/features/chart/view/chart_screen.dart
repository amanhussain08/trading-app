import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/binance_source.dart';
import '../../../data/market_data_source.dart';
import '../bloc/chart_bloc.dart';
import '../widgets/candle_chart.dart';

class ChartScreen extends StatelessWidget {
  const ChartScreen({super.key});

  /// Binance kline interval codes offered in the dropdown, with their labels.
  /// Codes are case-sensitive: `1m` is one minute, `1M` is one month.
  static const intervals = {
    '1m': '1m',
    '5m': '5m',
    '15m': '15m',
    '30m': '30m',
    '1h': '1H',
    '4h': '4H',
    '1d': '1D',
    '1w': '1W',
    '1M': '1M',
  };

  /// Pass [source] to supply your own data source (e.g. a fake in tests); the
  /// caller then owns it. Otherwise the route creates a [BinanceSource] and
  /// disposes it when the screen is popped.
  static Route<void> route({
    required String symbol,
    required String interval,
    MarketDataSource? source,
  }) {
    final chart = BlocProvider(
      create: (context) =>
          ChartBloc(context.read<MarketDataSource>())
            ..add(ChartStarted(symbol: symbol, interval: interval)),
      child: const ChartScreen(),
    );

    return MaterialPageRoute(
      builder: (_) => source != null
          ? RepositoryProvider<MarketDataSource>.value(
              value: source,
              child: chart,
            )
          : RepositoryProvider<MarketDataSource>(
              create: (_) => BinanceSource(),
              dispose: (source) => source.dispose(),
              child: chart,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.select((ChartBloc bloc) => bloc.state.symbol);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [Text(symbol), SizedBox(width: 8), _IntervalDropdown()],
        ),
        backgroundColor: Colors.transparent,
        // actions: const [_IntervalDropdown()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BlocBuilder<ChartBloc, ChartState>(
            buildWhen: (previous, current) => previous.status != current.status,
            builder: (context, state) => switch (state.status) {
              ChartStatus.initial || ChartStatus.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              ChartStatus.failure => Center(
                child: Text(state.error ?? 'Something went wrong'),
              ),
              ChartStatus.ready => const CandleChart(),
            },
          ),
        ),
      ),
    );
  }
}

class _IntervalDropdown extends StatelessWidget {
  const _IntervalDropdown();

  @override
  Widget build(BuildContext context) {
    final (symbol, interval) = context.select(
      (ChartBloc bloc) => (bloc.state.symbol, bloc.state.interval),
    );

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: ChartScreen.intervals.containsKey(interval) ? interval : null,
        items: [
          for (final MapEntry(key: code, value: label)
              in ChartScreen.intervals.entries)
            DropdownMenuItem(value: code, child: Text(label)),
        ],
        onChanged: (code) {
          if (code == null || code == interval) return;
          context.read<ChartBloc>().add(
            ChartStarted(symbol: symbol, interval: code),
          );
        },
      ),
    );
  }
}
