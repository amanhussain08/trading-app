# trading-app

A Flutter app that shows a live candlestick chart for Binance markets. It
loads the last 1,000 candles over REST, then keeps the newest candle updated
over a WebSocket. The chart is built like
[Lightweight Charts](https://github.com/tradingview/lightweight-charts):

For more about the app:

Go to folder path /documents



## Requirements

- **Flutter 3.38 or newer** (Dart 3.10.4 or newer; see `environment.sdk` in
`pubspec.yaml`). This project is developed on Flutter 3.38.5. Check yours
with `flutter --version`.
- The toolchain for the platform you want to run on:
  - **Android:** Android Studio with an Android SDK, plus an emulator or a
  phone with USB debugging on.
  - **iOS:** a Mac with Xcode and CocoaPods, plus a simulator or an iPhone.
- **Internet access.** The app reads public market data from Binance
(`data-api.binance.vision` and `data-stream.binance.vision`). No account or
API key is needed.

Run `flutter doctor` and fix anything it reports for your platform before
going further.

## Run the app

```sh
git clone https://github.com/amanhussain08/trading-app.git
cd trading-app
flutter pub get
flutter devices          # list what you can run on
flutter run              # or: flutter run -d <device id>
```

The home screen opens the BTC/USDT chart on the 1-hour interval.

### Use a phone or a simulator

The chart only responds to **touch and stylus**. It ignores the mouse and the
trackpad on purpose. So:

- **Best:** a real phone, an Android emulator or the iOS Simulator. Clicking
and dragging in an emulator or simulator counts as touch, so it works there.
To pinch with two fingers, hold Option in the iOS Simulator, or Ctrl (Cmd
on a Mac) in the Android emulator.
- **Desktop (macOS, Windows, Linux) and web:** the app builds and shows the
chart, but you can't pan, zoom or draw with a mouse.

### Release build

```sh
flutter run --release            # fastest way to judge how smooth it is
flutter build apk --release      # Android APK in build/app/outputs/flutter-apk/
flutter build ios --release      # needs signing set up in Xcode
```

Debug builds are much slower than release builds, so judge scrolling and
zooming in release (or `--profile`) mode.

## Project layout

```text
lib/
  main.dart                     app entry point
  data/                         Binance REST + WebSocket source, Candle model
  features/home/                home screen
  features/chart/
    bloc/                       ChartBloc: loads candles and merges live updates
    scale/                      TimeScale and PriceScale: the chart's view
    drawing/                    drawing model, hit testing and DrawingController
    view/chart_screen.dart      chart screen, with the interval picker
    widgets/                    CandleChart, painters, axes, crosshair, drawings
```

## Troubleshooting

- **"No internet connection" or "Request timed out" on the chart:** the device
can't reach Binance. Check its connection. Some networks and regions block
Binance, in which case try another network or a VPN.
- **Version solving failed in** `flutter pub get`**:** your Flutter is too old.
Run `flutter upgrade`, or install 3.38 or newer.
- **iOS build fails on pods:** run `cd ios && pod install && cd ..`, then
`flutter run` again.
- **The chart doesn't move when you drag:** you're using a mouse or trackpad.
Use a phone, an emulator or the iOS Simulator; see above.
