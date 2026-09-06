/// Port of every action class in `com.group_finity.mascot.action`.
library;

import 'dart:math' as math;

import '../animation/animation.dart';
import '../config/behavior_instantiation_exception.dart';
import '../image/image_pairs.dart' show javaRound;
import '../mascot.dart';
import '../script/variable_map.dart';
import '../sound/sounds.dart';
import 'base.dart';
import 'globals.dart';

final math.Random _random = math.Random();

// ---------------------------------------------------------------------------
// Simple animation actions
// ---------------------------------------------------------------------------

/// Plays the animation once; ends when the animation completes or the mascot
/// leaves the border.
class Animate extends BorderedAction {
  Animate(super.schema, super.animations, super.variables);

  @override
  bool hasNext() {
    final animation = getAnimation();
    if (animation == null) return false;
    return super.hasNext() && getTime() < animation.duration;
  }

  @override
  void tick() {
    super.tick();
    checkOnBorder();
    getAnimation()!.apply(mascot, getTime());
  }
}

/// Loops the animation indefinitely (until Duration/Condition expire).
class Stay extends BorderedAction {
  Stay(super.schema, super.animations, super.variables);

  @override
  void tick() {
    super.tick();
    checkOnBorder();
    getAnimation()!.apply(mascot, getTime());
  }
}

/// Walks toward a target using the animation's pose velocities, optionally
/// playing a turn animation when the direction changes.
class Move extends BorderedAction {
  bool? _hasTurning;
  bool turning = false;

  static const int defaultTarget = 0x7FFFFFFF;

  Move(super.schema, super.animations, super.variables);

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    if (turning) return true;
    final targetX = getTargetX();
    final targetY = getTargetY();
    return targetX != defaultTarget && mascot.anchor.x != targetX ||
        targetY != defaultTarget && mascot.anchor.y != targetY;
  }

  @override
  void tick() {
    super.tick();
    checkOnBorder();
    final targetX = getTargetX();
    final targetY = getTargetY();
    var down = false;

    if (targetX != defaultTarget) {
      if (mascot.anchor.x != targetX) {
        turning = hasTurningAnimation() &&
            (turning || (mascot.anchor.x < targetX) != mascot.lookRight);
        mascot.lookRight = mascot.anchor.x < targetX;
      }
    }
    if (targetY != defaultTarget) {
      down = mascot.anchor.y < targetY;
    }

    var animation = getAnimation()!;
    if (turning && getTime() >= animation.duration) {
      turning = false;
      animation = getAnimation()!;
    }

    animation.apply(mascot, getTime());

    if (targetX != defaultTarget) {
      if (mascot.lookRight && mascot.anchor.x >= targetX ||
          !mascot.lookRight && mascot.anchor.x <= targetX) {
        mascot.anchor.x = targetX;
      }
    }
    if (targetY != defaultTarget) {
      if (down && mascot.anchor.y >= targetY ||
          !down && mascot.anchor.y <= targetY) {
        mascot.anchor.y = targetY;
      }
    }
  }

  @override
  Animation? getAnimation() {
    for (final animation in animations) {
      if (turning == animation.isTurn && animation.isEffective(variables)) {
        return animation;
      }
    }
    return null;
  }

  bool hasTurningAnimation() {
    _hasTurning ??= animations.isNotEmpty && animations.any((a) => a.isTurn);
    return _hasTurning!;
  }

  int getTargetX() => evalInt(schema.get('TargetX'), defaultTarget);
  int getTargetY() => evalInt(schema.get('TargetY'), defaultTarget);
}

/// Deprecated (1.0.21): forces the last animation to be the turn animation.
class MoveWithTurn extends Move {
  MoveWithTurn(super.schema, super.animations, super.variables) {
    if (animations.length < 2) {
      throw ArgumentError('animations.size<2');
    }
  }

  @override
  Animation? getAnimation() {
    if (turning) {
      return animations.last;
    }
    for (var index = 0; index < animations.length - 1; index++) {
      final animation = animations[index];
      if (animation.isEffective(variables)) {
        return animation;
      }
    }
    return null;
  }

  @override
  bool hasTurningAnimation() => true;
}

/// Jumps to a target in a fake arc.
class Jump extends ActionBase {
  static const double defaultVelocity = 20.0;
  double _scaling = 1.0;

  Jump(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    _scaling = EngineHooks.instance.scaling();
  }

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    final targetX = getTargetX();
    final targetY = getTargetY();
    final distanceX = targetX - mascot.anchor.x;
    final distanceY = targetY - mascot.anchor.y - distanceX.abs() / 2;
    final distance = _pythag(distanceX, distanceY);
    return distance != 0;
  }

  @override
  void tick() {
    final targetX = getTargetX();
    final targetY = getTargetY();
    if (mascot.anchor.x != targetX) {
      mascot.lookRight = mascot.anchor.x < targetX;
    }
    final distanceX = targetX - mascot.anchor.x;
    final distanceY = targetY - mascot.anchor.y - distanceX.abs() / 2;
    final distance = _pythag(distanceX, distanceY);
    final velocity = getVelocity() * _scaling;
    if (distance != 0) {
      final velocityX = velocity * distanceX / distance;
      final velocityY = velocity * distanceY / distance;
      variables.put(schema.get('VelocityX'), velocityX);
      variables.put(schema.get('VelocityY'), velocityY);
      mascot.anchor
          .translate(javaRound(velocityX), javaRound(velocityY));
      getAnimation()!.apply(mascot, getTime());
    }
    if (distance <= velocity) {
      mascot.anchor.setLocation(targetX, targetY);
    }
  }

  int getTargetX() => evalInt(schema.get('TargetX'), 0);
  int getTargetY() => evalInt(schema.get('TargetY'), 0);
  double getVelocity() => evalDouble(schema.get('VelocityParam'), defaultVelocity);
}

double _pythag(num a, num b) => math.sqrt((a * a + b * b).toDouble());

