/// Port of `environment/Environment.java`, `AbstractEnvironment.java` and
/// `environment/MascotEnvironment.java`.
library;

import '../script/script_object.dart';
import 'area.dart';

/// Interacts with, and provides information about, the desktop environment.
abstract class Environment {
  /// Initializes this environment. Called once when the environment is created.
  void init();

  /// Advances this environment by one frame (called every 40 ms).
  void tick();

  /// Gets the work area containing the given physical point.
  Area getWorkAreaAt(JPoint point);

  /// Gets the work areas of all displays, keyed by display id.
  ComplexArea getComplexWorkArea();

  /// Gets the union of all active displays.
  Area getScreen();

  /// Gets the areas of all active displays.
  Iterable<Area> getScreens();

  /// Gets the areas of all active displays, keyed by display id.
  ComplexArea getComplexScreen();

  /// Gets the area of the active window.
  Area getActiveWindow();

  /// Gets the title of the active window (may be empty).
  String getActiveWindowTitle();

  /// Gets the id of the active window (0 when there is none).
  int getActiveWindowId();

  /// Repositions the active window so its top-left corner is at (x, y).
  void moveActiveWindow(int x, int y);

  /// Searches for windows that were thrown off-screen and restores them.
  void restoreWindows();

  /// Gets the cursor position with velocity.
  Location getCursor();

  /// Clears cached data about interactive windows.
  void refreshCache();
}

/// Base implementation tracking screens, work areas, and the cursor.
abstract class AbstractEnvironment implements Environment {
  JRect? screenRect;
  Map<String, JRect> screenRects = {};
  Map<String, JRect> workAreaRects = {};

  final Area screen = Area(calcDeltas: false);
  final ComplexArea complexScreen = ComplexArea();
  final ComplexArea complexWorkArea = ComplexArea();
  final Location cursor = Location();

  /// An invisible area used when no work area contains a point.
  final Area invisibleScreen = _InvisibleArea();

  DateTime _lastScreenUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// Called by tick(); subclasses refresh native screen info here when needed.
  void updateScreenRectsIfNeeded() {
    // Screens are refreshed at most every 5 seconds (Java uses a thread).
    final now = DateTime.now();
    if (now.difference(_lastScreenUpdate).inSeconds >= 5) {
      updateScreenRects();
      _lastScreenUpdate = now;
    }
  }

  /// Subclasses populate [screenRect], [screenRects] and [workAreaRects].
  void updateScreenRects();

  @override
  void init() {
    updateScreenRects();
    _lastScreenUpdate = DateTime.now();
    tick();
  }

  @override
  void tick() {
    updateScreenRectsIfNeeded();
    if (screenRect != null) screen.setFromRect(screenRect!);
    complexScreen.set(screenRects);
    complexWorkArea.set(workAreaRects);
  }

  @override
  Area getWorkAreaAt(JPoint point) {
    final workAreas = complexWorkArea.areaList;
    if (workAreas.isNotEmpty) {
      for (final workArea in workAreas) {
        if (workArea.containsPoint(point.x, point.y)) return workArea;
      }
      return invisibleScreen;
    }
    return invisibleScreen;
  }

  @override
  ComplexArea getComplexWorkArea() => complexWorkArea;

  @override
  Area getScreen() => screen;

  @override
  Iterable<Area> getScreens() => complexScreen.areaList;

  @override
  ComplexArea getComplexScreen() => complexScreen;

  @override
  Location getCursor() => cursor;
}

class _InvisibleArea extends Area {
  _InvisibleArea();

  @override
  bool get isVisible => false;
}

/// Provides mascots with information about the desktop environment, for use
/// in scripts. Per-mascot facade over [Environment] (port of
/// `MascotEnvironment.java`).
class MascotEnvironment {
  /// Set by the app so scripts can read live settings (multiscreen, etc.).
  static bool Function() multiscreenEnabled = () => true;

  final Environment impl;
  final dynamic mascot; // Mascot (typed loosely to avoid a dependency cycle)
  Area? currentWorkArea;

  MascotEnvironment(this.impl, this.mascot);

  /// Returns the mascot's anchor point.
  JPoint get anchor => mascot.anchor as JPoint;

