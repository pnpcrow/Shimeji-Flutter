/// Port of `config/Configuration.java`.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../settings.dart';

import '../action/base.dart' show Action;
import '../behavior/behavior.dart' show Behavior;
import '../action/globals.dart';
import '../environment/area.dart';
import '../mascot.dart';
import '../script/variable_map.dart';
import 'action_builder.dart';
import 'behavior_builder.dart';
import 'exceptions.dart';
import 'schema.dart';
import 'xml_util.dart';

/// A loaded image-set configuration: actions + behaviors parsed from
/// actions.xml / behaviors.xml.
class Configuration {
  final Map<String, String> constants = {};
  final Map<String, ActionBuilder> actionBuilders = {};
  final Map<String, BehaviorBuilder> behaviorBuilders = {};
  late Schema schema;
  String? displayName;
  String? previewImagePath;
  String? splashImagePath;

  /// Global settings accessor (scaling for hotspots, etc.).
  late Settings settings;

  /// Picks the schema from the root tag name and parses the document.
  ///
  /// After [load], call [loadPoseImages] then [validate].
  void load(XmlElement rootNode, String imageSet) {
    final rootTagName = rootNode.name.local;
    if (rootTagName == Schema.ja.get('Mascot')) {
      schema = Schema.ja;
    } else if (rootTagName == Schema.en.get('Mascot')) {
      schema = Schema.en;
    } else {
      throw ConfigurationException('Unrecognized root tag name: $rootTagName');
    }

    for (final constantNode
        in rootNode.namedChildren(schema.get('Constant'))) {
      final name = constantNode.attr(schema.get('Name'));
      final value = constantNode.attr(schema.get('Value'));
      constants[name] = value;
    }

    for (final actionList in rootNode.namedChildren(schema.get('ActionList'))) {
      for (final actionNode
          in actionList.namedChildren(schema.get('Action'))) {
        final ActionBuilder action;
        try {
          action = ActionBuilder(this, actionNode, imageSet);
        } on ConfigurationException {
          rethrow;
        } catch (e) {
          throw ConfigurationException('Failed to load action', e);
        }
        if (actionBuilders.containsKey(action.name)) {
          throw ConfigurationException('Duplicate action: ${action.name}');
        }
        actionBuilders[action.name!] = action;
      }
    }

    for (final behaviorList
        in rootNode.namedChildren(schema.get('BehaviourList'))) {
      _loadBehaviors(behaviorList, const []);
    }

    for (final infoNode in rootNode.namedChildren(schema.get('Information'))) {
      _loadInformation(infoNode);
    }
  }

  void _loadBehaviors(XmlElement list, List<String> conditions) {
    for (final node in list.childElements) {
      if (node.isNamed(schema.get('Condition'))) {
        final newConditions = <String>[...conditions];
        final conditionText = node.attr(schema.get('Condition'));
        if (conditionText.isNotEmpty) {
          try {
            Variable.parse(conditionText);
          } on VariableException catch (e) {
            throw ConfigurationException('Failed to parse condition', e);
          }
          newConditions.add(conditionText);
        }
        _loadBehaviors(node, newConditions);
      } else if (node.isNamed(schema.get('Behaviour'))) {
        final BehaviorBuilder behavior;
        try {
          behavior = BehaviorBuilder(this, node, conditions);
        } on ConfigurationException {
          rethrow;
        } catch (e) {
          throw ConfigurationException('Failed to load behavior', e);
        }
        if (behaviorBuilders.containsKey(behavior.name)) {
          throw ConfigurationException(
              'Duplicate behavior: ${behavior.name}');
        }
        behaviorBuilders[behavior.name] = behavior;
      }
    }
  }

  void _loadInformation(XmlElement infoNode) {
    for (final node in infoNode.childElements) {
      final nodeName = node.name.local;
      if (nodeName == schema.get('Name')) {
        displayName = node.textContent;
      } else if (nodeName == schema.get('PreviewImage')) {
        previewImagePath = node.textContent;
      } else if (nodeName == schema.get('SplashImage')) {
        splashImagePath = node.textContent;
      }
    }
  }

  /// Loads all pose images of all actions (asynchronous decoding).
  Future<void> loadPoseImages() async {
    for (final builder in actionBuilders.values) {
      for (final animationBuilder in builder.animationBuilders) {
        await animationBuilder.loadPoses(settings);
      }
    }
  }

  void validate() {
    for (final builder in actionBuilders.values) {
      builder.validate();
    }
    for (final builder in behaviorBuilders.values) {
      builder.validate();
    }
    final requiredBehaviors = [
      schema.get('ChaseMouse'),
      schema.get('Fall'),
      schema.get('Dragged'),
      schema.get('Thrown'),
    ];
    final missing = <String>[];
    for (final required in requiredBehaviors) {
      if (!behaviorBuilders.containsKey(required)) {
        missing.add(required);
      }
    }
    if (missing.isNotEmpty) {
      throw ConfigurationException(
          'Missing required behaviors: ${missing.join(", ")}');
    }
  }