/// Falls with gravity, air resistance and sub-pixel accumulation. Probes
/// upward while falling to catch windows that moved up.
class Fall extends ActionBase {
  static const double defaultResistanceX = 0.05;
  static const double defaultResistanceY = 0.1;
  static const double defaultGravity = 2;

  double velocityX = 0;
  double velocityY = 0;
  double modX = 0;
  double modY = 0;
  double scaling = 1.0;

  Fall(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    scaling = EngineHooks.instance.scaling();
    velocityX = getInitialVx() * scaling;
    velocityY = getInitialVy() * scaling;
  }

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    final anchor = mascot.anchor;
    // Ignore whether the mascot is on a floor if they have upward velocity.
    return (velocityY < 0 || !environment.getFloor().isOn(anchor)) &&
        !environment.getWall().isOn(anchor);
  }

  @override
  void tick() {
    final mascot = this.mascot;
    if (velocityX != 0) {
      mascot.lookRight = velocityX > 0;
    }
    velocityX = velocityX - velocityX * getResistanceX();
    velocityY = velocityY - velocityY * getResistanceY() + getGravity() * scaling;
    variables.put(schema.get('VelocityX'), velocityX);
    variables.put(schema.get('VelocityY'), velocityY);
    // Java's % keeps the sign of the dividend; Dart's remainder() matches.
    modX += velocityX.remainder(1);
    modY += velocityY.remainder(1);
    final dx = javaRound(velocityX + modX);
    final dy = javaRound(velocityY + modY);
    modX = modX.remainder(1);
    modY = modY.remainder(1);

    final dev = math.max(1, math.max(dx.abs(), dy.abs()));
    final anchorX = mascot.anchor.x;
    final anchorY = mascot.anchor.y;

    outer:
    for (var i = 0; i <= dev; i++) {
      final x = anchorX + (dx * i) ~/ dev;
      final y = anchorY + (dy * i) ~/ dev;
      if (dy > 0) {
        for (var j = -80; j <= 0; j++) {
          mascot.anchor.setLocation(x, y + j);
          if (environment.getFloorBorder(true).isOn(mascot.anchor)) {
            break outer;
          }
        }
      } else {
        mascot.anchor.setLocation(x, y);
      }
      if (environment.getWallBorder(true).isOn(mascot.anchor)) {
        break;
      }
    }

    getAnimation()!.apply(mascot, getTime());
  }

  int getInitialVx() => evalInt(schema.get('InitialVX'), 0);
  int getInitialVy() => evalInt(schema.get('InitialVY'), 0);
  double getResistanceX() => evalDouble(schema.get('ResistanceX'), defaultResistanceX);
  double getResistanceY() => evalDouble(schema.get('ResistanceY'), defaultResistanceY);
  double getGravity() => evalDouble(schema.get('Gravity'), defaultGravity);
}

/// Carries the active window while falling.
class FallWithIE extends Fall {
  FallWithIE(super.schema, super.animations, super.variables);

  @override
  bool hasNext() => EngineHooks.instance.throwing() && super.hasNext();

  @override
  void tick() {
    final activeIE = environment.getActiveIE();
    if (!activeIE.isVisible) {
      throw LostGroundException('Window is not visible');
    }
    final offsetX = getIeOffsetX();
    final offsetY = getIeOffsetY();
    if (mascot.lookRight) {
      if (mascot.anchor.x - offsetX != activeIE.left ||
          mascot.anchor.y + offsetY != activeIE.bottom) {
        throw LostGroundException('Mascot is not holding window');
      }
    } else {
      if (mascot.anchor.x + offsetX != activeIE.right ||
          mascot.anchor.y + offsetY != activeIE.bottom) {
        throw LostGroundException('Mascot is not holding window');
      }
    }
    super.tick();
    if (activeIE.isVisible) {
      if (mascot.lookRight) {
        environment.moveActiveIE(
            mascot.anchor.x - offsetX,
            mascot.anchor.y + offsetY - activeIE.height);
      } else {
        environment.moveActiveIE(
            mascot.anchor.x + offsetX - activeIE.width,
            mascot.anchor.y + offsetY - activeIE.height);
      }
    }
  }

  int getIeOffsetX() => evalInt(schema.get('IeOffsetX'), 0);
  int getIeOffsetY() => evalInt(schema.get('IeOffsetY'), 0);
}

/// Carries the active window while walking.
class WalkWithIE extends Move {
  WalkWithIE(super.schema, super.animations, super.variables);

  @override
  bool hasNext() => EngineHooks.instance.throwing() && super.hasNext();

  @override
  void tick() {
    final activeIE = environment.getActiveIE();
    if (!activeIE.isVisible) {
      throw LostGroundException('Window is not visible');
    }
    final offsetX = getIeOffsetX();
    final offsetY = getIeOffsetY();
    if (mascot.lookRight) {
      if (mascot.anchor.x - offsetX != activeIE.left ||
          mascot.anchor.y + offsetY != activeIE.bottom) {
        throw LostGroundException('Mascot is not holding window');
      }
    } else {
      if (mascot.anchor.x + offsetX != activeIE.right ||
          mascot.anchor.y + offsetY != activeIE.bottom) {
        throw LostGroundException('Mascot is not holding window');
      }
    }
    super.tick();
    if (activeIE.isVisible) {
      if (mascot.lookRight) {
        environment.moveActiveIE(
            mascot.anchor.x - offsetX,
            mascot.anchor.y + offsetY - activeIE.height);
      } else {
        environment.moveActiveIE(
            mascot.anchor.x + offsetX - activeIE.width,
            mascot.anchor.y + offsetY - activeIE.height);
      }
    }
  }

  int getIeOffsetX() => evalInt(schema.get('IeOffsetX'), 0);
  int getIeOffsetY() => evalInt(schema.get('IeOffsetY'), 0);
}

/// Pins the mascot to the cursor while dragged, with oscillating sway.
class Dragged extends ActionBase {
  static const int defaultOffsetY = 120;
  static const int _timeToResistBase = 250;

  double footX = 0;
  double footDx = 0;
  int timeToResist = _timeToResistBase;
  double scaling = 1.0;

