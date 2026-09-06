/// Port of `Mascot.java`.
///
/// In the Java original each mascot owned a transparent AWT window; in the
/// Flutter port all mascots are rendered by a single always-on-top overlay
/// window, and the mascot object only holds engine state. Input is dispatched
/// by the overlay layer.
library;

import 'animation/animation.dart' show Hotspot;
import 'behavior/behavior.dart';
import 'config/configuration.dart';
import 'environment/area.dart';
import 'environment/environment.dart';
import 'image/mascot_image.dart';
import 'manager.dart';
import 'script/script_object.dart';
import 'sound/sounds.dart';

export 'environment/environment.dart'
    show AreaScriptObject, BorderScriptObject, ScriptPointObject;

class Mascot {
  static int _lastId = 0;

  final int id = ++_lastId;
  String imageSet;
  late final MascotEnvironment environment;
  Manager? manager;

  final JPoint anchor = JPoint(0, 0);
  MascotImage? image;
  bool lookRight = false;
  Behavior? behavior;
  int time = 0;
  bool _animating = true;
  bool paused = false;
  bool dragging = false;
  String? sound;

  final List<String> affordances = [];
  final List<Hotspot> hotspots = [];
  JPoint? cursor; // cursor position in window-local coordinates

  /// Per-mascot script scratch space (Java Mascot.getVariables()).
  final Map<String, Object?> variables = {};

  /// Actions for the current native context menu, keyed by the stable item
  /// id the native layer echoes back on selection.
  final Map<String, void Function()> contextMenuActions = {};

  /// Resolves the action for a selected menu item id.
  void Function()? contextMenuActionFor(String id) =>
      contextMenuActions[id];

  /// Hooked by the overlay UI layer to open the mascot context menu.
  void Function(int x, int y)? onShowPopup;

  /// Cached image geometry for bounds computation (mirrors the Java
  /// prevImageAnchor/prevImageSize fields).
  int? _prevImageAnchorX;
  int? _prevImageAnchorY;
  int _prevImageWidth = 0;
  int _prevImageHeight = 0;

  Mascot(this.imageSet) {
    environment = MascotEnvironment(ShimejiEnvironmentHolder.instance!, this);
  }

  bool get isAnimating => _animating && !paused;

  set animating(bool value) => _animating = value;

  /// Advances the behavior by one tick.
  void tick() {
    if (!isAnimating) return;
    if (behavior != null) {
      try {
        behavior!.next();
      } on BehaviorExecutionException {
        dispose();
        rethrow;
      }
      time++;
    }
  }

  /// Applies the state after a tick (sound playback; rendering is handled by
  /// the shared overlay painter).
  void apply() {
    if (sound != null && Sounds.contains(sound)) {
      Sounds.play(sound);
    }
  }

  void dispose() {
    _animating = false;
    affordances.clear();
    manager?.remove(this);
    manager = null;
  }

  /// Bounds of the mascot window in physical screen coordinates.
  JRect get bounds {
    var x = anchor.x;
    var y = anchor.y;
    if (_prevImageAnchorX != null) {
      x -= _prevImageAnchorX!;
      y -= _prevImageAnchorY!;
    }
    return JRect(x, y, _prevImageWidth, _prevImageHeight);
  }

  int get imageWidth => image?.width ?? _prevImageWidth;

  void setImage(MascotImage? newImage) {
    if (identical(image, newImage)) return;
    image = newImage;
    if (newImage != null) {
      _prevImageAnchorX = newImage.centerX;
      _prevImageAnchorY = newImage.centerY;
      _prevImageWidth = newImage.width;
      _prevImageHeight = newImage.height;
    }
  }

  void setBehavior(Behavior newBehavior) {
    behavior = newBehavior;
    if (behavior != null) {
      behavior!.init(this);
    }
  }

  int get count => manager?.getCount(imageSet) ?? 0;
  int get totalCount => manager?.getCount() ?? 0;

  bool get isHotspotClicked => cursor != null;

  // -------------------------------------------------------------------------
  // Input (dispatched by the overlay layer)
  // -------------------------------------------------------------------------

  void mousePressed(bool rightButton, int windowX, int windowY) {
    if (rightButton) {
      showPopup(windowX, windowY);
      return;
    }
    if (!paused && behavior != null) {
      try {
        behavior!.mousePressed(JPoint(windowX, windowY));
      } on BehaviorExecutionException {
        dispose();
        rethrow;
      }
    }
  }