  Area getWorkArea() => getWorkAreaCached(false);

  Area getWorkAreaCached(bool forceRefresh) {
    final anchor = this.anchor;
    Area? implWorkArea;
    if (currentWorkArea != null) {
      if (forceRefresh || multiscreenEnabled()) {
        implWorkArea = impl.getWorkAreaAt(anchor);
        if (!identical(currentWorkArea, implWorkArea) &&
            currentWorkArea!.containsArea(implWorkArea)) {
          if (implWorkArea.containsPoint(anchor.x, anchor.y)) {
            currentWorkArea = implWorkArea;
            return currentWorkArea!;
          }
        }
        if (currentWorkArea!.containsPoint(anchor.x, anchor.y)) {
          return currentWorkArea!;
        }
      } else {
        return currentWorkArea!;
      }
    }

    implWorkArea ??= impl.getWorkAreaAt(anchor);

    if (implWorkArea.containsPoint(anchor.x, anchor.y)) {
      currentWorkArea = implWorkArea;
      return currentWorkArea!;
    }

    for (final area in impl.getScreens()) {
      if (area.containsPoint(anchor.x, anchor.y)) {
        currentWorkArea = area;
        return currentWorkArea!;
      }
    }

    currentWorkArea = implWorkArea;
    return currentWorkArea!;
  }

  void refreshWorkArea() {
    getWorkAreaCached(true);
  }

  Area getScreen() => impl.getScreen();

  ComplexArea getComplexScreen() => impl.getComplexScreen();

  Border getCeiling() => getCeilingBorder(false);

  Border getCeilingBorder(bool ignoreSeparator) {
    final anchor = this.anchor;

    final activeIe = getActiveIE();
    final activeIeBorder = activeIe.bottomBorder;
    if (activeIeBorder.isOn(anchor)) return activeIeBorder;

    final workArea = getWorkArea();
    final workAreaBorder = workArea.topBorder;
    if (workAreaBorder.isOn(anchor)) {
      if (!ignoreSeparator || isScreenTopBottom()) return workAreaBorder;
    }

    return const NotOnBorder();
  }

  Border getFloor() => getFloorBorder(false);

  Border getFloorBorder(bool ignoreSeparator) {
    final anchor = this.anchor;

    final activeIe = getActiveIE();
    final activeIeBorder = activeIe.topBorder;
    if (activeIeBorder.isOn(anchor)) return activeIeBorder;

    final workArea = getWorkArea();
    final workAreaBorder = workArea.bottomBorder;
    if (workAreaBorder.isOn(anchor)) {
      if (!ignoreSeparator || isScreenTopBottom()) return workAreaBorder;
    }

    return const NotOnBorder();
  }

  Border getWall() => getWallBorder(false);

  Border getWallBorder(bool ignoreSeparator) {
    final isLookRight = mascot.lookRight as bool;
    final anchor = this.anchor;

    final activeIe = getActiveIE();
    final activeIeBorder =
        isLookRight ? activeIe.leftBorder : activeIe.rightBorder;
    if (activeIeBorder.isOn(anchor)) return activeIeBorder;

    final workArea = getWorkArea();
    final workAreaBorder =
        isLookRight ? workArea.rightBorder : workArea.leftBorder;
    if (workAreaBorder.isOn(anchor)) {
      if (!ignoreSeparator || isScreenLeftRight()) return workAreaBorder;
    }

    return const NotOnBorder();
  }

  Area getActiveIE() {
    final activeIE = impl.getActiveWindow();

    if (currentWorkArea != null && !multiscreenEnabled()) {
      if (!currentWorkArea!.intersectsArea(activeIE)) {
        return Area(calcDeltas: false);
      }
    }

    return activeIE;
  }

  String getActiveIETitle() => impl.getActiveWindowTitle();

  int getActiveWindowId() => impl.getActiveWindowId();

  void moveActiveIE(int x, int y) => impl.moveActiveWindow(x, y);

  void moveActiveIEPoint(JPoint point) => impl.moveActiveWindow(point.x, point.y);

  void restoreIE() => impl.restoreWindows();