  Dragged(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    scaling = EngineHooks.instance.scaling();
    footX = (environment.getCursor().x + javaRound(getOffsetX() * scaling))
        .toDouble();
    timeToResist = _timeToResistBase;
  }

  @override
  bool hasNext() => super.hasNext() && getTime() < timeToResist;

  @override
  void tick() {
    mascot.lookRight = false;
    mascot.dragging = true;
    environment.refreshWorkArea();
    final cursor = environment.getCursor();

    var offsetX = javaRound(getOffsetX() * scaling);
    var offsetY = javaRound(getOffsetY() * scaling);
    if (getOffsetType() == schema.get('Origin')) {
      final img = mascot.image;
      if (img != null) {
        offsetX = img.centerX - offsetX;
        offsetY = img.centerY - offsetY;
      }
    }

    if ((cursor.x + offsetX - mascot.anchor.x).abs() >= 5) {
      setTime(0);
    }

    final newX = cursor.x;
    footDx = (footDx + (newX - footX) * 0.1) * 0.8;
    footX += footDx;
    variables.put(schema.get('FootDX'), footDx);
    variables.put(schema.get('FootX'), footX);

    getAnimation()!.apply(mascot, getTime());

    mascot.anchor.setLocation(cursor.x + offsetX, cursor.y + offsetY);

    if (getTime() == timeToResist - 1 && _random.nextDouble() >= 0.1) {
      timeToResist++;
    }
  }

  @override
  void refreshHotspots() {
    mascot.hotspots.clear();
  }

  int getOffsetX() => evalInt(schema.get('OffsetX'), 0);
  int getOffsetY() => evalInt(schema.get('OffsetY'), defaultOffsetY);
  String getOffsetType() =>
      evalString(schema.get('OffsetType'), 'ImageAnchor');
}

/// Resists briefly when the cursor holds still, then drops.
class Regist extends ActionBase {
  Regist(super.schema, super.animations, super.variables);

  double scaling = 1.0;

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    scaling = EngineHooks.instance.scaling();
  }

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    var offsetX = javaRound(getOffsetX() * scaling);
    if (getOffsetType() == schema.get('Origin')) {
      final img = mascot.image;
      if (img != null) offsetX = img.centerX - offsetX;
    }
    // This action does not update the mascot's position, so this uses the
    // mascot's anchor; the cursor may move vertically away from the mascot.
    return (environment.getCursor().x - mascot.anchor.x + offsetX).abs() < 5;
  }

  @override
  void tick() {
    mascot.dragging = true;
    getAnimation()!.apply(mascot, getTime());
    if (getTime() + 1 >= getAnimation()!.duration) {
      mascot.lookRight = _random.nextBool();
      throw LostGroundException('Mascot finished Regist action');
    }
  }

  @override
  void refreshHotspots() {
    mascot.hotspots.clear();
  }

  int getOffsetX() => evalInt(schema.get('OffsetX'), 0);
  String getOffsetType() =>
      evalString(schema.get('OffsetType'), 'ImageAnchor');
}

/// Turns the mascot around, playing the animation.
class Turn extends BorderedAction {
  bool turning = false;

  Turn(super.schema, super.animations, super.variables);

  @override
  bool hasNext() {
    turning = turning || getLookRight() != mascot.lookRight;
    final animation = getAnimation();
    if (animation == null) return false;
    return super.hasNext() && turning && getTime() < animation.duration;
  }

  @override
  void tick() {
    mascot.lookRight = getLookRight();
    super.tick();
    checkOnBorder();
    getAnimation()!.apply(mascot, getTime());
  }

  bool getLookRight() => variables.evalBool(schema.get('LookRight'), !mascot.lookRight);
}

/// Instantly flips the mascot.
class Look extends InstantAction {
  Look(super.schema, super.variables);

  @override
  void apply() {
    mascot.lookRight =
        variables.evalBool(schema.get('LookRight'), !mascot.lookRight);
  }
}

/// Instantly translates the anchor (values are unscaled, mirroring Java).
class Offset extends InstantAction {
  Offset(super.schema, super.variables);

  @override
  void apply() {
    mascot.anchor.translate(getOffsetX(), getOffsetY());
  }

  int getOffsetX() => evalInt(schema.get('X'), 0);
  int getOffsetY() => evalInt(schema.get('Y'), 0);
}

/// Stops a named sound clip, or all clips.
class Mute extends InstantAction {
  Mute(super.schema, super.variables);

  @override
  void apply() {
    final soundName = evalString(schema.get('Sound'), '');
    if (soundName.isNotEmpty) {
      // Sound files live under the image set's sound directory; clips are
      // keyed by full path so we match by suffix.
      final clips = Sounds.getAllByFileSuffix(soundName);
      for (final clip in clips) {
        if (clip.isRunning) clip.stop();
      }
    } else {
      Sounds.stopAll();
    }
  }
}

/// Disposes the mascot at the end of the animation.
class SelfDestruct extends Animate {
  SelfDestruct(super.schema, super.animations, super.variables);

  @override
  void tick() {
    super.tick();
    final animation = getAnimation()!;
    if (getTime() == animation.duration - 1 || animation.duration == 1) {
      mascot.dispose();
    }
  }
}

/// Transforms the mascot into another image set at the end of the animation.
class Transform extends Animate {
  Transform(super.schema, super.animations, super.variables);

  @override
  void tick() {
    super.tick();
    if (EngineHooks.instance.transformation()) {
      final animation = getAnimation()!;
      if (getTime() == animation.duration - 1 || animation.duration == 1) {
        _transform();
      }
    }
  }

  void _transform() {
    final transformMascot = getTransformMascot();
    final childType = EngineHooks.instance.configuration(transformMascot) != null
        ? transformMascot
        : mascot.imageSet;
    mascot.imageSet = childType;
    try {
      final configuration = EngineHooks.instance.configuration(childType);
      if (configuration != null) {
        mascot.setBehavior(
            configuration.buildBehaviorFor(getTransformBehavior(), mascot));
      }
    } on BehaviorInstantiationException
    catch (e) {
      EngineHooks.instance.showError(
          'Failed to set behavior to "${getTransformBehavior()}"', e);
    }
  }

