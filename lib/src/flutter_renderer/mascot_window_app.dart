/// Entry point for the per-mascot Flutter windows ("flutter" renderer mode).
///
/// Each mascot's native window hosts its own Flutter engine running this
/// bootstrap with `['mascot_window', '<windowId>']` entrypoint arguments.
/// The main engine (which owns all shimeji behavior state) forwards the
/// current pose as straight RGBA bytes; this engine merely decodes and
/// paints it. The window itself is borderless, topmost, never activated and
/// per-pixel transparent, with hit testing done natively against the pose
/// alpha — mirroring the legacy layered-window behavior.
///
/// A minimal widget tree (no MaterialApp) keeps start-up fast; a mascot
/// window only ever shows a single sprite.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PoseFrame {
  const PoseFrame({
    required this.image,
    required this.flipped,
    required this.opacity,
    required this.pixels,
  });

  final ui.Image image;
  final bool flipped;
  final double opacity;

  /// Retains the decoded pixel buffer for the lifetime of the frame (the
  /// decode pipeline may reference it asynchronously).
  final Uint8List pixels;
}

Future<void> runMascotWindowApp(String windowId) async {
  WidgetsFlutterBinding.ensureInitialized();
  await MascotWindowController.instance.start(windowId);
  runApp(MascotWindowRoot(controller: MascotWindowController.instance));
}

class MascotWindowController {
  static final MascotWindowController instance = MascotWindowController._();

  MascotWindowController._();

  static const MethodChannel _channel = MethodChannel('shimeji/mascot_view');

  final ValueNotifier<PoseFrame?> frame = ValueNotifier<PoseFrame?>(null);

  /// Decoded images keyed by pose signature; idle animations alternate a
  /// handful of poses, so a small LRU avoids re-decoding on every frame.
  final Map<String, ui.Image> _imageCache = {};
  static const int _imageCacheLimit = 16;

  int _decodeSerial = 0;

  Future<void> start(String windowId) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pose') {
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        if (args != null) _handlePose(args);
      }
      return null;
    });
    // Tell the native side this engine is listening; it (re)sends the
    // cached pose so windows created before the engine finished booting
    // still receive their first frame.
    try {
      await _channel.invokeMethod('ready', {'windowId': windowId});
    } on PlatformException {
      // The window may already be gone; nothing else to do.
    }
  }

  void _handlePose(Map<String, Object?> args) {
    final pixels = args['bytes'] as Uint8List?;
    final width = (args['w'] as num?)?.toInt() ?? 0;
    final height = (args['h'] as num?)?.toInt() ?? 0;
    final flipped = args['flipped'] == true;
    final opacity = ((args['opacity'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.0, 1.0);
    final signature =
        '${args['hash']}:${opacity.toStringAsFixed(3)}:$flipped';
    if (pixels == null || width <= 0 || height <= 0) return;
    if (pixels.length < width * height * 4) return;

    // A newer pose may arrive while an older decode is still running; the
    // serial check keeps stale decodes from overwriting newer frames.
    final serial = ++_decodeSerial;

    final cached = _imageCache.remove(signature);
    if (cached != null) {
      _imageCache[signature] = cached; // Refresh recency.
      frame.value = PoseFrame(
          image: cached, flipped: flipped, opacity: opacity, pixels: pixels);
      return;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    completer.future.then((image) {
      if (serial != _decodeSerial || !_cacheImage(signature, image)) {
        image.dispose();
        return;
      }
      frame.value = PoseFrame(
          image: image, flipped: flipped, opacity: opacity, pixels: pixels);
    });
  }

  bool _cacheImage(String signature, ui.Image image) {
    _imageCache[signature] = image;
    while (_imageCache.length > _imageCacheLimit) {
      final oldestKey = _imageCache.keys.first;
      final oldest = _imageCache[oldestKey];
      // Never dispose the image currently on screen: a repaint (resize, DPI
      // change) after eviction would paint a disposed image.
      if (identical(oldest, frame.value?.image)) break;
      _imageCache.remove(oldestKey)?.dispose();
    }
    return true;
  }
}

class MascotWindowRoot extends StatelessWidget {
  const MascotWindowRoot({super.key, required this.controller});

  final MascotWindowController controller;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<PoseFrame?>(
        valueListenable: controller.frame,
        builder: (context, frame, _) {
          if (frame == null) return const SizedBox.expand();
          final sprite = Transform.flip(
            flipX: frame.flipped,
            child: RawImage(
              image: frame.image,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
            ),
          );
          // Opacity at 1.0 skips the saveLayer entirely.
          return frame.opacity >= 1.0
              ? sprite
              : Opacity(opacity: frame.opacity, child: sprite);
        },
      ),
    );
  }
}
