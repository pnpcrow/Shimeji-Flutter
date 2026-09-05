/// Bridge between the Dart engine and the Windows runner.
///
/// The runner hosts a single transparent always-on-top overlay window. Dart
/// pushes per-mascot hit rectangles (with coarse alpha masks) and UI regions
/// to the runner; the runner decides per mouse event whether the overlay
/// accepts input (over a mascot or UI region) or lets events fall through to
/// the windows beneath.
library;

import 'package:flutter/services.dart';

/// One clickable mascot region in physical pixels.
class HitRect {
  final int x;
  final int y;
  final int width;
  final int height;
  final int maskCols;
  final int maskRows;
  final int cellSize;

  /// Row-major bitmask, one bit per cell, true where the cell is opaque.
  final List<int> maskBits;

  const HitRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.maskCols,
    required this.maskRows,
    required this.cellSize,
    required this.maskBits,
  });

  Map<String, Object> toMap() => {
        'x': x,
        'y': y,
        'w': width,
        'h': height,
        'cols': maskCols,
        'rows': maskRows,
        'cell': cellSize,
        'mask': maskBits,
      };
}

class UiRect {
  final int x;
  final int y;
  final int width;
  final int height;
  const UiRect(this.x, this.y, this.width, this.height);

  Map<String, Object> toMap() => {'x': x, 'y': y, 'w': width, 'h': height};
}

class OverlayController {
  static const MethodChannel _channel = MethodChannel('shimeji/overlay');

  /// The overlay window bounds in physical pixels (updated by the runner).
  static int windowX = 0;
  static int windowY = 0;
  static int windowWidth = 0;
  static int windowHeight = 0;

  /// Whether the last known bounds have been received from the runner.
  static bool hasBounds = false;

  static Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleCall);
  }

  static Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'windowBounds':
        final args = Map<dynamic, dynamic>.from(call.arguments as Map);
        windowX = (args['x'] as num).toInt();
        windowY = (args['y'] as num).toInt();
        windowWidth = (args['w'] as num).toInt();
        windowHeight = (args['h'] as num).toInt();
        hasBounds = true;
        return null;
    }
    return null;
  }

  /// Resizes/moves the overlay to cover the given physical rect.
  static Future<void> setWindowBounds(int x, int y, int w, int h) async {
    await _channel.invokeMethod('setWindowBounds',
        {'x': x, 'y': y, 'w': w, 'h': h});
    windowX = x;
    windowY = y;
    windowWidth = w;
    windowHeight = h;
    hasBounds = true;
  }

  /// Sets the clickable mascot regions (physical pixels).
  static Future<void> setHitRects(List<HitRect> rects) async {
    await _channel
        .invokeMethod('setHitRects', {'rects': rects.map((r) => r.toMap()).toList()});
  }

  /// Sets UI regions (menus/panels) that accept input.
  static Future<void> setUiRects(List<UiRect> rects) async {
    await _channel
        .invokeMethod('setUiRects', {'rects': rects.map((r) => r.toMap()).toList()});
  }

  /// Forces full click-through (true) or full input (false). Pass null to
  /// return to per-region hit testing.
  static Future<void> setClickThrough(bool? enabled) async {
    await _channel.invokeMethod('setClickThrough', {'enabled': enabled});
  }

  /// Toggles the always-on-top flag.
  static Future<void> setTopmost(bool topmost) async {
    await _channel.invokeMethod('setTopmost', {'topmost': topmost});
  }
}
