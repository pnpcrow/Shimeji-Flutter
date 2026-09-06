/// Bridge to the per-mascot native layered windows.
///
/// Mirrors the Java original's per-mascot translucent window: every mascot
/// owns a top-level `UpdateLayeredWindow` window presenting its current pose.
/// True per-pixel alpha gives automatic invisibility and click-through where
/// the sprite is transparent, independent of DWM accent support.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../image/mascot_image.dart';

class NativeMenuEntry {
  final String? label;
  final bool checked;
  final bool separator;

  /// Stable identifier echoed back by the native side when this entry is
  /// chosen. Position-independent, so separators/submenus cannot shift it.
  final String id;

  /// Nested popup entries; non-null turns this item into a submenu.
  final List<NativeMenuEntry>? children;

  const NativeMenuEntry.label(this.label,
      {required this.id, this.checked = false})
      : separator = false,
        children = null;
  const NativeMenuEntry.separator()
      : label = null,
        checked = false,
        separator = true,
        id = '',
        children = null;
  const NativeMenuEntry.submenu(this.label, this.children, {required this.id})
      : checked = false,
        separator = false;
}

class MascotNativeWindows {
  static const MethodChannel _channel = MethodChannel('shimeji/mascots');

  static final Set<int> _nativeAlive = {};

  /// Premultiplied BGRA bytes per (pose, flip, opacity). This can be large
  /// (width * height * 4 bytes per pose, 1 MB at 4x scaling of a 128px
  /// sprite), so it is bounded: least-recently-used entries are evicted
  /// once the budget is exceeded. Evicted poses are simply re-prepared the
  /// next time they are shown.
  static const int _bitmapCacheBudget = 64 * 1024 * 1024;
  static final Map<String, Uint8List> _bitmapCache = {};
  static int _bitmapCacheBytes = 0;
  static final Map<int, String> _lastSent = {};

  MascotNativeWindows._();

  /// Clears the prepared-bitmap cache (image sets changed).
  static void clearCache() {
    _bitmapCache.clear();
    _bitmapCacheBytes = 0;
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

  /// Opens a native popup menu for the mascot window [id] at physical screen
  /// position ([x], [y]). Returns the index into [items] of the chosen entry,
  /// or -1 when the menu was dismissed.
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
        'items': [for (final item in items) _encodeItem(item)],
      });
      return result ?? '';
    } on PlatformException {
      return '';
    }
  }

  static Future<void> destroyAll() async {
    _nativeAlive.clear();
    _lastSent.clear();
    try {
      await _channel.invokeMethod('destroyAllMascotWindows');
    } on PlatformException {
      // Engine teardown is best-effort.
    }
  }

  /// Prepares (and caches) the premultiplied BGRA bytes for a pose. [flipped]
  /// mirrors the sprite horizontally, matching the right-facing image.
  static Uint8List _prepareBitmap(
      MascotImage image, bool flipped, double opacity) {
    final key =
        '${identityHashCode(image)}:$flipped:${opacity.toStringAsFixed(3)}';
    // Re-inserting on hit refreshes recency (insertion-ordered map).
    final cached = _bitmapCache.remove(key);
    if (cached != null) {
      _bitmapCache[key] = cached;
      return cached;
    }

    final w = image.width;
    final h = image.height;
    final src = image.rgba;
    final out = Uint8List(w * h * 4);
    final alphaScale = opacity.clamp(0.0, 1.0);
    for (var y = 0; y < h; y++) {
      final srcRow = y * w;
      final dstRow = y * w;
      for (var x = 0; x < w; x++) {
        final sx = flipped ? (w - 1 - x) : x;
        final si = (srcRow + sx) * 4;
        final di = (dstRow + x) * 4;
        final a = (src[si + 3] * alphaScale).round();
        out[di] = (src[si + 2] * a) ~/ 255; // B (premultiplied)
        out[di + 1] = (src[si + 1] * a) ~/ 255; // G
        out[di + 2] = (src[si] * a) ~/ 255; // R
        out[di + 3] = a; // A
      }
    }
    _bitmapCache[key] = out;
    _bitmapCacheBytes += out.length;
    while (_bitmapCacheBytes > _bitmapCacheBudget && _bitmapCache.length > 1) {
      final oldest = _bitmapCache.keys.first;
      _bitmapCacheBytes -= _bitmapCache.remove(oldest)!.length;
    }
    return out;
  }

  /// Creates, updates and destroys the native windows so they mirror the
  /// given mascots. Called once per engine tick; only actual changes are
  /// pushed to the platform channel.
  static Future<void> syncMascots(Iterable<MascotSyncState> states) async {
    final aliveNow = <int>{};
    for (final state in states) {
      aliveNow.add(state.id);
      if (!_nativeAlive.contains(state.id)) {
        _nativeAlive.add(state.id);
        try {
          await _channel.invokeMethod('createMascotWindow', {'id': state.id});
        } on PlatformException {
          _nativeAlive.remove(state.id);
          continue;
        }
      }
      final signature = '${state.imageHash}:${state.x}:${state.y}:'
          '${state.width}:${state.height}:${state.opacity.toStringAsFixed(3)}';
      if (_lastSent[state.id] == signature) continue;

      if (state.image == null || state.width <= 0 || state.height <= 0) {
        // No pose yet: hide by moving off-screen is unnecessary; skip.
        _lastSent[state.id] = signature;
        continue;
      }
      final bytes = _prepareBitmap(state.image!, state.flipped, state.opacity);
      _lastSent[state.id] = signature;
      try {
        await _channel.invokeMethod('updateMascotWindow', {
          'id': state.id,
          'x': state.x,
          'y': state.y,
          'w': state.width,
          'h': state.height,
          'bytes': bytes,
        });
      } on PlatformException {
        _nativeAlive.remove(state.id);
      }
    }
    for (final id in _nativeAlive.difference(aliveNow).toList()) {
      _nativeAlive.remove(id);
      _lastSent.remove(id);
      try {
        await _channel.invokeMethod('destroyMascotWindow', {'id': id});
      } on PlatformException {
        // Ignore.
      }
    }
  }
}

/// Per-tick presentation state of one mascot.
class MascotSyncState {
  final int id;
  final MascotImage? image;
  final int imageHash;
  final bool flipped;
  final int x;
  final int y;
  final int width;
  final int height;
  final double opacity;

  const MascotSyncState({
    required this.id,
    required this.image,
    required this.imageHash,
    required this.flipped,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.opacity,
  });
}
