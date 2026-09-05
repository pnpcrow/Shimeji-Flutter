/// Port of `config/ActionBuilder.java` and `config/ActionRef.java`.
library;

import 'package:xml/xml.dart';

import 'configuration.dart';
import '../action/actions.dart';
import '../action/base.dart';
import '../animation/animation.dart';
import '../script/variable_map.dart';
import 'animation_builder.dart';
import 'exceptions.dart';
import 'schema.dart';
import 'xml_util.dart';

/// Registry of embedded action classes, keyed by their Java class simple name
/// (the XML `Class` attribute carries fully-qualified names).
final Map<String, Action Function(Schema, List<Animation>, VariableMap)>
    embeddedActionFactories = {
  'Fall': (s, a, v) => Fall(s, a, v),
  'FallWithIE': (s, a, v) => FallWithIE(s, a, v),
  'WalkWithIE': (s, a, v) => WalkWithIE(s, a, v),
  'Jump': (s, a, v) => Jump(s, a, v),
  'Move': (s, a, v) => Move(s, a, v),
  'Stay': (s, a, v) => Stay(s, a, v),
  'Animate': (s, a, v) => Animate(s, a, v),
  'Turn': (s, a, v) => Turn(s, a, v),
  'Breed': (s, a, v) => Breed(s, a, v),
  'BreedMove': (s, a, v) => BreedMove(s, a, v),
  'BreedJump': (s, a, v) => BreedJump(s, a, v),
  'Dragged': (s, a, v) => Dragged(s, a, v),
  'Regist': (s, a, v) => Regist(s, a, v),
  'ThrowIE': (s, a, v) => ThrowIE(s, a, v),
  'SelfDestruct': (s, a, v) => SelfDestruct(s, a, v),
  'Transform': (s, a, v) => Transform(s, a, v),
  'Interact': (s, a, v) => Interact(s, a, v),
  'ScanMove': (s, a, v) => ScanMove(s, a, v),
  'ScanJump': (s, a, v) => ScanJump(s, a, v),
  'ScanInteract': (s, a, v) => ScanInteract(s, a, v),
  'ComplexMove': (s, a, v) => ComplexMove(s, a, v),
  'ComplexJump': (s, a, v) => ComplexJump(s, a, v),
  'MoveWithTurn': (s, a, v) => MoveWithTurn(s, a, v),
  // Deprecated affordance aliases (1.0.21): affordances are built into
  // ActionBase now, so these are their base classes.
  'Broadcast': (s, a, v) => Animate(s, a, v),
  'BroadcastMove': (s, a, v) => Move(s, a, v),
  'BroadcastJump': (s, a, v) => Jump(s, a, v),
  'BroadcastStay': (s, a, v) => Stay(s, a, v),
  // Instant actions ignore the animation list.
  'Look': (s, a, v) => Look(s, v),
  'Offset': (s, a, v) => Offset(s, v),
  'Mute': (s, a, v) => Mute(s, v),
};

enum ActionType { embedded, move, stay, animate, sequence, select }

abstract class IActionBuilder {
  void validate();
  Action buildAction(Map<String, String> params);
}

class ActionBuilder implements IActionBuilder {
  final Configuration configuration;
  final String imageSet;
  final String? name; // null when anonymous
  final ActionType type;
  final String? className;
  final Map<String, String> params;
  final List<AnimationBuilder> animationBuilders = [];
  final List<IActionBuilder> childActionBuilders = [];

  ActionBuilder(this.configuration, XmlElement actionNode, this.imageSet,
      {bool isAnonymous = false})
      : name = isAnonymous
            ? null
            : (actionNode.attr(configuration.schema.get('Name')) ?? ''),
        type = _parseType(
            actionNode.attr(configuration.schema.get('Type')) ?? ''),
        className = actionNode.attr(configuration.schema.get('Class')),
        params = <String, String>{
          for (final a in actionNode.attributes) a.name.local: a.value,
        } {
    final schema = configuration.schema;

    // All attribute values must at least be parseable.
    for (final entry in params.entries) {
      try {
        Variable.parse(entry.value);
      } on VariableException catch (e) {
        throw ConfigurationException(
            'Failed to parse parameter ${entry.key}', e);
      }
    }

    final animationNodes =
        actionNode.childElements.where((e) => e.isNamed(schema.get('Animation')));
    for (final animationNode in animationNodes) {
      try {
        animationBuilders
            .add(AnimationBuilder(configuration, animationNode, imageSet));
      } on ConfigurationException {
        rethrow;
      }
    }

    final isComplexAction =
        type == ActionType.sequence || type == ActionType.select;
    for (final node in actionNode.childElements) {
      final isReference = node.isNamed(schema.get('ActionReference'));
      if (isReference || node.isNamed(schema.get('Action'))) {
        if (!isComplexAction) {
          throw ConfigurationException(
              'Child actions are not supported for type ${schema.get('Type')}');
        }
        try {
          childActionBuilders.add(isReference
              ? ActionRef(configuration, node)
              : ActionBuilder(configuration, node, imageSet,
                  isAnonymous: true));
        } on ConfigurationException {
          rethrow;
        }
      }
    }

    if (isComplexAction && childActionBuilders.isEmpty) {
      throw ConfigurationException('No child actions for $typeString');
    }
  }

