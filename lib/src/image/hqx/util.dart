/// Port of hqx-java `Util.java` — YUV comparison and pixel interpolation
/// helpers for the hqx algorithms (LGPL-3.0, see hqx-java licensing).
library;

import 'dart:typed_data';

const int _mask2 = 0x0000FF00;
const int _mask13 = 0x00FF00FF;
const int _maskRgb = 0x00FFFFFF;
const int _maskAlpha = 0xFF000000;

const int _maskY = 0x00FF0000;
const int _maskU = 0x0000FF00;
const int _maskV = 0x000000FF;

final Uint32List _rgbToYuv = _buildRgbToYuvTable();

Uint32List _buildRgbToYuvTable() {
  final table = Uint32List(0x1000000);
  for (var c = 0; c < table.length; c++) {
    final r = (c & 0xFF0000) >>> 16;
    final g = (c & 0x00FF00) >>> 8;
    final b = c & 0x0000FF;
    // YCbCr (JPEG conversion) — matches hqx-java's "YUV".
    final y = (0.299 * r + 0.587 * g + 0.114 * b).truncate();
    final u = (-0.169 * r - 0.331 * g + 0.500 * b).truncate() + 128;
    final v = (0.500 * r - 0.419 * g - 0.081 * b).truncate() + 128;
    table[c] = (y << 16 | u << 8 | v) & 0xFFFFFFFF;
  }
  return table;
}

/// Helpers shared by the hqx scalers.
class HqxUtil {
  HqxUtil._();

  /// The 24-bit YUV equivalent of the provided 24-bit RGB color.
  static int rgbToYuv(int rgb) => _rgbToYuv[rgb & _maskRgb];

  /// Compares two ARGB colors against the Y, U, V and A thresholds.
  /// trY/trU must be pre-shifted (16/8 bits) like the Java original.
  static bool diff(int c1, int c2, int trY, int trU, int trV, int trA) {
    final yuv1 = rgbToYuv(c1);
    final yuv2 = rgbToYuv(c2);

    // The masked component differences fit in 31 bits, so signed comparison
    // on the absolute values matches Java's unsigned comparison here.
    return ((yuv1 & _maskY) - (yuv2 & _maskY)).abs() > trY ||
        ((yuv1 & _maskU) - (yuv2 & _maskU)).abs() > trU ||
        ((yuv1 & _maskV) - (yuv2 & _maskV)).abs() > trV ||
        (((c1 >>> 24) - (c2 >>> 24)).abs() & 0xFFFFFFFF) > trA;
  }

  // (c1*3+c2) >> 2
  static int mix3To1(int c1, int c2) {
    if (c1 == c2) {
      return c1;
    }
    return ((c1 & _mask2) * 3 + (c2 & _mask2) >>> 2 & _mask2 |
            (c1 & _mask13) * 3 + (c2 & _mask13) >>> 2 & _mask13 |
            ((c1 & _maskAlpha) >>> 2) * 3 + ((c2 & _maskAlpha) >>> 2) & _maskAlpha)
        ;
  }

  // (c1*2+c2+c3) >> 2
  static int mix2To1To1(int c1, int c2, int c3) {
    return ((c1 & _mask2) * 2 + (c2 & _mask2) + (c3 & _mask2) >>> 2 & _mask2 |
            (c1 & _mask13) * 2 + (c2 & _mask13) + (c3 & _mask13) >>> 2 & _mask13 |
            ((c1 & _maskAlpha) >>> 2) * 2 +
                    ((c2 & _maskAlpha) >>> 2) +
                    ((c3 & _maskAlpha) >>> 2) &
                _maskAlpha)
        ;
  }

  // (c1*7+c2)/8
  static int mix7To1(int c1, int c2) {
    if (c1 == c2) {
      return c1;
    }
    return ((c1 & _mask2) * 7 + (c2 & _mask2) >>> 3 & _mask2 |
            (c1 & _mask13) * 7 + (c2 & _mask13) >>> 3 & _mask13 |
            ((c1 & _maskAlpha) >>> 3) * 7 + ((c2 & _maskAlpha) >>> 3) & _maskAlpha)
        ;
  }