  String getTransformBehavior() =>
      evalString(schema.get('TransformBehaviour'), '');
  String getTransformMascot() =>
      evalString(schema.get('TransformMascot'), '');
}

/// Breeding delegate shared by Breed/BreedMove/BreedJump/Complex*.
class BreedDelegate {
  final ActionBase action;
  double scaling = 1.0;

  BreedDelegate(this.action);

  void initScaling() {
    scaling = EngineHooks.instance.scaling();
  }

  bool isEnabled() {
    final isBornTransient = action.variables
        .evalBool(action.schema.get('BornTransient'), false);
    return isBornTransient
        ? EngineHooks.instance.transients()
        : EngineHooks.instance.breeding();
  }

  bool isIntervalFrame() =>
      action.getTime() % getBornInterval() == 0;

  bool isPenultimateFrame() =>
      action.getTime() == action.getAnimation()!.duration - 1;

  void breed() {
    final bornMascot = getBornMascot();
    final childType = EngineHooks.instance.configuration(bornMascot) != null
        ? bornMascot
        : action.mascot.imageSet;
    for (var index = 0; index < getBornCount(); index++) {
      final newMascot = EngineHooks.instance.createMascot(childType);
      if (action.mascot.lookRight) {
        newMascot.anchor.setLocation(
            action.mascot.anchor.x - javaRound(getBornX() * scaling),
            action.mascot.anchor.y + javaRound(getBornY() * scaling));
      } else {
        newMascot.anchor.setLocation(
            action.mascot.anchor.x + javaRound(getBornX() * scaling),
            action.mascot.anchor.y + javaRound(getBornY() * scaling));
      }
      newMascot.lookRight = action.mascot.lookRight;
      try {
        final configuration = EngineHooks.instance.configuration(childType);
        if (configuration != null) {
          newMascot.setBehavior(configuration
              .buildBehaviorFor(getBornBehavior(), action.mascot));
          final manager = action.mascot.manager;
          if (manager != null) manager.add(newMascot);
        }
      } on BehaviorInstantiationException {
        newMascot.dispose();
        EngineHooks.instance.showError('Failed to create a new shimeji.');
      }
    }
  }

  void validateBornCount() {
    if (getBornCount() < 1) {
      throw VariableException('BornCount must be positive');
    }
  }

  void validateBornInterval() {
    if (getBornInterval() < 1) {
      throw VariableException('BornInterval must be positive');
    }
  }

  int getBornX() => action.variables.evalInt(action.schema.get('BornX'), 0);
  int getBornY() => action.variables.evalInt(action.schema.get('BornY'), 0);
  String getBornBehavior() =>
      action.variables.evalString(action.schema.get('BornBehaviour'), '');
  String getBornMascot() =>
      action.variables.evalString(action.schema.get('BornMascot'), '');
  int getBornInterval() =>
      action.variables.evalInt(action.schema.get('BornInterval'), 1);
  int getBornCount() =>
      action.variables.evalInt(action.schema.get('BornCount'), 1);
}

/// Spawns children at the penultimate frame.
class Breed extends Animate {
  late final BreedDelegate delegate = BreedDelegate(this);

  Breed(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    delegate.initScaling();
    delegate.validateBornCount();
  }

  @override
  void tick() {
    super.tick();
    if (delegate.isPenultimateFrame() && delegate.isEnabled()) {
      delegate.breed();
    }
  }
}

/// Breeds every BornInterval frames while moving.
class BreedMove extends Move {
  late final BreedDelegate delegate = BreedDelegate(this);

  BreedMove(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    delegate.initScaling();
    delegate.validateBornCount();
    delegate.validateBornInterval();
  }

  @override
  void tick() {
    super.tick();
    if (delegate.isIntervalFrame() && !turning && delegate.isEnabled()) {
      delegate.breed();
    }
  }
}

/// Breeds every BornInterval frames while jumping.
class BreedJump extends Jump {
  late final BreedDelegate delegate = BreedDelegate(this);

  BreedJump(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    delegate.initScaling();
    delegate.validateBornCount();
    delegate.validateBornInterval();
  }

  @override
  void tick() {
    super.tick();
    if (delegate.isIntervalFrame() && delegate.isEnabled()) {
      delegate.breed();
    }
  }
}

/// Applies its behaviour when overlapping another mascot.
class Interact extends Animate {
  Interact(super.schema, super.animations, super.variables);

  @override
  bool hasNext() {
    final manager = mascot.manager;
    return super.hasNext() &&
        manager != null &&
        manager.hasOverlappingMascotsAtPoint(mascot.anchor);
  }

  @override
  void tick() {
    super.tick();
    final animation = getAnimation()!;
    if ((getTime() == animation.duration - 1 || animation.duration == 1) &&
        getBehaviour().trim().isNotEmpty) {
      try {
        final configuration = EngineHooks.instance.configuration(mascot.imageSet);
        if (configuration != null) {
          mascot.setBehavior(configuration.buildBehaviorFor(getBehaviour(), mascot));
        }
      } on BehaviorInstantiationException catch (e) {
        EngineHooks.instance.showError(
            'Failed to set behavior to "${getBehaviour()}"', e);
      }
    }
  }

  String getBehaviour() => evalString(schema.get('Behaviour'), '');
}

// ---------------------------------------------------------------------------
// Scan actions
// ---------------------------------------------------------------------------

extension MascotDisposedExt on Mascot {
  bool isDisposed() => manager == null && !isAnimating;
}

/// Finds a mascot broadcasting the action's affordance and walks to it.
class ScanMove extends BorderedAction {
  Mascot? _target;
  bool? _hasTurning;
  bool turning = false;

  ScanMove(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    mascot.affordances.clear();
    final manager = mascot.manager;
    if (manager != null) {
      _target = _live(manager.getMascotWithAffordance(getAffordance()));
    }
    _putTargetVariables();
  }

