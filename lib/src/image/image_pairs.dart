/// Port of `image/ImagePairs.java` plus the image-scaling parts of
/// `image/ImageUtils.java`.
///
/// Images are individual PNG files inside an image set directory. Frames are
/// decoded once per (anchor, path) key, scaled according to the global
/// scaling setting, and cached. The right-facing image is either loaded from
/// disk or produced by horizontally mirroring the left image.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../image/mascot_image.dart';
import 'filter.dart';

/// Java Math.round(double): floor(x + 0.5).
int javaRound(double x) => (x + 0.5).floor();

class ImagePairs {
  static final Map<String, ImagePair> _imagePairs = {};
  static final Map<String, List<String>> _imageSetsToImagePairs = {};

  /// Resolves paths relative to the image directory (img/).
  static late String Function(String path) resolveImagePath;

  ImagePairs._();

  static bool contains(String key) => _imagePairs.containsKey(key);

  /// Number of cached image pairs (diagnostics).
  static int get count => _imagePairs.length;

  static ImagePair? get(String? key) =>
      key == null ? null : _imagePairs[key];

  static void addUsage(String imagePair, String imageSet) {
    _imageSetsToImagePairs.putIfAbsent(imageSet, () => []);
    if (!_imageSetsToImagePairs[imageSet]!.contains(imagePair)) {
      _imageSetsToImagePairs[imageSet]!.add(imagePair);
    }
  }

  /// Evicts every cached pair of [imageSet], disposing the decoded
  /// [ui.Image]s. Called when a set is unloaded or re-decoded (scaling
  /// change); without it every reload would accumulate the full decode of
  /// every set ever shown until the engine runs out of memory.
  static void removeAll(String imageSet) {
    final keys = _imageSetsToImagePairs.remove(imageSet);
    if (keys == null) return;
    for (final key in keys) {
      _imagePairs.remove(key)?.dispose();
    }
  }

  static void clear() {
    for (final pair in _imagePairs.values) {
      pair.dispose();
    }
    _imagePairs.clear();
    _imageSetsToImagePairs.clear();
  }

  /// Loads an image pair. Returns the cache key.
  ///
  /// The key encodes scaling and filter, so a change of either re-decodes
  /// instead of silently serving the stale size (callers must evict the old
  /// entries via [removeAll]).
  static Future<String> load(
    String path,
    String? rightPath,
    int anchorX,
    int anchorY,
    double scaling,
    Filter filter,
  ) async {
    var key = '$anchorX,$anchorY:${scaling.toStringAsFixed(4)}:'
        '${filter.name}:$path';
    if (rightPath != null) key += ':$rightPath';
    if (_imagePairs.containsKey(key)) return key;

    final leftBytes = await File(resolveImagePath(path)).readAsBytes();
    final leftImage = await _decode(leftBytes);
    final leftScaled = await _scale(leftImage, scaling, filter);
    // _scale returns the source itself when no scaling applies; otherwise
    // the decoded original is an intermediate and must be freed.
    if (!identical(leftScaled, leftImage)) leftImage.dispose();
    final scaledAnchorX = javaRound(anchorX * scaling);
    final scaledAnchorY = javaRound(anchorY * scaling);

    final left = await _mascotImage(leftScaled, scaledAnchorX, scaledAnchorY);

    final MascotImage right;
    if (rightPath == null) {
      // Mirror the left image: same bitmap, mirrored anchor and hit mask.
      right = MascotImage(
        image: left.image,
        anchorX: scaledAnchorX,
        anchorY: scaledAnchorY,
        alphaMask: left.alphaMask,
        maskCols: left.maskCols,
        maskRows: left.maskRows,
        rgba: left.rgba,
        flipped: true,
      );
    } else {
      final rightBytes = await File(resolveImagePath(rightPath)).readAsBytes();
      final rightImage = await _decode(rightBytes);
      final rightScaled = await _scale(rightImage, scaling, filter);
      if (!identical(rightScaled, rightImage)) rightImage.dispose();
      right = await _mascotImage(rightScaled, scaledAnchorX, scaledAnchorY);
    }

    _imagePairs[key] = ImagePair(left, right);
    return key;
  }

  static Future<ui.Image> _decode(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<MascotImage> _mascotImage(
      ui.Image image, int anchorX, int anchorY) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    return MascotImage.maskFromBytes(
      image: image,
      bytes: bytes,
      anchorX: anchorX,
      anchorY: anchorY,
    );
  }

  /// Port of ImageUtils.scale: applies hqx for integral 2x/3x/4x scaling,
  /// then rescales the remainder with nearest-neighbour or bicubic
  /// interpolation.
  ///
  /// Returns [source] itself when no scaling applies; otherwise the caller
  /// owns the result and [source] (if different) must be disposed by it.
  /// The hqx intermediate is disposed here.
  static Future<ui.Image> _scale(
      ui.Image source, double scaling, Filter filter) async {
    if (scaling == 1) return source;

    var effectiveScaling = scaling;
    ui.Image working = source;

    if (filter == Filter.hqx && scaling > 1) {
      var hqxType = 0;
      if (_isMultiple(scaling, 4)) {
        hqxType = 4;
      } else if (_isMultiple(scaling, 3)) {
        hqxType = 3;
      } else if (_isMultiple(scaling, 2)) {
        hqxType = 2;
      }
      if (hqxType > 0) {
        working = await _applyHqx(source, hqxType);
        effectiveScaling = scaling / hqxType;
      }
      // Otherwise fall back to nearest-neighbour below.
    }

    if (effectiveScaling == 1) return working;

    final width = javaRound(working.width * effectiveScaling);
    final height = javaRound(working.height * effectiveScaling);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..filterQuality = filter == Filter.bicubic
          ? ui.FilterQuality.high
          : ui.FilterQuality.none
      ..isAntiAlias = false;
    canvas.drawImageRect(
      working,
      ui.Rect.fromLTWH(0, 0, working.width.toDouble(), working.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final scaled = picture.toImageSync(width, height);
    picture.dispose();
    // The hqx output was only an intermediate for the canvas draw.
    if (!identical(working, source)) working.dispose();
    return scaled;
  }

  static bool _isMultiple(double scaling, int n) {
    final quotient = scaling / n;
    return (quotient - quotient.roundToDouble()).abs() < 1e-9;
  }

  /// Hook for the hqx scaler (ported in `hqx.dart`). Set at startup.
  static Future<ui.Image> Function(ui.Image source, int factor)? hqxScaler;

  static Future<ui.Image> _applyHqx(ui.Image source, int factor) async {
    final scaler = hqxScaler;
    if (scaler == null) return source;
    try {
      return await scaler(source, factor);
    } catch (e) {
      // A broken custom scaler must not take the whole image set down.
      assert(() {
        // ignore: avoid_print
        print('hqx scaling failed ($factor x): $e');
        return true;
      }());
      return source;
    }
  }
}
