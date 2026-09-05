/// Port of `script/Variable.java`, `script/Script.java` and
/// `script/VariableMap.java`.
///
/// A [VariableMap] is the per-action evaluation scope. Keys map either to a
/// [Variable] (XML parameter, `<Constant>`, engine-written value) or to a live
/// [ScriptObject] (`mascot`, `action`). Scripts are compiled expressions with
/// Nashorn-compatible caching semantics: `${...}` scripts are evaluated once
/// per action initialization, `#{...}` scripts are re-evaluated every frame.
library;

import 'expression.dart';
import 'script_object.dart';

class VariableException implements Exception {
  final String message;
  VariableException(this.message);

  @override
  String toString() => 'VariableException: $message';
}

abstract class Variable {
  /// Parses a raw XML attribute value into a Variable.
  ///
  /// `${...}` and `#{...}` become scripts; everything else becomes a constant
  /// (booleans, numbers, or the raw string).
  static Variable? parse(String? source) {
    if (source == null) return null;
    if (source.startsWith(r'${') && source.endsWith('}')) {
      return ScriptVariable(source.substring(2, source.length - 1), false);
    } else if (source.startsWith('#{') && source.endsWith('}')) {
      return ScriptVariable(source.substring(2, source.length - 1), true);
    } else {
      return Constant(parseConstant(source));
    }
  }

  static Object? parseConstant(String source) {
    if (source == 'true') return true;
    if (source == 'false') return false;
    final d = double.tryParse(source);
    return d ?? source;
  }

  void init();
  void resetValue();
  Object? get(VariableMap variables);
}

class Constant extends Variable {
  final Object? value;
  Constant(this.value);

  @override
  void init() {}

  @override
  void resetValue() {}

  @override
  Object? get(VariableMap variables) => value;

  @override
  String toString() => 'Constant($value)';
}

class ScriptVariable extends Variable {
  final String source;
  final bool allowValueReset;
  late final Expression _expr;
  Object? _value;
  bool _needsReevaluation = true;

  ScriptVariable(this.source, this.allowValueReset) {
    _expr = ExpressionParser.parse(source);
  }

  @override
  void init() {
    _value = null;
    _needsReevaluation = true;
  }

  @override
  void resetValue() {
    if (allowValueReset) {
      _value = null;
      _needsReevaluation = true;
    }
  }

  @override
  Object? get(VariableMap variables) {
    if (!_needsReevaluation) return _value;
    _value = variables.evaluateExpression(_expr, source);
    _needsReevaluation = false;
    return _value;
  }

  @override
  String toString() => '${allowValueReset ? '#' : '\$'}{$source}';
}

/// Port of `script/VariableMap.java`. Implements the script scope: all keys
/// are visible to scripts as top-level identifiers, and `mascot` / `action`
/// are live objects.
class VariableMap {
  final Map<String, Variable> rawMap = <String, Variable>{};
  final Map<String, ScriptObject> _objects = <String, ScriptObject>{};

  Map<String, Variable> getRawMap() => rawMap;

  /// Binds a live script object (e.g. `mascot`).
  void putObject(String key, ScriptObject object) => _objects[key] = object;

  void put(String key, Object? value) {
    if (value is Variable) {
      rawMap[key] = value;
    } else {
      rawMap[key] = Constant(value);
    }
  }

  Object? remove(String key) => rawMap.remove(key);

  void clear() {
    rawMap.clear();
    _objects.clear();
  }

  void init() {
    for (final v in rawMap.values) {
      v.init();
    }
  }

  void resetValues() {
    for (final v in rawMap.values) {
      v.resetValue();
    }
  }

  /// Resolves a key: live objects first, then variables.
  Object? getValue(String key) {
    final obj = _objects[key];
    if (obj != null) return obj;
    final v = rawMap[key];
    return v?.get(this);
  }

  /// Evaluates a compiled expression with this map as the scope.
  Object? evaluateExpression(Expression expr, String source) {
    try {
      return expr.evaluate(getValue);
    } on ScriptException catch (e) {
      throw VariableException('Failed to evaluate "${e.message}" in "$source"');
    }
  }

  /// Convenience for engine code: numeric parameter with truncation toward
  /// zero (matches Java `Number.intValue()` on Nashorn's Doubles).
  int evalInt(String key, int fallback) {
    final v = rawMap[key];
    if (v == null) return fallback;
    final value = v.get(this);
    if (value is num) {
      // Java Double.intValue() truncates toward zero.
      return value.isInfinite
          ? (value.isNegative ? -0x7FFFFFFFFFFFFFFF : 0x7FFFFFFFFFFFFFFF)
          : value.truncate();
    }
    if (value is bool) return value ? 1 : 0;
    if (value is String) {
      final d = double.tryParse(value);
      if (d != null) return d.truncate();
    }
    return fallback;
  }

  double evalDouble(String key, double fallback) {
    final v = rawMap[key];
    if (v == null) return fallback;
    final value = v.get(this);
    if (value is num) return value.toDouble();
    if (value is bool) return value ? 1 : 0;
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  bool evalBool(String key, bool fallback) {
    final v = rawMap[key];
    if (v == null) return fallback;
    final value = v.get(this);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return fallback;
  }

  String evalString(String key, String fallback) {
    final v = rawMap[key];
    if (v == null) return fallback;
    final value = v.get(this);
    if (value == null) return fallback;
    return value.toString();
  }

  /// Evaluates a condition string against this scope (used by builders).
  static bool evalCondition(String condition, VariableMap context) {
    final variable = Variable.parse(condition);
    if (variable == null) return true;
    final value = variable.get(context);
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value != null;
  }
}
