/// Live objects exposed to the scripting layer.
///
/// The Java original passes live objects (Mascot, MascotEnvironment, Border,
/// ...) into the Nashorn engine, which resolves properties through JavaBean
/// getters. The Dart port implements the same idea with [ScriptObject]:
/// property navigation (`mascot.environment.cursor.x`) resolves through
/// [getProperty] and method calls (`mascot.environment.floor.isOn(anchor)`)
/// through [callMethod].
abstract class ScriptObject {
  const ScriptObject();

  /// Resolves a property by its script name (JS-style camelCase).
  Object? getProperty(String name) => null;

  /// Invokes a method by its script name with the given arguments.
  Object? callMethod(String name, List<Object?> args) => null;
}

/// A read-only point with `x` / `y` properties.
class ScriptPoint extends ScriptObject {
  final int Function() _x;
  final int Function() _y;

  ScriptPoint(this._x, this._y);

  int get x => _x();
  int get y => _y();

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

/// Wraps a plain map so scripts can navigate it like an object.
class ScriptMap extends ScriptObject {
  final Map<String, Object?> map;
  ScriptMap(this.map);

  @override
  Object? getProperty(String name) => map[name];
}
