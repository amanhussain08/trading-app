import 'package:flutter/material.dart';

import '../../chart/view/chart_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.candlestick_chart,
                  size: 72,
                  color: Color(0xFF26A69A),
                ),
                const SizedBox(height: 24),
                Text('Trading App', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Candlestick charts from Binance market data',
                  style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(ChartScreen.route(symbol: 'BTCUSDT', interval: '1h')),
                  icon: const Icon(Icons.show_chart),
                  label: const Text('Open BTC/USDT chart'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
