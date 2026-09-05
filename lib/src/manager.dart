/// Port of `Manager.java` — the global tick loop synchronizing all mascots.
library;

import 'dart:async';

import 'config/behavior_instantiation_exception.dart';
import 'config/configuration.dart';
import 'environment/area.dart';
import 'mascot.dart' show Mascot, ShimejiEnvironmentHolder;

class Manager {
  static const int tickInterval = 40; // ms, 25 FPS

  final List<Mascot> _mascots = [];
  final Set<Mascot> _added = {};
  final Set<Mascot> _removed = {};
  bool _exitOnLastRemoved = true;
  bool _enabled = true;
  Timer? _timer;
  bool _ticking = false;

  bool get exitOnLastRemoved => _exitOnLastRemoved;
  set exitOnLastRemoved(bool value) => _exitOnLastRemoved = value;

  /// Hooked by the app: called when the last mascot is removed.
  void Function()? onExitOnLastRemoved;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(
        const Duration(milliseconds: tickInterval), (_) => _timerFired());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _timerFired() {
    if (!_enabled || _ticking) return;
    _ticking = true;
    try {
      tick();
    } catch (_) {
      // Errors are logged by the engine callers; never kill the timer.
    } finally {
      _ticking = false;
    }
  }

  void tick() {
    final environment = ShimejiEnvironmentHolder.instance;
    if (environment != null) {
      environment.tick();
    }
    if (_added.isNotEmpty) {
      _mascots.addAll(_added);
      _added.clear();
    }
    if (_removed.isNotEmpty) {
      _mascots.removeWhere((m) => _removed.contains(m));
      _removed.clear();
    }
    final noMascots = _mascots.isEmpty;
    if (!noMascots) {
      for (final mascot in _mascots) {
        mascot.tick();
      }
      for (final mascot in _mascots) {
        mascot.apply();
      }
    }
    if (_exitOnLastRemoved && noMascots) {
      onExitOnLastRemoved?.call();
    }
  }

  Iterable<Mascot> get mascots => List.unmodifiable(_mascots);

  void add(Mascot mascot) {
    final oldManager = mascot.manager;
    if (identical(oldManager, this)) return;
    oldManager?.remove(mascot);
    _added.add(mascot);
    _removed.remove(mascot);
    mascot.manager = this;
  }

  void remove(Mascot mascot) {
    _added.remove(mascot);
    _removed.add(mascot);
    mascot.manager = null;
  }

  void setBehaviorAll(String name) {
    for (final mascot in _mascots) {
      final configuration = ConfigurationForHook(mascot.imageSet);
      if (configuration == null) continue;
      try {
        mascot.setBehavior(configuration
            .buildBehaviorFor(configuration.schema.get(name), mascot));
      } on BehaviorInstantiationException catch (e) {
        ShowErrorHook('Failed to set behavior to "$name"', e);
        mascot.dispose();
      }
    }
  }

  void setBehaviorAllFor(Configuration configuration, String name, String imageSet) {
    for (final mascot in _mascots) {
      try {
        if (mascot.imageSet == imageSet) {
          mascot.setBehavior(
              configuration.buildBehaviorFor(configuration.schema.get(name), mascot));
        }
      } on BehaviorInstantiationException catch (e) {
        ShowErrorHook('Failed to set behavior to "$name"', e);
        mascot.dispose();
      }
    }
  }

  void remainOne() {
    for (var i = _mascots.length - 1; i > 0; i--) {
      _mascots[i].dispose();
    }
  }

  void remainOneMascot(Mascot mascot) {
    for (var i = _mascots.length - 1; i >= 0; i--) {
      if (!identical(_mascots[i], mascot)) {
        _mascots[i].dispose();
      }
    }
  }

  void remainOneImageSet(String imageSet) {
    var isFirst = true;
    for (var i = _mascots.length - 1; i >= 0; i--) {
      final m = _mascots[i];
      if (m.imageSet == imageSet && isFirst) {
        isFirst = false;
      } else if (m.imageSet == imageSet && !isFirst) {
        m.dispose();
      }
    }
  }

  void remainOneImageSetExcept(String imageSet, Mascot mascot) {
    for (var i = _mascots.length - 1; i >= 0; i--) {
      final m = _mascots[i];
      if (m.imageSet == imageSet && !identical(m, mascot)) {
        m.dispose();
      }
    }
  }

  void remainNone(String imageSet) {
    for (var i = _mascots.length - 1; i >= 0; i--) {
      if (_mascots[i].imageSet == imageSet) {
        _mascots[i].dispose();
      }
    }
  }

  void disposeAll() {
    for (var i = _mascots.length - 1; i >= 0; i--) {
      _mascots[i].dispose();
    }
  }

  bool get isPaused =>
      _mascots.isNotEmpty && _mascots.every((m) => m.paused);

  void togglePauseAll() {
    if (_mascots.isEmpty) return;
    final isPaused = _mascots.every((m) => m.paused);
    for (final mascot in _mascots) {
      mascot.paused = !isPaused;
    }
  }

  bool get enabled => _enabled;
  set enabled(bool value) => _enabled = value;

  int getCount([String? imageSet]) {
    if (_mascots.isEmpty) return 0;
    if (imageSet == null) return _mascots.length;
    return _mascots.where((m) => m.imageSet == imageSet).length;
  }

  Mascot? getMascotWithAffordance(String affordance) {
    for (final mascot in _mascots) {
      if (mascot.affordances.contains(affordance)) {
        return mascot;
      }
    }
    return null;
  }

  bool hasOverlappingMascotsAtPoint(JPoint anchor) {
    var count = 0;
    for (final mascot in _mascots) {
      if (mascot.anchor == anchor) {
        count++;
        if (count > 1) return true;
      }
    }
    return false;
  }
}

/// Hooks set by the app.
Configuration? Function(String imageSet) ConfigurationForHook = (_) => null;
void Function(String message, [Object? error]) ShowErrorHook = (_, [_]) {};