  // (c1*2+(c2+c3)*7)/16
  static int mix2To7To7(int c1, int c2, int c3) {
    return ((c1 & _mask2) * 2 + (c2 & _mask2) * 7 + (c3 & _mask2) * 7 >>> 4 & _mask2 |
            (c1 & _mask13) * 2 + (c2 & _mask13) * 7 + (c3 & _mask13) * 7 >>> 4 & _mask13 |
            ((c1 & _maskAlpha) >>> 4) * 2 +
                    ((c2 & _maskAlpha) >>> 4) * 7 +
                    ((c3 & _maskAlpha) >>> 4) * 7 &
                _maskAlpha)
        ;
  }

  // (c1+c2) >> 1
  static int mixEven(int c1, int c2) {
    if (c1 == c2) {
      return c1;
    }
    return ((c1 & _mask2) + (c2 & _mask2) >>> 1 & _mask2 |
            (c1 & _mask13) + (c2 & _mask13) >>> 1 & _mask13 |
            ((c1 & _maskAlpha) >>> 1) + ((c2 & _maskAlpha) >>> 1) & _maskAlpha)
        ;
  }

  // (c1*5+c2*2+c3)/8
  static int mix4To2To1(int c1, int c2, int c3) {
    return ((c1 & _mask2) * 5 + (c2 & _mask2) * 2 + (c3 & _mask2) >>> 3 & _mask2 |
            (c1 & _mask13) * 5 + (c2 & _mask13) * 2 + (c3 & _mask13) >>> 3 & _mask13 |
            ((c1 & _maskAlpha) >>> 3) * 5 +
                    ((c2 & _maskAlpha) >>> 3) * 2 +
                    ((c3 & _maskAlpha) >>> 3) &
                _maskAlpha)
        ;
  }

  // (c1*6+c2+c3)/8
  static int mix6To1To1(int c1, int c2, int c3) {
    return ((c1 & _mask2) * 6 + (c2 & _mask2) + (c3 & _mask2) >>> 3 & _mask2 |
            (c1 & _mask13) * 6 + (c2 & _mask13) + (c3 & _mask13) >>> 3 & _mask13 |
            ((c1 & _maskAlpha) >>> 3) * 6 +
                    ((c2 & _maskAlpha) >>> 3) +
                    ((c3 & _maskAlpha) >>> 3) &
                _maskAlpha)
        ;
  }

  // (c1*5+c2*3)/8
  static int mix5To3(int c1, int c2) {
    if (c1 == c2) {
      return c1;
    }
    return ((c1 & _mask2) * 5 + (c2 & _mask2) * 3 >>> 3 & _mask2 |
            (c1 & _mask13) * 5 + (c2 & _mask13) * 3 >>> 3 & _mask13 |
            ((c1 & _maskAlpha) >>> 3) * 5 + ((c2 & _maskAlpha) >>> 3) * 3 & _maskAlpha)
        ;
  }

  // (c1*2+(c2+c3)*3)/8
  static int mix2To3To3(int c1, int c2, int c3) {
    return ((c1 & _mask2) * 2 + (c2 & _mask2) * 3 + (c3 & _mask2) * 3 >>> 3 & _mask2 |
            (c1 & _mask13) * 2 + (c2 & _mask13) * 3 + (c3 & _mask13) * 3 >>> 3 & _mask13 |
            ((c1 & _maskAlpha) >>> 3) * 2 +
                    ((c2 & _maskAlpha) >>> 3) * 3 +
                    ((c3 & _maskAlpha) >>> 3) * 3 &
                _maskAlpha)
        ;
  }

  // (c1*14+c2+c3)/16
  static int mix14To1To1(int c1, int c2, int c3) {
    return ((c1 & _mask2) * 14 + (c2 & _mask2) + (c3 & _mask2) >>> 4 & _mask2 |
            (c1 & _mask13) * 14 + (c2 & _mask13) + (c3 & _mask13) >>> 4 & _mask13 |
            ((c1 & _maskAlpha) >>> 4) * 14 +
                    ((c2 & _maskAlpha) >>> 4) +
                    ((c3 & _maskAlpha) >>> 4) &
                _maskAlpha)
        ;
  }
}
