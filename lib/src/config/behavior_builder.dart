/// Port of `config/BehaviorBuilder.java` and `config/BehaviorRef.java`.
library;

import 'package:xml/xml.dart';

import '../behavior/behavior.dart';
import '../behavior/user_behavior.dart';
import '../script/variable_map.dart';
import 'configuration.dart';
import 'exceptions.dart';
import 'xml_util.dart';

abstract class IBehaviorBuilder {
  Behavior buildBehavior();
  int get frequency;
}

class BehaviorBuilder implements IBehaviorBuilder {
  final Configuration configuration;
  final String name;
  final String actionName;
  @override
  final int frequency;
  final List<String> conditions = [];
  final bool hidden;
  bool toggleable = false;
  bool nextAdditive = true;
  final List<BehaviorRef> nextBehaviorBuilders = [];
  final Map<String, String> params = {};

  BehaviorBuilder(this.configuration, XmlElement behaviorNode,
      List<String> inheritedConditions)
      : name = behaviorNode.attr(configuration.schema.get('Name')) ?? '',
        actionName =
            behaviorNode.attr(configuration.schema.get('Action')) ?? '',
        frequency = int.tryParse(
                behaviorNode
                        .attr(configuration.schema.get('Frequency')) ??
                    '') ??
            0,
        hidden =
            behaviorNode.attr(configuration.schema.get('Hidden')) ==
                'true' {
    final schema = configuration.schema;
    final effectiveActionName = actionName.isEmpty ? name : actionName;
    _actionName = effectiveActionName;

    final behaviorConditions = <String>[...inheritedConditions];
    final conditionText = behaviorNode.attr(schema.get('Condition'));
    if (conditionText.isNotEmpty) {
      try {
        Variable.parse(conditionText);
      } on VariableException catch (e) {
        throw ConfigurationException('Failed to parse condition', e);
      }
      behaviorConditions.add(conditionText);
    }
    conditions.addAll(behaviorConditions);

    final required = <String>{
      schema.get('ChaseMouse'),
      schema.get('Fall'),
      schema.get('Thrown'),
      schema.get('Dragged'),
    };
    final toggleableText = behaviorNode.attr(schema.get('Toggleable'));
    toggleable = toggleableText.isNotEmpty &&
        !required.contains(name) &&
        toggleableText == 'true';

    // All other attributes become parameters for the action.
    final excluded = <String>{
      schema.get('Name'),
      schema.get('Action'),
      schema.get('Frequency'),
      schema.get('Hidden'),
      schema.get('Condition'),
      schema.get('Toggleable'),
    };
    for (final attribute in behaviorNode.attributes) {
      if (!excluded.contains(attribute.name.local)) {
        params[attribute.name.local] = attribute.value;
      }
    }
    for (final entry in params.entries) {
      try {
        Variable.parse(entry.value);
      } on VariableException catch (e) {
        throw ConfigurationException(
            'Failed to parse parameter ${entry.key}', e);
      }
    }

    final nextLists =
        behaviorNode.namedChildren(schema.get('NextBehaviourList')).toList();
    if (nextLists.isEmpty) {
      nextAdditive = true;
    } else {
      var additive = true;
      for (final nextList in nextLists) {
        final addText = nextList.attr(schema.get('Add'));
        if (addText.isEmpty) {
          throw ConfigurationException('Missing Add attribute');
        }
        additive = addText == 'true';
        _loadBehaviors(nextList, const [], nextBehaviorBuilders);
      }
      nextAdditive = additive;
    }
  }

  late final String _actionName;

