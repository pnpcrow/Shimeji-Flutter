/// Port of `action/Action.java`, `ActionBase.java`, `BorderedAction.java`,
/// `InstantAction.java`, `ComplexAction.java` and `LostGroundException.java`.
library;

import '../animation/animation.dart';
import '../config/schema.dart';
import '../environment/area.dart';
import '../environment/environment.dart';
import '../mascot.dart';
import '../script/script_object.dart';
import '../script/variable_map.dart';

/// Signals "not on any border" — the behavior switches to Fall.
class LostGroundException implements Exception {
  final String? message;
  LostGroundException([this.message]);

  @override
  String toString() => 'LostGroundException: $message';
}

abstract class Action {
  void init(Mascot mascot);
  bool hasNext();
  void next(); // throws LostGroundException
  bool isDraggable() => true;
}

/// Exposes an action to scripts (mostly unused by real conf files).
class ActionScriptObject extends ScriptObject {
  final Action action;
  ActionScriptObject(this.action);

  @override
  Object? getProperty(String name) => null;
}

abstract class ActionBase extends Action {
  final Schema schema;
  final List<Animation> animations;
  final VariableMap variables;
  Mascot? _mascot;
  int _startTime = 0;

  ActionBase(this.schema, this.animations, this.variables);

  Mascot? get mascotOrNull => _mascot;
  Mascot get mascot => _mascot!;

  @override
  void init(Mascot mascot) {
    _mascot = mascot;
    setTime(0);
    variables.putObject('mascot', MascotScriptObject(mascot));
    variables.putObject('action', ActionScriptObject(this));
    variables.init();
    for (final animation in animations) {
      animation.init();
    }
  }

  @override
  bool hasNext() =>
      _mascot != null && getTime() < getDuration() && isEffective();

  @override
  void next() {
    if (_mascot == null) return;
    resetVariables();
    if (_mascot!.affordances.isNotEmpty) {
      _mascot!.affordances.clear();
    }
    final affordance = getAffordance();
    if (affordance.trim().isNotEmpty) {
      _mascot!.affordances.add(affordance);
    }
    refreshHotspots();
    tick();
  }

  void resetVariables() {
    variables.resetValues();
    for (final animation in animations) {
      animation.resetCondition();
    }
  }

  void refreshHotspots() {
    try {
      final animation = getAnimation();
      if (animation != null) {
        _mascot!.hotspots
          ..clear()
          ..addAll(animation.hotspots);
      }
    } on VariableException {
      _mascot!.hotspots.clear();
    }
  }

  /// One frame of action logic.
  void tick();

  Animation? getAnimation() {
    for (final animation in animations) {
      if (animation.isEffective(variables)) {
        return animation;
      }
    }
    return null;
  }

  MascotEnvironment get environment => _mascot!.environment;

  int getTime() => _mascot!.time - _startTime;

  void setTime(int time) => _startTime = _mascot!.time - time;

  int getDuration() => variables.evalInt(schema.get('Duration'), 0x7FFFFFFF);

  bool isEffective() => variables.evalBool(schema.get('Condition'), true);

  @override
  bool isDraggable() => variables.evalBool(schema.get('Draggable'), true);

  String getAffordance() => variables.evalString(schema.get('Affordance'), '');

  /// Numeric parameter with Java `Number.intValue()` truncation semantics.
  int evalInt(String key, int fallback) =>
      variables.evalInt(key, fallback);

  double evalDouble(String key, double fallback) =>
      variables.evalDouble(key, fallback);

  bool evalBool(String key, bool fallback) => variables.evalBool(key, fallback);

  String evalString(String key, String fallback) =>
      variables.evalString(key, fallback);

  bool evalBoolDefault(String key, bool fallback) =>
      variables.evalBool(key, fallback);
}

abstract class BorderedAction extends ActionBase {
  Border? _border;

  BorderedAction(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    final borderType = variables.evalString(schema.get('BorderType'), '');
    if (borderType == schema.get('Ceiling')) {
      _border = environment.getCeiling();
    } else if (borderType == schema.get('Wall')) {
      _border = environment.getWall();
    } else if (borderType == schema.get('Floor')) {
      _border = environment.getFloor();
    }
  }

  Border? get border => _border;

  @override
  void tick() {
    if (_border != null) {
      final moved = _border!.move(_mascot!.anchor);
      _mascot!.anchor.setLocation(moved.x, moved.y);
    }
  }

  void checkOnBorder() {
    if (_border != null && !_border!.isOn(_mascot!.anchor)) {
      throw LostGroundException('Mascot is not on border');
    }
  }
}

abstract class InstantAction extends ActionBase {
  InstantAction(Schema schema, VariableMap variables)
      : super(schema, const [], variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    if (super.hasNext()) {
      apply();
    }
  }

  void apply();

  @override
  bool hasNext() => false;

  @override
  void tick() {}
}

abstract class ComplexAction extends ActionBase {
  final List<Action> actions;
  int _currentAction = 0;

  ComplexAction(Schema schema, VariableMap variables, this.actions)
      : super(schema, const [], variables) {
    if (actions.isEmpty) {
      throw ArgumentError('actions.length==0');
    }
  }

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    if (super.hasNext()) {
      setCurrentAction(0);
      seek();
    }
  }

  void seek() {
    if (super.hasNext()) {
      while (_currentAction < actions.length) {
        if (currentAction.hasNext()) break;
        setCurrentAction(_currentAction + 1);
      }
    }
  }

  @override
  bool hasNext() =>
      super.hasNext() && _currentAction < actions.length && currentAction.hasNext();

  @override
  void tick() {
    final action = currentAction;
    if (action.hasNext()) {
      action.next();
    }
  }

  Action get currentAction => actions[_currentAction];

  void setCurrentAction(int index) {
    _currentAction = index;
    if (super.hasNext()) {
      if (_currentAction < actions.length) {
        actions[_currentAction].init(_mascot!);
      }
    }
  }

  @override
  bool isDraggable() {
    if (_currentAction < actions.length && actions[_currentAction] is ActionBase) {
      return (actions[_currentAction] as ActionBase).isDraggable();
    }
    return true;
  }
}