  void _putTargetVariables() {
    final target = _liveTarget();
    variables.put(schema.get('TargetX'), target?.anchor.x);
    variables.put(schema.get('TargetY'), target?.anchor.y);
  }

  Mascot? _live(Mascot? mascot) =>
      mascot != null && !mascot.isDisposed() ? mascot : null;

  Mascot? _liveTarget() => _live(_target);

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    if (turning || mascot.manager == null) return true;
    final target = _liveTarget();
    return target != null && target.affordances.contains(getAffordance());
  }

  @override
  void tick() {
    super.tick();
    mascot.affordances.clear();
    checkOnBorder();
    final target = _liveTarget();
    if (target == null) return;

    final targetX = target.anchor.x;
    final targetY = target.anchor.y;
    variables.put(schema.get('TargetX'), targetX);
    variables.put(schema.get('TargetY'), targetY);

    if (mascot.anchor.x != targetX) {
      turning = hasTurningAnimation() &&
          (turning || (mascot.anchor.x < targetX) != mascot.lookRight);
      mascot.lookRight = mascot.anchor.x < targetX;
    }
    final down = mascot.anchor.y < targetY;

    var animation = getAnimation()!;
    if (turning && getTime() >= animation.duration) {
      turning = false;
      animation = getAnimation()!;
    }
    animation.apply(mascot, getTime());

    if (mascot.lookRight && mascot.anchor.x >= targetX ||
        !mascot.lookRight && mascot.anchor.x <= targetX) {
      mascot.anchor.x = targetX;
    }
    if (down && mascot.anchor.y >= targetY ||
        !down && mascot.anchor.y <= targetY) {
      mascot.anchor.y = targetY;
    }

    final noMoveX = mascot.anchor.x == targetX;
    final noMoveY = mascot.anchor.y == targetY;
    if (!turning && noMoveX && noMoveY) {
      var setFirstBehavior = false;
      try {
        final selfConfiguration =
            EngineHooks.instance.configuration(mascot.imageSet);
        if (selfConfiguration != null) {
          mascot.setBehavior(
              selfConfiguration.buildBehaviorFor(getBehaviour(), mascot));
          setFirstBehavior = true;
        }
        final targetConfiguration =
            EngineHooks.instance.configuration(target.imageSet);
        if (targetConfiguration != null) {
          target.setBehavior(
              targetConfiguration.buildBehaviorFor(getTargetBehaviour(), target));
          if (isTargetLook() && target.lookRight == mascot.lookRight) {
            target.lookRight = !mascot.lookRight;
          }
        }
      } on BehaviorInstantiationException catch (e) {
        EngineHooks.instance.showError(
            'Failed to set behavior "${setFirstBehavior ? getTargetBehaviour() : getBehaviour()}"',
            e);
      }
    }
  }

  @override
  Animation? getAnimation() {
    for (final animation in animations) {
      if (turning == animation.isTurn && animation.isEffective(variables)) {
        return animation;
      }
    }
    return null;
  }

  bool hasTurningAnimation() {
    _hasTurning ??= animations.isNotEmpty && animations.any((a) => a.isTurn);
    return _hasTurning!;
  }

  @override
  String getAffordance() => evalString(schema.get('Affordance'), '');
  String getBehaviour() => evalString(schema.get('Behaviour'), '');
  String getTargetBehaviour() =>
      evalString(schema.get('TargetBehaviour'), '');
  bool isTargetLook() => evalBool(schema.get('TargetLook'), false);
}

/// Finds a mascot broadcasting the action's affordance and jumps to it.
class ScanJump extends ActionBase {
  Mascot? _target;
  double scaling = 1.0;

  ScanJump(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    scaling = EngineHooks.instance.scaling();
    mascot.affordances.clear();
    final manager = mascot.manager;
    if (manager != null) {
      final candidate = manager.getMascotWithAffordance(getAffordance());
      _target = candidate != null && !candidate.isDisposed() ? candidate : null;
    }
    variables.put(schema.get('TargetX'), _target?.anchor.x);
    variables.put(schema.get('TargetY'), _target?.anchor.y);
  }

  Mascot? get _liveTarget {
    final t = _target;
    return t != null && !t.isDisposed() ? t : null;
  }

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    if (mascot.manager == null) return true;
    final target = _liveTarget;
    return target != null && target.affordances.contains(getAffordance());
  }

  @override
  void tick() {
    mascot.affordances.clear();
    final target = _liveTarget;
    if (target == null) return;

    final targetX = target.anchor.x;
    final targetY = target.anchor.y;
    variables.put(schema.get('TargetX'), targetX);
    variables.put(schema.get('TargetY'), targetY);

    if (mascot.anchor.x != targetX) {
      mascot.lookRight = mascot.anchor.x < targetX;
    }

    final distanceX = targetX - mascot.anchor.x;
    final distanceY = targetY - mascot.anchor.y - distanceX.abs() / 2;
    final distance = _pythag(distanceX, distanceY);
    final velocity = getVelocity() * scaling;
    if (distance != 0) {
      final velocityX = velocity * distanceX / distance;
      final velocityY = velocity * distanceY / distance;
      variables.put(schema.get('VelocityX'), velocityX);
      variables.put(schema.get('VelocityY'), velocityY);
      mascot.anchor.translate(javaRound(velocityX), javaRound(velocityY));
      getAnimation()!.apply(mascot, getTime());
    }
    if (distance <= velocity) {
      mascot.anchor.setLocation(targetX, targetY);
      var setFirstBehavior = false;
      try {
        final selfConfiguration =
            EngineHooks.instance.configuration(mascot.imageSet);
        if (selfConfiguration != null) {
          mascot.setBehavior(
              selfConfiguration.buildBehaviorFor(getBehaviour(), mascot));
          setFirstBehavior = true;
        }
        final targetConfiguration =
            EngineHooks.instance.configuration(target.imageSet);
        if (targetConfiguration != null) {
          target.setBehavior(
              targetConfiguration.buildBehaviorFor(getTargetBehaviour(), target));
          if (isTargetLook() && target.lookRight == mascot.lookRight) {
            target.lookRight = !mascot.lookRight;
          }
        }
      } on BehaviorInstantiationException catch (e) {
        EngineHooks.instance.showError(
            'Failed to set behavior "${setFirstBehavior ? getTargetBehaviour() : getBehaviour()}"',
            e);
      }
    }
  }

  @override
  String getAffordance() => evalString(schema.get('Affordance'), '');
  String getBehaviour() => evalString(schema.get('Behaviour'), '');
  String getTargetBehaviour() => evalString(schema.get('TargetBehaviour'), '');
  bool isTargetLook() => evalBool(schema.get('TargetLook'), false);
  double getVelocity() =>
      evalDouble(schema.get('VelocityParam'), 20.0);
}

