import 'package:flutter/material.dart';

import 'features/home/view/home_screen.dart';

void main() {
  runApp(const TradingApp());
}

/// The app: a light theme, opening on [HomeScreen].
class TradingApp extends StatelessWidget {
  const TradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trading App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const HomeScreen(),
    );
  }
}
