/// The CustomPainter that renders every mascot onto the transparent overlay.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../image/mascot_image.dart';

class MascotPainter extends CustomPainter {
  final List<MascotRender> mascots;
  final bool drawBounds;

  MascotPainter(this.mascots, {required this.drawBounds});

  @override
  void paint(Canvas canvas, Size size) {
    for (final render in mascots) {
      final image = render.image;
      final rect = render.bounds;
      if (rect.width <= 0 || rect.height <= 0) continue;
      final paint = ui.Paint()
        ..isAntiAlias = false
        ..filterQuality = ui.FilterQuality.none
        ..color = ui.Color.fromRGBO(255, 255, 255, render.opacity);

      void draw({required bool flipped}) {
        if (flipped) {
          canvas.save();
          canvas.translate(rect.left + rect.width, rect.top);
          canvas.scale(-1, 1);
          canvas.drawImage(image.image, ui.Offset.zero, paint);
          canvas.restore();
        } else {
          canvas.drawImage(image.image, rect.topLeft, paint);
        }
      }

      draw(flipped: image.flipped);

      if (drawBounds) {
        final border = ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const ui.Color(0xFF0000FF);
        canvas.drawRect(rect, border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MascotPainter oldDelegate) => true;
}

/// The per-mascot render state captured each frame (logical coordinates).
class MascotRender {
  final MascotImage image;
  final Rect bounds;
  final double opacity;
  const MascotRender(this.image, this.bounds, this.opacity);
}