  String get typeString {
    switch (type) {
      case ActionType.embedded:
        return 'Embedded';
      case ActionType.move:
        return 'Move';
      case ActionType.stay:
        return 'Stay';
      case ActionType.animate:
        return 'Animate';
      case ActionType.sequence:
        return 'Sequence';
      case ActionType.select:
        return 'Select';
    }
  }

  static ActionType _parseType(String typeString) {
    switch (typeString) {
      case 'Embedded':
        return ActionType.embedded;
      case 'Move':
        return ActionType.move;
      case 'Stay':
        return ActionType.stay;
      case 'Animate':
        return ActionType.animate;
      case 'Sequence':
        return ActionType.sequence;
      case 'Select':
        return ActionType.select;
      default:
        throw ConfigurationException('Unknown action type: $typeString');
    }
  }

  @override
  void validate() {
    for (final ref in childActionBuilders) {
      ref.validate();
    }
    for (final animationBuilder in animationBuilders) {
      animationBuilder.validate();
    }
  }

  @override
  Action buildAction(Map<String, String> params) {
    final variables = _createVariables(params);
    final animations = <Animation>[
      for (final builder in animationBuilders) builder.buildAnimation(),
    ];
    final actions = <Action>[
      for (final builder in childActionBuilders)
        builder.buildAction(const {}),
    ];

    switch (type) {
      case ActionType.embedded:
        final simpleName = (className ?? '').split('.').last;
        final factory = embeddedActionFactories[simpleName];
        if (factory == null) {
          throw ActionInstantiationException(
              'Embedded action class not supported: $className');
        }
        return factory(configuration.schema, animations, variables);
      case ActionType.move:
        return Move(configuration.schema, animations, variables);
      case ActionType.stay:
        return Stay(configuration.schema, animations, variables);
      case ActionType.animate:
        return Animate(configuration.schema, animations, variables);
      case ActionType.sequence:
        return Sequence(configuration.schema, variables, actions);
      case ActionType.select:
        return Select(configuration.schema, variables, actions);
    }
  }

  VariableMap _createVariables(Map<String, String> params) {
    final variables = VariableMap();
    for (final entry in this.params.entries) {
      variables.put(entry.key, Variable.parse(entry.value));
    }
    for (final entry in params.entries) {
      variables.put(entry.key, Variable.parse(entry.value));
    }
    return variables;
  }
}

/// A reference to a top-level action with optional parameter overrides.
class ActionRef implements IActionBuilder {
  final Configuration configuration;
  final String name;
  final Map<String, String> params;

  ActionRef(this.configuration, XmlElement refNode)
      : name = refNode.attr(configuration.schema.get('Name')) ?? '',
        params = <String, String>{
          for (final a in refNode.attributes) a.name.local: a.value,
        } {
    for (final entry in params.entries) {
      try {
        Variable.parse(entry.value);
      } on VariableException catch (e) {
        throw ConfigurationException(
            'Failed to parse parameter ${entry.key}', e);
      }
    }
  }

  @override
  void validate() {
    if (!configuration.actionBuilders.containsKey(name)) {
      throw ConfigurationException('No action found: $name');
    }
  }

  @override
  Action buildAction(Map<String, String> params) {
    final Map<String, String> newParams;
    if (this.params.isEmpty && params.isEmpty) {
      newParams = const {};
    } else if (this.params.isEmpty) {
      newParams = params;
    } else if (params.isEmpty) {
      newParams = this.params;
    } else {
      newParams = <String, String>{}
        ..addAll(params)
        ..addAll(this.params);
    }
    return configuration.buildAction(name, newParams);
  }
}
