/// Port of `behavior/UserBehavior.java`.
library;

import 'dart:math' as math;

import '../action/base.dart';
import '../environment/area.dart';
import '../config/configuration.dart';
import '../mascot.dart';
import '../script/variable_map.dart';
import 'behavior.dart';

enum _HotspotState { inactive, activeNull, active }

class UserBehavior extends Behavior {
  final String name;
  final Action action;
  final Configuration configuration;
  Mascot? _mascot;

  UserBehavior(this.name, this.action, this.configuration);

  @override
  void init(Mascot mascot) {
    _mascot = mascot;
    try {
      action.init(mascot);
      if (!action.hasNext()) {
        mascot.setBehavior(configuration.buildNextBehavior(name, mascot));
      }
    } on VariableException {
      throw BehaviorExecutionException('Failed to evaluate a variable', null);
    }
  }

  @override
  void next() {
    final mascot = _mascot;
    if (mascot == null) return;

    try {
      var hotspotState = _HotspotState.inactive;
      if (action.hasNext()) {
        action.next();
      }
      if (mascot.isHotspotClicked) {
        if (mascot.hotspots.isNotEmpty) {
          for (final hotspot in mascot.hotspots) {
            if (hotspot.contains(mascot, mascot.cursor!)) {
              hotspotState = _HotspotState.activeNull;
              if (hotspot.behaviour != null) {
                hotspotState = _HotspotState.active;
                mascot.setBehavior(
                    configuration.buildBehaviorFor(hotspot.behaviour!, mascot));
              }
              break;
            }
          }
        }
        if (hotspotState == _HotspotState.inactive) {
          mascot.cursor = null;
        }
      }

      if (hotspotState != _HotspotState.active) {
        if (action.hasNext()) {
          final mascotBounds = mascot.bounds;
          final screen = mascot.environment.getScreen();
          if (mascotBounds.x + mascotBounds.width <= screen.left ||
              screen.right <= mascotBounds.x ||
              screen.bottom <= mascotBounds.y) {
            // Out of screen bounds: teleport above the work area and fall.
            final area = mascot.environment.getWorkArea();
            mascot.anchor.setLocation(
                (random() * (area.width - 2)).truncate() + area.left + 1,
                area.top - 256);
            mascot.setBehavior(configuration
                .buildBehavior(configuration.schema.get('Fall')));
          }
        } else {
          mascot.setBehavior(configuration.buildNextBehavior(name, mascot));
        }
      }
    } on LostGroundException {
      mascot.cursor = null;
      mascot.dragging = false;
      mascot.setBehavior(
          configuration.buildBehavior(configuration.schema.get('Fall')));
    } on VariableException {
      throw BehaviorExecutionException('Failed to evaluate a variable', null);
    }
  }

  @override
  void mousePressed(JPoint point) {
    final mascot = _mascot;
    if (mascot == null) return;
    var handled = false;
    if (mascot.hotspots.isNotEmpty) {
      for (final hotspot in mascot.hotspots) {
        if (hotspot.contains(mascot, point) &&
            configuration.isBehaviorEnabled(hotspot.behaviour, mascot)) {
          handled = true;
          mascot.cursor = point;
          if (hotspot.behaviour != null) {
            mascot.setBehavior(
                configuration.buildBehaviorFor(hotspot.behaviour!, mascot));
          }
          break;
        }
      }
    }
    if (!handled && action is ActionBase) {
      handled = !(action as ActionBase).isDraggable();
    }
    if (!handled) {
      mascot.setBehavior(
          configuration.buildBehavior(configuration.schema.get('Dragged')));
    }
  }

  @override
  void mouseReleased(JPoint point) {
    final mascot = _mascot;
    if (mascot == null) return;
    if (mascot.isHotspotClicked) {
      mascot.cursor = null;
    }
    if (mascot.dragging) {
      mascot.dragging = false;
      mascot.setBehavior(
          configuration.buildBehavior(configuration.schema.get('Thrown')));
    }
  }
}

/// A shared Random for behavior logic (Math.random equivalent).
final math.Random _sharedRandom = math.Random();

double random() => _sharedRandom.nextDouble();