/// Stays in place until a mascot with the affordance comes close, then
/// interacts at the penultimate frame.
class ScanInteract extends BorderedAction {
  Mascot? _target;
  bool? _hasTurning;
  bool turning = false;

  ScanInteract(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    mascot.affordances.clear();
    variables.put(schema.get('TargetX'), null);
    variables.put(schema.get('TargetY'), null);
  }

  Mascot? get _liveTarget => _live(_target);

  static Mascot? _live(Mascot? mascot) =>
      mascot != null && !mascot.isDisposed() ? mascot : null;

  @override
  bool hasNext() {
    final animation = getAnimation();
    if (animation == null) return false;
    return super.hasNext() && (turning || getTime() < animation.duration);
  }

  @override
  void tick() {
    super.tick();
    mascot.affordances.clear();
    checkOnBorder();

    var target = _liveTarget;
    final manager = mascot.manager;
    if (manager != null &&
        (target == null || !target.affordances.contains(getAffordance()))) {
      _target = _live(manager.getMascotWithAffordance(getAffordance()));
      target = _liveTarget;
    }
    variables.put(schema.get('TargetX'), target?.anchor.x);
    variables.put(schema.get('TargetY'), target?.anchor.y);

    if (target != null && target.affordances.contains(getAffordance())) {
      if (mascot.anchor.x != target.anchor.x) {
        turning = hasTurningAnimation() &&
            (turning ||
                (mascot.anchor.x < target.anchor.x) != mascot.lookRight);
        mascot.lookRight = mascot.anchor.x < target.anchor.x;
      }
      var animation = getAnimation()!;
      if (turning && getTime() >= animation.duration) {
        setTime(getTime() - animation.duration);
        turning = false;
        animation = getAnimation()!;
      }
      animation.apply(mascot, getTime());
      animation = getAnimation()!;
      if (!turning &&
          (getTime() == animation.duration - 1 || animation.duration == 1) &&
          getBehaviour().trim().isNotEmpty) {
        var setFirstBehavior = false;
        try {
          final selfConfiguration =
              EngineHooks.instance.configuration(mascot.imageSet);
          if (selfConfiguration != null) {
            mascot.setBehavior(
                selfConfiguration.buildBehaviorFor(getBehaviour(), mascot));
            setFirstBehavior = true;
          }
          final targetBehaviour = getTargetBehaviour();
          if (targetBehaviour.trim().isNotEmpty) {
            final targetConfiguration =
                EngineHooks.instance.configuration(target.imageSet);
            if (targetConfiguration != null) {
              target.setBehavior(
                  targetConfiguration.buildBehavior(targetBehaviour, target));
            }
          }
          if (isTargetLook() && target.lookRight == mascot.lookRight) {
            target.lookRight = !mascot.lookRight;
          }
        } on BehaviorInstantiationException catch (e) {
          EngineHooks.instance.showError(
              'Failed to set behavior "${setFirstBehavior ? getTargetBehaviour() : getBehaviour()}"',
              e);
        }
      }
    }
  }

  @override
  Animation? getAnimation() {
    for (final animation in animations) {
      if (turning == animation.isTurn && animation.isEffective(variables)) {
        return animation;
      }
    }
    return null;
  }

  bool hasTurningAnimation() {
    _hasTurning ??= animations.isNotEmpty && animations.any((a) => a.isTurn);
    return _hasTurning!;
  }

  @override
  String getAffordance() => evalString(schema.get('Affordance'), '');
  String getBehaviour() => evalString(schema.get('Behaviour'), '');
  String getTargetBehaviour() =>
      evalString(schema.get('TargetBehaviour'), '');
  bool isTargetLook() => evalBool(schema.get('TargetLook'), false);
}

/// Unified Move with optional Breed/Scan characteristics.
class ComplexMove extends BorderedAction {
  late final BreedDelegate delegate = BreedDelegate(this);

  bool _breedEnabled = false;
  bool _scanEnabled = false;
  Mascot? _target;
  bool? _hasTurning;
  bool turning = false;

  static const int defaultTarget = 0x7FFFFFFF;

  ComplexMove(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    final characteristics = evalString(schema.get('Characteristics'), '');
    if (characteristics.isNotEmpty) {
      for (final characteristic in characteristics.split(',')) {
        if (characteristic == schema.get('Breed')) {
          _breedEnabled = true;
        } else if (characteristic == schema.get('Scan')) {
          _scanEnabled = true;
        }
      }
    }
    if (_breedEnabled) {
      delegate.initScaling();
      delegate.validateBornCount();
      delegate.validateBornInterval();
    }
    if (_scanEnabled) {
      mascot.affordances.clear();
      final manager = mascot.manager;
      if (manager != null) {
        final candidate = manager.getMascotWithAffordance(getAffordance());
        _target = candidate != null && !candidate.isDisposed() ? candidate : null;
      }
      variables.put(schema.get('TargetX'), _target?.anchor.x);
      variables.put(schema.get('TargetY'), _target?.anchor.y);
    }
  }

