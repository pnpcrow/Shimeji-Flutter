/// Port of `image/MascotImage.java` and `image/ImagePair.java`.
library;

import 'dart:ui' as ui;

/// A mascot frame: the image plus the anchor point inside it (the point that
/// aligns with the mascot's anchor / feet position).
///
/// [flipped] marks a right-facing image that was produced by horizontally
/// mirroring the left image; the effective anchor is mirrored accordingly.
class MascotImage {
  final ui.Image image;
  final int anchorX;
  final int anchorY;
  final bool flipped;

  /// Coarse alpha grid (8x8-pixel cells, row-major) used for hit testing:
  /// true where any pixel of the cell is opaque.
  final List<bool> alphaMask;
  final int maskCols;
  final int maskRows;

  static const int maskCellSize = 8;

  MascotImage({
    required this.image,
    required this.anchorX,
    required this.anchorY,
    required this.alphaMask,
    required this.maskCols,
    required this.maskRows,
    this.flipped = false,
  });

  /// The effective anchor inside the image (mirrored for flipped images).
  int get centerX => flipped ? image.width - anchorX : anchorX;
  int get centerY => anchorY;

  int get width => image.width;
  int get height => image.height;

  /// Whether the point (in image-local coordinates) lies on an opaque cell.
  /// The x coordinate is mirrored for flipped images, mirroring
  /// `Hotspot.contains` and the Java window `contains` behavior.
  bool hitTest(int x, int y) {
    if (alphaMask.isEmpty) return true;
    var localX = flipped ? width - 1 - x : x;
    if (localX < 0 || localX >= width || y < 0 || y >= height) return false;
    final col = localX ~/ maskCellSize;
    final row = y ~/ maskCellSize;
    if (col >= maskCols || row >= maskRows) return false;
    return alphaMask[row * maskCols + col];
  }

  /// Builds an alpha mask from raw RGBA bytes.
  static MascotImage maskFromBytes({
    required ui.Image image,
    required Uint8ListBytes bytes,
    required int anchorX,
    required int anchorY,
    bool flipped = false,
  }) {
    final w = image.width;
    final h = image.height;
    final cols = (w + maskCellSize - 1) ~/ maskCellSize;
    final rows = (h + maskCellSize - 1) ~/ maskCellSize;
    final mask = List<bool>.filled(cols * rows, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final alpha = bytes[(y * w + x) * 4 + 3];
        if (alpha != 0) {
          mask[(y ~/ maskCellSize) * cols + (x ~/ maskCellSize)] = true;
        }
      }
    }
    return MascotImage(
      image: image,
      anchorX: anchorX,
      anchorY: anchorY,
      alphaMask: mask,
      maskCols: cols,
      maskRows: rows,
      flipped: flipped,
    );
  }
}

typedef Uint8ListBytes = List<int>;

/// A left/right image pair.
class ImagePair {
  final MascotImage leftImage;
  final MascotImage rightImage;

  ImagePair(this.leftImage, this.rightImage);

  MascotImage getImage(bool lookRight) => lookRight ? rightImage : leftImage;
}