  Location getCursor() => impl.getCursor();

  bool isScreenTopBottom() => _isScreenTopBottom(anchor);

  bool _isScreenTopBottom(JPoint location) {
    var count = 0;
    for (final area in impl.getScreens()) {
      if (area.topBorder.isOn(location)) count++;
      if (area.bottomBorder.isOn(location)) count++;
    }
    if (count == 0) {
      for (final area in impl.getComplexWorkArea().areaList) {
        if (area.topBorder.isOn(location)) count++;
        if (area.bottomBorder.isOn(location)) count++;
      }
    }
    return count == 1;
  }

  bool isScreenLeftRight() => _isScreenLeftRight(anchor);

  bool _isScreenLeftRight(JPoint location) {
    var count = 0;
    for (final area in impl.getScreens()) {
      if (area.leftBorder.isOn(location)) count++;
      if (area.rightBorder.isOn(location)) count++;
    }
    if (count == 0) {
      for (final area in impl.getComplexWorkArea().areaList) {
        if (area.leftBorder.isOn(location)) count++;
        if (area.rightBorder.isOn(location)) count++;
      }
    }
    return count == 1;
  }
}

// ---------------------------------------------------------------------------
// Script object adapters (Nashorn property access equivalents)
// ---------------------------------------------------------------------------

/// Exposes an [Area] to scripts: left/top/right/bottom/width/height plus the
/// four borders (each with an `isOn(point)` method).
class AreaScriptObject extends ScriptObject {
  final Area area;
  AreaScriptObject(this.area);

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'left':
        return area.left;
      case 'top':
        return area.top;
      case 'right':
        return area.right;
      case 'bottom':
        return area.bottom;
      case 'width':
        return area.width;
      case 'height':
        return area.height;
      case 'dleft':
        return area.dleft;
      case 'dtop':
        return area.dtop;
      case 'dright':
        return area.dright;
      case 'dbottom':
        return area.dbottom;
      case 'visible':
        return area.isVisible;
      case 'leftBorder':
        return BorderScriptObject(area.leftBorder);
      case 'rightBorder':
        return BorderScriptObject(area.rightBorder);
      case 'topBorder':
        return BorderScriptObject(area.topBorder);
      case 'bottomBorder':
        return BorderScriptObject(area.bottomBorder);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AreaScriptObject && identical(other.area, area);

  @override
  int get hashCode => identityHashCode(area);
}

/// Exposes a [Border] to scripts (`isOn(point)`).
class BorderScriptObject extends ScriptObject {
  final Border border;
  BorderScriptObject(this.border);

  @override
  Object? getProperty(String name) {
    if (border is FloorCeiling) {
      final fc = border as FloorCeiling;
      switch (name) {
        case 'y':
          return fc.y;
        case 'left':
          return fc.left;
        case 'right':
          return fc.right;
        case 'width':
          return fc.width;
      }
    } else if (border is Wall) {
      final w = border as Wall;
      switch (name) {
        case 'x':
          return w.x;
        case 'top':
          return w.top;
        case 'bottom':
          return w.bottom;
        case 'height':
          return w.height;
      }
    }
    return null;
  }

  @override
  Object? callMethod(String name, List<Object?> args) {
    if (name == 'isOn') {
      final arg = args.isNotEmpty ? args[0] : null;
      JPoint? point;
      if (arg is JPoint) {
        point = arg;
      } else if (arg is ScriptObject) {
        point = JPoint(_asInt(arg.getProperty('x')), _asInt(arg.getProperty('y')));
      }
      if (point != null) return border.isOn(point);
    } else if (name == 'move') {
      final arg = args.isNotEmpty ? args[0] : null;
      if (arg is JPoint) {
        final moved = border.move(arg);
        return ScriptPointObject(moved.x, moved.y);
      }
    }
    return null;
  }
}

int _asInt(Object? v) => v is num ? v.toInt() : 0;

/// Point value passed back from scripts.
class ScriptPointObject extends ScriptObject {
  final int x;
  final int y;
  ScriptPointObject(this.x, this.y);

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'x':
        return x;
      case 'y':
        return y;
    }
    return null;
  }
}