  void mouseReleased(bool rightButton, int windowX, int windowY) {
    if (rightButton) return;
    if (!paused && behavior != null) {
      try {
        behavior!.mouseReleased(JPoint(windowX, windowY));
      } on BehaviorExecutionException {
        dispose();
        rethrow;
      }
    }
  }

  void showPopup(int x, int y) {
    onShowPopup?.call(x, y);
  }
}

/// Global access to the shared [Environment]; assigned at startup.
class ShimejiEnvironmentHolder {
  static Environment? instance;
}

/// Configuration builder hook needed by behaviors to avoid import cycles.
/// Set at startup; see app.dart.
typedef BuildBehaviorFn = Future<Behavior> Function(String name);

/// Exposes a [Mascot] to the scripting engine.
class MascotScriptObject extends ScriptObject {
  final Mascot mascot;
  MascotScriptObject(this.mascot);

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'anchor':
        return LivePointScriptObject(mascot.anchor);
      case 'lookRight':
        return mascot.lookRight;
      case 'imageSet':
        return mascot.imageSet;
      case 'time':
        return mascot.time;
      case 'count':
        return mascot.count;
      case 'totalCount':
        return mascot.totalCount;
      case 'environment':
        return MascotEnvironmentScriptObject(mascot.environment);
      case 'affordances':
        return mascot.affordances;
      case 'dragging':
        return mascot.dragging;
      case 'id':
        return mascot.id;
    }
    return null;
  }
}

/// Live view over a [JPoint].
class LivePointScriptObject extends ScriptObject {
  final JPoint point;
  LivePointScriptObject(this.point);

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'x':
        return point.x;
      case 'y':
        return point.y;
    }
    return null;
  }
}

/// Live view over the cursor [Location].
class LocationScriptObject extends ScriptObject {
  final Location location;
  LocationScriptObject(this.location);

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'x':
        return location.x;
      case 'y':
        return location.y;
      case 'dx':
        return location.dx;
      case 'dy':
        return location.dy;
    }
    return null;
  }
}

/// Exposes [MascotEnvironment] to the scripting engine, mirroring the Java
/// getter surface used by Shimeji scripts.
class MascotEnvironmentScriptObject extends ScriptObject {
  final MascotEnvironment env;
  MascotEnvironmentScriptObject(this.env);

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'cursor':
        return LocationScriptObject(env.getCursor());
      case 'floor':
        return BorderScriptObject(env.getFloor());
      case 'ceiling':
        return BorderScriptObject(env.getCeiling());
      case 'wall':
        return BorderScriptObject(env.getWall());
      case 'workArea':
        return AreaScriptObject(env.getWorkArea());
      case 'screen':
        return AreaScriptObject(env.getScreen());
      case 'activeIE':
        return AreaScriptObject(env.getActiveIE());
      case 'activeIETitle':
        return env.getActiveIETitle();
      case 'activeWindowId':
        return env.getActiveWindowId();
    }
    return null;
  }

  @override
  Object? callMethod(String name, List<Object?> args) {
    switch (name) {
      case 'moveActiveIE':
        if (args.length >= 2) {
          env.moveActiveIE(_asInt(args[0]), _asInt(args[1]));
        }
        return null;
      case 'restoreIE':
        env.restoreIE();
        return null;
    }
    return null;
  }
}

int _asInt(Object? v) => v is num ? v.toInt() : 0;

/// Used by UserBehavior to reach the configuration.
typedef ConfigurationGetter = Configuration? Function(String imageSet);

final configurationGetterHolder = ConfigurationHolder();

class ConfigurationHolder {
  Configuration? Function(String imageSet) get = (_) => null;

  Configuration getRequired(String imageSet) {
    final c = get(imageSet);
    if (c == null) {
      throw StateError('No configuration loaded for image set "$imageSet"');
    }
    return c;
  }
}

/// Constants shared with UserBehavior.
const String behaviorNameChaseMouse = 'ChaseMouse';
const String behaviorNameFall = 'Fall';
const String behaviorNameDragged = 'Dragged';
const String behaviorNameThrown = 'Thrown';

final userBehaviorNames = const [
  behaviorNameChaseMouse,
  behaviorNameFall,
  behaviorNameDragged,
  behaviorNameThrown,
];