  Mascot? get _liveTarget {
    final t = _target;
    return t != null && !t.isDisposed() ? t : null;
  }

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    if (turning) return true;
    if (_scanEnabled) {
      if (mascot.manager == null) return true;
      final target = _liveTarget;
      return target != null && target.affordances.contains(getAffordance());
    } else {
      final targetX = getTargetX();
      final targetY = getTargetY();
      return targetX != defaultTarget && mascot.anchor.x != targetX ||
          targetY != defaultTarget && mascot.anchor.y != targetY;
    }
  }

  @override
  void tick() {
    super.tick();
    if (_scanEnabled) {
      mascot.affordances.clear();
    }
    checkOnBorder();

    int targetX;
    int targetY;
    final target = _liveTarget;
    if (_scanEnabled) {
      if (target == null) return;
      targetX = target.anchor.x;
      targetY = target.anchor.y;
      variables.put(schema.get('TargetX'), targetX);
      variables.put(schema.get('TargetY'), targetY);
    } else {
      targetX = getTargetX();
      targetY = getTargetY();
    }

    if (mascot.anchor.x != targetX) {
      turning = hasTurningAnimation() &&
          (turning || (mascot.anchor.x < targetX) != mascot.lookRight);
      mascot.lookRight = mascot.anchor.x < targetX;
    }
    final down = mascot.anchor.y < targetY;

    var animation = getAnimation()!;
    if (turning && getTime() >= animation.duration) {
      turning = false;
      animation = getAnimation()!;
    }
    animation.apply(mascot, getTime());

    if (targetX != defaultTarget || _scanEnabled) {
      if (mascot.lookRight && mascot.anchor.x >= targetX ||
          !mascot.lookRight && mascot.anchor.x <= targetX) {
        mascot.anchor.x = targetX;
      }
    }
    if (targetY != defaultTarget || _scanEnabled) {
      if (down && mascot.anchor.y >= targetY ||
          !down && mascot.anchor.y <= targetY) {
        mascot.anchor.y = targetY;
      }
    }

    if (_breedEnabled &&
        delegate.isIntervalFrame() &&
        !turning &&
        delegate.isEnabled()) {
      delegate.breed();
    }

    if (!turning && mascot.anchor.x == targetX && mascot.anchor.y == targetY) {
      var setFirstBehavior = false;
      try {
        final selfConfiguration =
            EngineHooks.instance.configuration(mascot.imageSet);
        if (selfConfiguration != null) {
          mascot.setBehavior(
              selfConfiguration.buildBehaviorFor(getBehaviour(), mascot));
          setFirstBehavior = true;
        }
        if (target != null) {
          final targetConfiguration =
              EngineHooks.instance.configuration(target.imageSet);
          if (targetConfiguration != null) {
            target.setBehavior(
                targetConfiguration.buildBehaviorFor(getTargetBehaviour(), target));
            if (isTargetLook() && target.lookRight == mascot.lookRight) {
              target.lookRight = !mascot.lookRight;
            }
          }
        }
      } on BehaviorInstantiationException catch (e) {
        EngineHooks.instance.showError(
            'Failed to set behavior "${setFirstBehavior ? getTargetBehaviour() : getBehaviour()}"',
            e);
      }
    }
  }

  @override
  Animation? getAnimation() {
    for (final animation in animations) {
      if (turning == animation.isTurn && animation.isEffective(variables)) {
        return animation;
      }
    }
    return null;
  }

  bool hasTurningAnimation() {
    _hasTurning ??= animations.isNotEmpty && animations.any((a) => a.isTurn);
    return _hasTurning!;
  }

  int getTargetX() => evalInt(schema.get('TargetX'), defaultTarget);
  int getTargetY() => evalInt(schema.get('TargetY'), defaultTarget);
  @override
  String getAffordance() => evalString(schema.get('Affordance'), '');
  String getBehaviour() => evalString(schema.get('Behaviour'), '');
  String getTargetBehaviour() => evalString(schema.get('TargetBehaviour'), '');
  bool isTargetLook() => evalBool(schema.get('TargetLook'), false);
}

/// Unified Jump with optional Breed/Scan characteristics.
class ComplexJump extends ActionBase {
  late final BreedDelegate delegate = BreedDelegate(this);

  bool _breedEnabled = false;
  bool _scanEnabled = false;
  Mascot? _target;
  double scaling = 1.0;

  ComplexJump(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    scaling = EngineHooks.instance.scaling();
    final characteristics = evalString(schema.get('Characteristics'), '');
    if (characteristics.isNotEmpty) {
      for (final characteristic in characteristics.split(',')) {
        if (characteristic == schema.get('Breed')) {
          _breedEnabled = true;
        } else if (characteristic == schema.get('Scan')) {
          _scanEnabled = true;
        }
      }
    }
    if (_breedEnabled) {
      delegate.initScaling();
      delegate.validateBornCount();
      delegate.validateBornInterval();
    }
    if (_scanEnabled) {
      mascot.affordances.clear();
      final manager = mascot.manager;
      if (manager != null) {
        final candidate = manager.getMascotWithAffordance(getAffordance());
        _target = candidate != null && !candidate.isDisposed() ? candidate : null;
      }
      variables.put(schema.get('TargetX'), _target?.anchor.x);
      variables.put(schema.get('TargetY'), _target?.anchor.y);
    }
  }

  Mascot? get _liveTarget {
    final t = _target;
    return t != null && !t.isDisposed() ? t : null;
  }

  @override
  bool hasNext() {
    if (!super.hasNext()) return false;
    if (_scanEnabled) {
      if (mascot.manager == null) return true;
      final target = _liveTarget;
      return target != null && target.affordances.contains(getAffordance());
    } else {
      final targetX = getTargetX();
      final targetY = getTargetY();
      final distanceX = targetX - mascot.anchor.x;
      final distanceY = targetY - mascot.anchor.y - distanceX.abs() / 2;
      final distance = _pythag(distanceX, distanceY);
      return distance != 0;
    }
  }

