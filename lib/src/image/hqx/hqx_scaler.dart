/// Bridges Flutter [ui.Image]s to the hqx scalers (which operate on packed
/// ARGB int arrays, like Java's `BufferedImage.getRGB`).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'hq2x.dart';
import 'hq3x.dart';
import 'hq4x.dart';

/// Upscales [source] by exactly [factor]x (2, 3 or 4) using hqx.
Future<ui.Image> applyHqx(ui.Image source, int factor) async {
  final w = source.width;
  final h = source.height;
  final data = await source.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final rgba = data!.buffer.asUint8List();

  final src = Int32List(w * h);
  for (var i = 0; i < w * h; i++) {
    final r = rgba[i * 4];
    final g = rgba[i * 4 + 1];
    final b = rgba[i * 4 + 2];
    final a = rgba[i * 4 + 3];
    src[i] = (a << 24) | (r << 16) | (g << 8) | b;
  }

  final dw = w * factor;
  final dh = h * factor;
  final dst = Int32List(dw * dh);
  switch (factor) {
    case 2:
      Hq2x.scale2(src, dst, w, h);
    case 3:
      Hq3x.scale3(src, dst, w, h);
    case 4:
      Hq4x.scale4(src, dst, w, h);
    default:
      throw ArgumentError('Unsupported hqx factor: $factor');
  }

  final out = Uint8List(dw * dh * 4);
  for (var i = 0; i < dw * dh; i++) {
    final argb = dst[i];
    out[i * 4] = (argb >>> 16) & 0xFF;
    out[i * 4 + 1] = (argb >>> 8) & 0xFF;
    out[i * 4 + 2] = argb & 0xFF;
    out[i * 4 + 3] = (argb >>> 24) & 0xFF;
  }

  final buffer = await ui.ImmutableBuffer.fromUint8List(out);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: dw,
    height: dh,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  // The buffer/descriptor/codec are decode intermediates only; the frame
  // owns its image from here.
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}