  Action buildAction(String name, Map<String, String> params) {
    final builder = actionBuilders[name];
    if (builder == null) {
      throw ActionInstantiationException('No corresponding action found: $name');
    }
    return builder.buildAction(params);
  }

  /// Builds the next behavior for a mascot using the weighted-random
  /// frequency selection with condition filtering.
  Behavior buildNextBehavior(String? previousName, Mascot mascot) {
    final context = VariableMap();
    for (final entry in constants.entries) {
      context.put(entry.key, Variable.parse(entry.value));
    }
    context.putObject('mascot', MascotScriptObject(mascot));

    final candidates = <IBehaviorBuilder>[];
    var totalFrequency = 0;

    final prevBehaviorBuilder =
        previousName == null ? null : behaviorBuilders[previousName];

    if (prevBehaviorBuilder == null || prevBehaviorBuilder.isNextAdditive) {
      for (final behaviorBuilder in behaviorBuilders.values) {
        try {
          if (behaviorBuilder.isEffective(context) &&
              isBehaviorEnabledBuilder(behaviorBuilder, mascot)) {
            candidates.add(behaviorBuilder);
            totalFrequency += behaviorBuilder.frequency;
          }
        } on VariableException {
          // Failed conditions are skipped with a warning in the original.
        }
      }
    }

    if (prevBehaviorBuilder != null &&
        prevBehaviorBuilder.nextBehaviorBuilders.isNotEmpty) {
      for (final behaviorRef in prevBehaviorBuilder.nextBehaviorBuilders) {
        try {
          if (behaviorRef.isEffective(context) &&
              isBehaviorEnabled(behaviorRef.name, mascot)) {
            candidates.add(behaviorRef);
            totalFrequency += behaviorRef.frequency;
          }
        } on VariableException {
          // Skipped.
        }
      }
    }

    if (totalFrequency > 0) {
      var random = math.Random().nextDouble() * totalFrequency;
      for (final builder in candidates) {
        random -= builder.frequency;
        if (random < 0) {
          return builder.buildBehavior();
        }
      }
    }

    // No candidates: teleport above the work area and fall.
    final area = EngineHooks.instance.multiscreen()
        ? mascot.environment.getScreen()
        : mascot.environment.getWorkArea();
    _teleportAbove(mascot.anchor, area);
    return buildBehavior(schema.get('Fall'));
  }

  void _teleportAbove(JPoint anchor, Area area) {
    anchor.setLocation(
        (math.Random().nextDouble() * (area.width - 2)).truncate() +
            area.left +
            1,
        area.top - 256);
  }

  Behavior buildBehaviorFor(String name, Mascot mascot) {
    if (behaviorBuilders.containsKey(name)) {
      if (isBehaviorEnabled(name, mascot)) {
        return behaviorBuilders[name]!.buildBehavior();
      } else {
        final area = EngineHooks.instance.multiscreen()
            ? mascot.environment.getScreen()
            : mascot.environment.getWorkArea();
        _teleportAbove(mascot.anchor, area);
        return buildBehavior(schema.get('Fall'));
      }
    } else {
      throw BehaviorInstantiationException('No behavior found: $name', name);
    }
  }

  Behavior buildBehavior(String name) {
    final builder = behaviorBuilders[name];
    if (builder == null) {
      throw BehaviorInstantiationException('No behavior found: $name', name);
    }
    return builder.buildBehavior();
  }

  bool isBehaviorEnabledBuilder(BehaviorBuilder builder, Mascot mascot) {
    final disabled = EngineHooks.instance.disabledBehaviorsFor(mascot.imageSet);
    if (builder.toggleable && disabled != null) {
      return !disabled.contains(builder.name);
    }
    return true;
  }

  bool isBehaviorEnabled(String? name, Mascot mascot) {
    if (name == null) return false;
    final builder = behaviorBuilders[name];
    if (builder == null) return false;
    return isBehaviorEnabledBuilder(builder, mascot);
  }

  bool isBehaviorHidden(String name) =>
      behaviorBuilders[name]?.isHidden ?? false;

  bool isBehaviorToggleable(String name) =>
      behaviorBuilders[name]?.toggleable ?? false;

  Iterable<String> get behaviorNames => behaviorBuilders.keys;

  /// Resolves a sound file path (img/<set>/sound/, sound/<set>/, sound/).
  String resolveSoundPath(String imageSet, String soundText) {
    final candidates = [
      'img/$imageSet/sound/$soundText',
      'sound/$imageSet/$soundText',
      'sound/$soundText',
    ];
    for (final candidate in candidates) {
      final file = File(resolveAppPath(candidate));
      if (file.existsSync()) return file.path;
    }
    return resolveAppPath(candidates.first);
  }
}

/// Resolves a path relative to the application directory; assigned at startup.
String Function(String) resolveAppPath = (p) => p;
