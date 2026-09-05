/// Port of `environment/Area.java`, `Border.java`, `FloorCeiling.java`,
/// `Wall.java`, `ComplexArea.java`, `NotOnBorder.java` and `Location.java`.
///
/// All coordinates are in physical screen pixels (the Java original worked in
/// DPI-unscaled pixels as well).
library;

/// Simple mutable 2D point with Java-`Point`-like semantics.
class JPoint {
  int x;
  int y;
  JPoint([this.x = 0, this.y = 0]);

  void setLocation(int nx, int ny) {
    x = nx;
    y = ny;
  }

  void translate(int dx, int dy) {
    x += dx;
    y += dy;
  }

  JPoint clone() => JPoint(x, y);

  @override
  String toString() => 'JPoint($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is JPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Simple mutable rectangle.
class JRect {
  int x;
  int y;
  int width;
  int height;
  JRect(this.x, this.y, this.width, this.height);

  bool intersects(JRect r) {
    final tw = width, th = height;
    final rw = r.width, rh = r.height;
    if (rw <= 0 || rh <= 0 || tw <= 0 || th <= 0) return false;
    final tx = x, ty = y, rx = r.x, ry = r.y;
    return (rx + rw > tx) && (ry + rh > ty) && (tx + tw > rx) && (ty + th > ry);
  }

  bool containsPoint(int px, int py) =>
      px >= x && px < x + width && py >= y && py < y + height;

  @override
  String toString() => 'JRect($x, $y, $width, $height)';
}

/// A region of space with which mascots can interact.
class Area {
  final bool calcDeltas;
  bool _visible = true;

  int left = 0, top = 0, right = 0, bottom = 0;
  int _dleft = 0, _dtop = 0, _dright = 0, _dbottom = 0;

  late final FloorCeiling topBorder = FloorCeiling(this, false);
  late final FloorCeiling bottomBorder = FloorCeiling(this, true);
  late final Wall leftBorder = Wall(this, false);
  late final Wall rightBorder = Wall(this, true);

  Area({this.calcDeltas = true});

  bool get isVisible => _visible;
  set visible(bool v) => _visible = v;

  int get width => right - left;
  int get height => bottom - top;

  int get dleft => calcDeltas ? _dleft : 0;
  int get dtop => calcDeltas ? _dtop : 0;
  int get dright => calcDeltas ? _dright : 0;
  int get dbottom => calcDeltas ? _dbottom : 0;

  void set(int l, int t, int r, int b) {
    if (calcDeltas) {
      _dleft = l - left;
      _dtop = t - top;
      _dright = r - right;
      _dbottom = b - bottom;
    }
    left = l;
    top = t;
    right = r;
    bottom = b;
  }

  void setRect(int x, int y, int w, int h) => set(x, y, x + w, y + h);

  void setFromRect(JRect r) => setRect(r.x, r.y, r.width, r.height);

  void resetDeltas() {
    if (calcDeltas) {
      _dleft = 0;
      _dtop = 0;
      _dright = 0;
      _dbottom = 0;
    }
  }

  bool containsPoint(int x, int y) {
    if (((right - left) | (bottom - top)) < 0) return false;
    return left <= x && x <= right && top <= y && y <= bottom;
  }

  bool containsPoint2(JPoint point) => containsPoint(point.x, point.y);

  bool containsArea(Area a) =>
      contains(a.left, a.top, a.right, a.bottom);

  bool contains(int l, int t, int r, int b) {
    if (((right - left) | (bottom - top) | (r - l) | (b - t)) < 0) return false;
    if (l < left || t < top) return false;
    if (r <= l) {
      if (right >= left || r > right) return false;
    } else {
      if (right >= left && r > right) return false;
    }
    if (b <= t) {
      if (bottom >= top || b > bottom) return false;
    } else {
      if (bottom >= top && b > bottom) return false;
    }
    return true;
  }

  bool intersectsRect(JRect r) {
    final tw = right - left, th = bottom - top;
    if (r.width <= 0 || r.height <= 0 || tw <= 0 || th <= 0) return false;
    return (r.x + r.width > left) &&
        (r.y + r.height > top) &&
        (right > r.x) &&
        (bottom > r.y);
  }

  bool intersectsArea(Area a) {
    final tw = right - left, th = bottom - top;
    final aw = a.right - a.left, ah = a.bottom - a.top;
    if (aw <= 0 || ah <= 0 || tw <= 0 || th <= 0) return false;
    return (a.right > left) &&
        (a.bottom > top) &&
        (right > a.left) &&
        (bottom > a.top);
  }

  JRect toRect() => JRect(left, top, right - left, bottom - top);

  @override
  String toString() => 'Area[left=$left,top=$top,right=$right,bottom=$bottom]';
}

/// A moveable surface with which mascots can interact.
abstract class Border {
  bool isOn(JPoint location);
  JPoint move(JPoint location);
}

class NotOnBorder implements Border {
  const NotOnBorder();

  @override
  bool isOn(JPoint location) => false;

