/// Port of `animation/Pose.java`, `animation/Animation.java` and
/// `animation/Hotspot.java`.
library;

import '../environment/area.dart' show JPoint;
import '../image/image_pairs.dart';
import '../script/variable_map.dart';

/// One frame of an animation. [dx]/[dy] are pre-scaled per-tick movement;
/// `dx` is in the direction the mascot faces (left-positive) and is negated
/// when the mascot looks right (Java Pose.apply semantics).
class Pose {
  final String? imageKey;
  final int dx;
  final int dy;
  final int duration;
  final String? soundKey;

  const Pose({
    required this.imageKey,
    required this.dx,
    required this.dy,
    required this.duration,
    required this.soundKey,
  });

  void apply(dynamic mascot) {
    mascot.anchor.translate(mascot.lookRight ? -dx : dx, dy);
    mascot.setImage((imageKey == null || !ImagePairs.contains(imageKey!))
        ? null
        : ImagePairs.get(imageKey)!.getImage(mascot.lookRight));
    mascot.sound = soundKey;
  }
}

/// A clickable region on an animation frame. [originX]/[originY]/[width]/
/// [height] are in image-local coordinates (pre-scaled).
class Hotspot {
  final String shape; // 'rectangle' | 'ellipse'
  final int originX;
  final int originY;
  final int width;
  final int height;
  final String? behaviour;

  Hotspot({
    required this.shape,
    required this.originX,
    required this.originY,
    required this.width,
    required this.height,
    required this.behaviour,
  });

  /// Tests a point given in window coordinates (physical px within the
  /// mascot's image bounds). Mirrors the x coordinate when the mascot faces
  /// right, like Java's Hotspot.contains.
  bool contains(dynamic mascot, JPoint point) {
    final bounds = mascot.bounds;
    final localX = point.x - bounds.x;
    final localY = point.y - bounds.y;
    final x =
        mascot.lookRight ? mascot.imageWidth - localX : localX;
    return containsLocal(x.toInt(), localY.toInt());
  }

  bool containsLocal(int x, int y) {
    if (shape == 'ellipse') {
      final cx = originX + width / 2;
      final cy = originY + height / 2;
      final rx = width / 2;
      final ry = height / 2;
      if (rx <= 0 || ry <= 0) return false;
      final nx = (x - cx) / rx;
      final ny = (y - cy) / ry;
      return nx * nx + ny * ny <= 1;
    }
    // Java Rectangle.contains is inclusive of the right/bottom edges.
    return x >= originX &&
        x <= originX + width &&
        y >= originY &&
        y <= originY + height;
  }
}

class Animation {
  final Variable? condition;
  final List<Pose> poses;
  final List<Hotspot> hotspots;
  final bool turn;
  final int duration;

  Animation({
    required this.condition,
    required this.poses,
    required this.hotspots,
    required this.turn,
    required this.duration,
  }) {
    if (poses.isEmpty) {
      throw ArgumentError('poses.size==0');
    }
  }

  void init() {
    condition?.init();
  }

  void resetCondition() {
    condition?.resetValue();
  }

  bool isEffective(VariableMap variables) {
    if (condition == null) return true;
    final value = condition!.get(variables);
    return value == true;
  }

  void apply(dynamic mascot, int time) {
    getPoseAt(time)!.apply(mascot);
  }

  Pose? getPoseAt(int time) {
    time %= duration;
    for (final pose in poses) {
      time -= pose.duration;
      if (time < 0) {
        return pose;
      }
    }
    return null;
  }

  bool get isTurn => turn;
}
