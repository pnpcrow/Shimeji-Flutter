/// Bridge to the per-mascot Flutter-engine windows ("flutter" renderer mode).
///
/// Like the legacy presenter, every mascot owns its own top-level native
/// window, so mascots stay independent desktop objects and can move across
/// monitors (geometry is applied natively in physical screen coordinates, no
/// fullscreen overlay is involved). Instead of `UpdateLayeredWindow`
/// bitmaps, each window hosts a dedicated Flutter engine that paints the
/// current pose, and context menus open in a Flutter-rendered popup window
/// instead of a native Win32 menu.
///
/// Pixel data only travels when the pose actually changes; pure movement is
/// a native `SetWindowPos` with no channel traffic to the mascot engines.
library;

import 'package:flutter/services.dart';

import 'mascot_windows.dart' show MascotSyncState, NativeMenuEntry;

class FlutterMascotWindows {
  static const MethodChannel _channel = MethodChannel('shimeji/mascots');

  static final Set<int> _alive = {};

  /// Pose signature per mascot ("hash:flipped:opacity"); geometry is tracked
  /// separately so movement never re-sends pixels.
  static final Map<int, String> _lastPose = {};
  static final Map<int, String> _lastGeometry = {};

  FlutterMascotWindows._();

  /// Tears down every Flutter-renderer mascot window (engine included) and
  /// resets the bookkeeping. Invoked on app exit and renderer switches.
  static Future<void> destroyAll() async {
    _alive.clear();
    _lastPose.clear();
    _lastGeometry.clear();
    try {
      await _channel.invokeMethod('destroyAllMascotWindows');
    } on PlatformException {
      // Engine teardown is best-effort.
    }
  }

  static Map<String, Object> _encodeItem(NativeMenuEntry item) {
    if (item.separator) {
      return {'separator': true};
    }
    if (item.children != null) {
      return {
        'label': item.label!,
        'id': item.id,
        'children': [for (final child in item.children!) _encodeItem(child)],
      };
    }
    return {'label': item.label!, 'id': item.id, 'checked': item.checked};
  }

  /// Opens the Flutter-rendered context menu window for mascot window [id]
  /// at physical screen position ([x], [y]). Returns the stable id of the
  /// chosen entry, or '' when the menu was dismissed.
  static Future<String> showContextMenu({
    required int id,
    required int x,
    required int y,
    required List<NativeMenuEntry> items,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('showContextMenu', {
        'id': id,
        'x': x,
        'y': y,
        'renderer': 'flutter',
        'items': [for (final item in items) _encodeItem(item)],
      });
      return result ?? '';
    } on PlatformException {
      return '';
    }
  }

  /// Boots the context-menu engine ahead of the first right-click so the
  /// first menu opens without engine start-up latency.
  static Future<void> prewarmContextMenu() async {
    try {
      await _channel.invokeMethod('prewarmContextMenu');
    } on PlatformException {
      // Optional warm-up; ignore.
    }
  }

  /// Creates, updates and destroys the Flutter-rendered windows so they
  /// mirror the given mascots. Called once per engine tick.
  static Future<void> syncMascots(Iterable<MascotSyncState> states) async {
    final aliveNow = <int>{};
    for (final state in states) {
      aliveNow.add(state.id);
      if (!_alive.contains(state.id)) {
        _alive.add(state.id);
        _lastPose.remove(state.id);
        _lastGeometry.remove(state.id);
        try {
          await _channel.invokeMethod('createMascotWindow', {
            'id': state.id,
            'renderer': 'flutter',
          });
        } on PlatformException {
          _alive.remove(state.id);
          continue;
        }
      }

      final pose =
          '${state.imageHash}:${state.flipped}:${state.opacity.toStringAsFixed(3)}';
      final geometry = '${state.x}:${state.y}:${state.width}:${state.height}';
      if (_lastPose[state.id] == pose && _lastGeometry[state.id] == geometry) {
        continue;
      }
      if (state.image == null || state.width <= 0 || state.height <= 0) {
        // No pose yet: nothing to present.
        _lastPose[state.id] = pose;
        _lastGeometry[state.id] = geometry;
        continue;
      }

      // Pixels are attached only when the pose changed since the last send;
      // the native side keeps the latest pose per window (for per-pixel hit
      // testing and delivery to engines that finish booting late).
      final includePixels = _lastPose[state.id] != pose;
      _lastPose[state.id] = pose;
      _lastGeometry[state.id] = geometry;
      try {
        await _channel.invokeMethod('updateMascotWindow', {
          'id': state.id,
          'renderer': 'flutter',
          'x': state.x,
          'y': state.y,
          'w': state.width,
          'h': state.height,
          if (includePixels) ...{
            'hash': state.imageHash,
            'flipped': state.flipped,
            'opacity': state.opacity,
            // Straight (non-premultiplied) RGBA; the mascot engine's Flutter
            // view handles blending, flipping and opacity in the widget tree.
            'bytes': state.image!.rgba,
          },
        });
      } on PlatformException {
        _alive.remove(state.id);
        _lastPose.remove(state.id);
        _lastGeometry.remove(state.id);
      }
    }
    for (final id in _alive.difference(aliveNow).toList()) {
      _alive.remove(id);
      _lastPose.remove(id);
      _lastGeometry.remove(id);
      try {
        await _channel.invokeMethod('destroyMascotWindow', {
          'id': id,
          'renderer': 'flutter',
        });
      } on PlatformException {
        // Ignore.
      }
    }
  }
}