  @override
  JPoint move(JPoint location) => location;
}

/// Horizontal border on the top or bottom of an [Area].
class FloorCeiling implements Border {
  final Area area;
  final bool bottom;

  FloorCeiling(this.area, this.bottom);

  int get y => bottom ? area.bottom : area.top;
  int get left => area.left;
  int get right => area.right;
  int get dy => bottom ? area.dbottom : area.dtop;
  int get dLeft => area.dleft;
  int get dRight => area.dright;
  int get width => area.width;

  @override
  bool isOn(JPoint location) =>
      area.isVisible &&
      y == location.y &&
      left <= location.x &&
      location.x <= right;

  @override
  JPoint move(JPoint location) {
    if (!area.isVisible) return location;
    if (dLeft == 0 && dRight == 0 && dy == 0) return location;

    final prevLeft = left - dLeft;
    final prevWidth = right - dRight - prevLeft;
    if (prevWidth == 0) return location;

    final newX = (location.x - prevLeft) * width ~/ prevWidth + left;
    final newY = location.y + dy;

    if ((newX - location.x).abs() >= 80 ||
        newY - location.y > 20 ||
        newY - location.y < -80) {
      return location;
    }

    return JPoint(newX, newY);
  }
}

/// Vertical border on the left or right side of an [Area].
class Wall implements Border {
  final Area area;
  final bool right;

  Wall(this.area, this.right);

  int get x => right ? area.right : area.left;
  int get top => area.top;
  int get bottom => area.bottom;
  int get dx => right ? area.dright : area.dleft;
  int get dTop => area.dtop;
  int get dBottom => area.dbottom;
  int get height => area.height;

  @override
  bool isOn(JPoint location) =>
      area.isVisible &&
      x == location.x &&
      top <= location.y &&
      location.y <= bottom;

  @override
  JPoint move(JPoint location) {
    if (!area.isVisible) return location;
    if (dTop == 0 && dBottom == 0 && dx == 0) return location;

    final prevTop = top - dTop;
    final prevHeight = bottom - dBottom - prevTop;
    if (prevHeight == 0) return location;

    final newX = location.x + dx;
    final newY = (location.y - prevTop) * height ~/ prevHeight + top;

    if ((newX - location.x).abs() >= 80 || (newY - location.y).abs() >= 80) {
      return location;
    }

    return JPoint(newX, newY);
  }
}

/// A collection of named areas (one per display).
class ComplexArea {
  final Map<String, Area> areas = <String, Area>{};

  void set(Map<String, JRect> rectangles) {
    if (rectangles.isEmpty) {
      areas.clear();
    } else {
      areas.removeWhere((key, area) => !rectangles.containsKey(key));
      rectangles.forEach(setArea);
    }
  }

  void setArea(String name, JRect value) {
    if (areas.isNotEmpty) {
      for (final area in areas.values) {
        if (area.left == value.x &&
            area.top == value.y &&
            area.width == value.width &&
            area.height == value.height) {
          return;
        }
      }
    }
    final area = areas[name];
    if (area == null) {
      areas[name] = Area(calcDeltas: false)..setFromRect(value);
    } else {
      area.setFromRect(value);
    }
  }

  Iterable<Area> get areaList => areas.values;

  FloorCeiling? getBottomBorder(JPoint location) {
    FloorCeiling? ret;
    if (areas.isNotEmpty) {
      for (final area in areas.values) {
        if (area.topBorder.isOn(location)) {
          return null;
        } else if (area.bottomBorder.isOn(location)) {
          ret = area.bottomBorder;
        }
      }
    }
    return ret;
  }

  FloorCeiling? getTopBorder(JPoint location) {
    FloorCeiling? ret;
    if (areas.isNotEmpty) {
      for (final area in areas.values) {
        if (area.bottomBorder.isOn(location)) {
          return null;
        } else if (area.topBorder.isOn(location)) {
          ret = area.topBorder;
        }
      }
    }
    return ret;
  }

  Wall? getLeftBorder(JPoint location) {
    Wall? ret;
    if (areas.isNotEmpty) {
      for (final area in areas.values) {
        if (area.rightBorder.isOn(location)) {
          return null;
        } else if (area.leftBorder.isOn(location)) {
          ret = area.leftBorder;
        }
      }
    }
    return ret;
  }

  Wall? getRightBorder(JPoint location) {
    Wall? ret;
    if (areas.isNotEmpty) {
      for (final area in areas.values) {
        if (area.leftBorder.isOn(location)) {
          return null;
        } else if (area.rightBorder.isOn(location)) {
          ret = area.rightBorder;
        }
      }
    }
    return ret;
  }
}

/// Position with velocity, used for the cursor.
class Location {
  int x = 0, y = 0, dx = 0, dy = 0;

  void set(int nx, int ny) {
    // Averages the stored deltas with the actual deltas so the values are
    // more representative of the cursor's momentum (see Java Location.set).
    dx = (dx + nx - x) ~/ 2;
    dy = (dy + ny - y) ~/ 2;
    x = nx;
    y = ny;
  }
}