  @override
  void tick() {
    int targetX;
    int targetY;
    final target = _liveTarget;
    if (_scanEnabled) {
      mascot.affordances.clear();
      if (target == null) return;
      targetX = target.anchor.x;
      targetY = target.anchor.y;
      variables.put(schema.get('TargetX'), targetX);
      variables.put(schema.get('TargetY'), targetY);
    } else {
      targetX = getTargetX();
      targetY = getTargetY();
    }

    if (mascot.anchor.x != targetX) {
      mascot.lookRight = mascot.anchor.x < targetX;
    }
    final distanceX = targetX - mascot.anchor.x;
    final distanceY = targetY - mascot.anchor.y - distanceX.abs() / 2;
    final distance = _pythag(distanceX, distanceY);
    final velocity = getVelocity() * scaling;
    if (distance != 0) {
      final velocityX = velocity * distanceX / distance;
      final velocityY = velocity * distanceY / distance;
      variables.put(schema.get('VelocityX'), velocityX);
      variables.put(schema.get('VelocityY'), velocityY);
      mascot.anchor.translate(javaRound(velocityX), javaRound(velocityY));
      getAnimation()!.apply(mascot, getTime());
    }
    if (distance <= velocity) {
      mascot.anchor.setLocation(targetX, targetY);
      if (_scanEnabled) {
        var setFirstBehavior = false;
        try {
          final selfConfiguration =
              EngineHooks.instance.configuration(mascot.imageSet);
          if (selfConfiguration != null) {
            mascot.setBehavior(
                selfConfiguration.buildBehaviorFor(getBehaviour(), mascot));
            setFirstBehavior = true;
          }
          if (target != null) {
            final targetConfiguration =
                EngineHooks.instance.configuration(target.imageSet);
            if (targetConfiguration != null) {
              target.setBehavior(targetConfiguration
                  .buildBehaviorFor(getTargetBehaviour(), target));
              if (isTargetLook() && target.lookRight == mascot.lookRight) {
                target.lookRight = !mascot.lookRight;
              }
            }
          }
        } on BehaviorInstantiationException catch (e) {
          EngineHooks.instance.showError(
              'Failed to set behavior "${setFirstBehavior ? getTargetBehaviour() : getBehaviour()}"',
              e);
        }
      }
    }
    if (_breedEnabled &&
        delegate.isIntervalFrame() &&
        delegate.isEnabled()) {
      delegate.breed();
    }
  }

  int getTargetX() => evalInt(schema.get('TargetX'), 0);
  int getTargetY() => evalInt(schema.get('TargetY'), 0);
  double getVelocity() => evalDouble(schema.get('VelocityParam'), 20.0);
  @override
  String getAffordance() => evalString(schema.get('Affordance'), '');
  String getBehaviour() => evalString(schema.get('Behaviour'), '');
  String getTargetBehaviour() => evalString(schema.get('TargetBehaviour'), '');
  bool isTargetLook() => evalBool(schema.get('TargetLook'), false);
}

/// Throws the active window with a ballistic motion.
class ThrowIE extends Animate {
  double scaling = 1.0;
  int activeWindowId = 0;

  static const int defaultInitialVx = 32;
  static const int defaultInitialVy = -10;
  static const double defaultGravity = 0.5;

  ThrowIE(super.schema, super.animations, super.variables);

  @override
  void init(Mascot mascot) {
    super.init(mascot);
    scaling = EngineHooks.instance.scaling();
    activeWindowId = environment.getActiveWindowId();
  }

  @override
  bool hasNext() =>
      EngineHooks.instance.throwing() &&
      super.hasNext() &&
      environment.getActiveIE().isVisible &&
      activeWindowId == environment.getActiveWindowId();

  @override
  void tick() {
    super.tick();
    final activeIE = environment.getActiveIE();
    if (activeIE.isVisible) {
      if (mascot.lookRight) {
        environment.moveActiveIE(
            activeIE.left + javaRound(getInitialVx() * scaling),
            activeIE.top +
                javaRound(getInitialVy() * scaling +
                    getTime() * getGravity() * scaling));
      } else {
        environment.moveActiveIE(
            activeIE.left - javaRound(getInitialVx() * scaling),
            activeIE.top +
                javaRound(getInitialVy() * scaling +
                    getTime() * getGravity() * scaling));
      }
    }
  }

  int getInitialVx() => evalInt(schema.get('InitialVX'), defaultInitialVx);
  int getInitialVy() => evalInt(schema.get('InitialVY'), defaultInitialVy);
  double getGravity() => evalDouble(schema.get('Gravity'), defaultGravity);
}

// ---------------------------------------------------------------------------
// Deprecated affordance aliases (1.0.21): affordance broadcasting is built
// into ActionBase, so these are their base classes, kept for image sets that
// still reference the old class names.
// ---------------------------------------------------------------------------

/// Deprecated: use [Animate] (affordances are built into ActionBase).
class Broadcast extends Animate {
  Broadcast(super.schema, super.animations, super.variables);
}

/// Deprecated: use [Move].
class BroadcastMove extends Move {
  BroadcastMove(super.schema, super.animations, super.variables);
}

/// Deprecated: use [Jump].
class BroadcastJump extends Jump {
  BroadcastJump(super.schema, super.animations, super.variables);
}

/// Deprecated: use [Stay].
class BroadcastStay extends Stay {
  BroadcastStay(super.schema, super.animations, super.variables);
}

// ---------------------------------------------------------------------------
// Complex actions
// ---------------------------------------------------------------------------

/// Runs child actions in order, optionally looping.
class Sequence extends ComplexAction {
  Sequence(super.schema, super.variables, super.actions);

  @override
  bool hasNext() {
    seek();
    return super.hasNext();
  }

  @override
  void setCurrentAction(int index) {
    if (isLoop()) {
      super.setCurrentAction(index % actions.length);
    } else {
      super.setCurrentAction(index);
    }
  }

  bool isLoop() => variables.evalBool(schema.get('Loop'), false);
}

/// Runs the first child action whose conditions allow it to start.
class Select extends ComplexAction {
  Select(super.schema, super.variables, super.actions);
}