  void _loadBehaviors(XmlElement list, List<String> conditions,
      List<BehaviorRef> nextBehaviorBuilders) {
    for (final node in list.childElements) {
      if (node.isNamed(configuration.schema.get('Condition'))) {
        final newConditions = <String>[...conditions];
        final conditionText =
            node.attr(configuration.schema.get('Condition'));
        if (conditionText.isNotEmpty) {
          try {
            Variable.parse(conditionText);
          } on VariableException catch (e) {
            throw ConfigurationException('Failed to parse condition', e);
          }
          newConditions.add(conditionText);
        }
        _loadBehaviors(node, newConditions, nextBehaviorBuilders);
      } else if (node.isNamed(configuration.schema.get('BehaviourReference'))) {
        nextBehaviorBuilders
            .add(BehaviorRef(configuration, node, conditions));
      }
    }
  }

  void validate() {
    if (!configuration.actionBuilders.containsKey(_actionName)) {
      throw ConfigurationException('No action found: $_actionName');
    }
    for (final ref in nextBehaviorBuilders) {
      ref.validate();
    }
  }

  @override
  Behavior buildBehavior() => buildBehaviorWithParams(const {});

  Behavior buildBehaviorWithParams(Map<String, String> params) {
    final Map<String, String> newParams;
    if (this.params.isEmpty && params.isEmpty) {
      newParams = const {};
    } else if (this.params.isEmpty) {
      newParams = params;
    } else if (params.isEmpty) {
      newParams = this.params;
    } else {
      newParams = <String, String>{}
        ..addAll(this.params)
        ..addAll(params);
    }
    return UserBehavior(
        name, configuration.buildAction(_actionName, newParams), configuration);
  }

  bool isEffective(VariableMap context) {
    if (frequency == 0) return false;
    for (final condition in conditions) {
      if (!VariableMap.evalCondition(condition, context)) {
        return false;
      }
    }
    return true;
  }

  bool get isHidden => hidden;
  bool get isToggleable => toggleable;
  bool get isNextAdditive => nextAdditive;
}

/// A reference to another behavior inside a NextBehaviorList.
class BehaviorRef implements IBehaviorBuilder {
  final Configuration configuration;
  final String name;
  @override
  final int frequency;
  final List<String> conditions = [];
  final Map<String, String> params = {};

  BehaviorRef(this.configuration, XmlElement refNode,
      List<String> inheritedConditions)
      : name = refNode.attr(configuration.schema.get('Name')) ?? '',
        frequency = int.tryParse(
                refNode
                        .attr(configuration.schema.get('Frequency')) ??
                    '') ??
            0 {
    final schema = configuration.schema;
    final behaviorConditions = <String>[...inheritedConditions];
    final conditionText = refNode.attr(schema.get('Condition'));
    if (conditionText.isNotEmpty) {
      try {
        Variable.parse(conditionText);
      } on VariableException catch (e) {
        throw ConfigurationException('Failed to parse condition', e);
      }
      behaviorConditions.add(conditionText);
    }
    conditions.addAll(behaviorConditions);

    final excluded = <String>{
      schema.get('Name'),
      schema.get('Action'),
      schema.get('Frequency'),
      schema.get('Hidden'),
      schema.get('Condition'),
      schema.get('Toggleable'),
    };
    for (final attribute in refNode.attributes) {
      if (!excluded.contains(attribute.name.local)) {
        params[attribute.name.local] = attribute.value;
      }
    }
    for (final entry in params.entries) {
      try {
        Variable.parse(entry.value);
      } on VariableException catch (e) {
        throw ConfigurationException(
            'Failed to parse parameter ${entry.key}', e);
      }
    }
  }

  void validate() {
    if (!configuration.behaviorBuilders.containsKey(name)) {
      throw ConfigurationException('No behavior found: $name');
    }
  }

  @override
  Behavior buildBehavior() {
    final builder = configuration.behaviorBuilders[name];
    if (builder == null) {
      throw BehaviorInstantiationException('No behavior found: $name', name);
    }
    return builder.buildBehaviorWithParams(params);
  }

  bool isEffective(VariableMap context) {
    if (frequency == 0) return false;
    for (final condition in conditions) {
      if (!VariableMap.evalCondition(condition, context)) {
        return false;
      }
    }
    return true;
  }
}
