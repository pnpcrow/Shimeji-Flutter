/// A small JavaScript-subset expression engine that replaces the Nashorn
/// scripting engine of the Java original.
///
/// Shimeji configuration scripts are condition/parameter expressions such as
/// `#{mascot.environment.floor.isOn(mascot.anchor) && FootX < cursor.x + 50}`
/// or `${100 + Math.random() * 100}`. This engine supports exactly the
/// constructs used by Shimeji image sets:
///
/// * literals (numbers, strings, `true`, `false`, `null`)
/// * property navigation (`mascot.environment.cursor.x`)
/// * method calls on properties (`mascot.environment.floor.isOn(p)`)
/// * the `Math` object (`random`, `abs`, `min`, `max`, `floor`, `ceil`, `round`, `pow`, `sqrt`, ...)
/// * arithmetic (`+ - * / %`), comparison (`< <= > >= == != === !==`),
///   logic (`! && ||`) with JavaScript truthiness, and the ternary operator
/// * string concatenation through `+`
library;

import 'dart:math' as math;

import 'script_object.dart';

class ScriptException implements Exception {
  final String message;
  ScriptException(this.message);

  @override
  String toString() => 'ScriptException: $message';
}

/// Compiled expression (AST root).
class Expression {
  final _Node _root;
  Expression._(this._root);

  /// Evaluates the expression. [resolve] resolves a top-level identifier
  /// (a [VariableMap] key); it may return `null` for unknown names.
  Object? evaluate(Object? Function(String name) resolve) {
    return _root.eval(resolve);
  }
}

class _MathObject extends ScriptObject {
  const _MathObject();

  double _num(Object? v, int i) {
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
    if (v is String) return double.tryParse(v) ?? double.nan;
    if (v == null) return 0;
    return double.nan;
  }

  @override
  Object? callMethod(String name, List<Object?> args) {
    double n(int i) => i < args.length ? _num(args[i], i) : double.nan;
    switch (name) {
      case 'random':
        return math.Random().nextDouble();
      case 'abs':
        return n(0).abs();
      case 'min':
        var m = n(0);
        for (var i = 1; i < args.length; i++) {
          final v = n(i);
          if (v.isNaN || m.isNaN) return double.nan;
          if (v < m) m = v;
        }
        return m;
      case 'max':
        var m = n(0);
        for (var i = 1; i < args.length; i++) {
          final v = n(i);
          if (v.isNaN || m.isNaN) return double.nan;
          if (v > m) m = v;
        }
        return m;
      case 'floor':
        return n(0).floorToDouble();
      case 'ceil':
        return n(0).ceilToDouble();
      case 'round':
        // Java Math.round(double): floor(x + 0.5)
        return (n(0) + 0.5).floorToDouble();
      case 'pow':
        return _safePow(n(0), n(1));
      case 'sqrt':
        final v = n(0);
        return v < 0 ? double.nan : math.sqrt(v);
      case 'sin':
        return math.sin(n(0));
      case 'cos':
        return math.cos(n(0));
      case 'tan':
        return math.tan(n(0));
      case 'atan':
        return math.atan(n(0));
      case 'atan2':
        return math.atan2(n(0), n(1));
      case 'exp':
        return math.exp(n(0));
      case 'log':
        final v = n(0);
        return v <= 0 ? double.nan : math.log(v);
    }
    throw ScriptException('Unsupported Math method: $name');
  }

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'PI':
        return math.pi;
      case 'E':
        return math.e;
    }
    return null;
  }

  double _safePow(double x, double y) {
    try {
      final r = math.pow(x, y);
      return r.toDouble();
    } catch (_) {
      return double.nan;
    }
  }
}

const _math = _MathObject();

// ---------------------------------------------------------------------------
// Evaluation helpers (JavaScript semantics)
// ---------------------------------------------------------------------------

bool _truthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

double _toNumber(Object? v) {
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v == null) return 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? double.nan;
  }
  return double.nan;
}

String _toStr(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is double) {
    if (v.isFinite && v == v.truncateToDouble() && v.abs() < 1e15) {
      return v.truncate().toString();
    }
    return v.toString();
  }
  return v.toString();
}

bool _looseEquals(Object? l, Object? r) {
  if (l == null && r == null) return true;
  if (l == null || r == null) return false;
  if (l is bool || r is bool) return _toNumber(l) == _toNumber(r);
  if (l is num && r is String) return l == (double.tryParse(r) ?? double.nan);
  if (l is String && r is num) return (double.tryParse(l) ?? double.nan) == r;
  if (l is num && r is num) return l.toDouble() == r.toDouble();
  return l == r;
}

bool _strictEquals(Object? l, Object? r) {
  if (l is num && r is num) return l.toDouble() == r.toDouble();
  if (l.runtimeType != r.runtimeType) return false;
  return l == r;
}

Object? _getProperty(Object? target, String name) {
  if (target is ScriptObject) return target.getProperty(name);
  if (target is Map) return target[name];
  if (target == null) return null; // forgiving: null.x -> null
  throw ScriptException('Cannot read property "$name" of ${target.runtimeType}');
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

abstract class _Node {
  Object? eval(Object? Function(String name) resolve);
}

class _Literal implements _Node {
  final Object? value;
  _Literal(this.value);

  @override
  Object? eval(Object? Function(String name) resolve) => value;
}

class _Ident implements _Node {
  final String name;
  _Ident(this.name);

  @override
  Object? eval(Object? Function(String name) resolve) {
    if (name == 'Math') return _math;
    return resolve(name);
  }
}

class _Unary implements _Node {
  final String op;
  final _Node operand;
  _Unary(this.op, this.operand);

  @override
  Object? eval(Object? Function(String name) resolve) {
    final v = operand.eval(resolve);
    switch (op) {
      case '!':
        return !_truthy(v);
      case '-':
        return -_toNumber(v);
      case '+':
        return _toNumber(v);
    }
    throw ScriptException('Unknown unary operator $op');
  }
}

class _Binary implements _Node {
  final String op;
  final _Node left;
  final _Node right;
  _Binary(this.op, this.left, this.right);

  @override
  Object? eval(Object? Function(String name) resolve) {
    // Short-circuiting operators return operand values like JavaScript.
    if (op == '&&') {
      final l = left.eval(resolve);
      return _truthy(l) ? right.eval(resolve) : l;
    }
    if (op == '||') {
      final l = left.eval(resolve);
      return _truthy(l) ? l : right.eval(resolve);
    }
    final l = left.eval(resolve);
    final r = right.eval(resolve);
    switch (op) {
      case '+':
        if (l is String || r is String) return _toStr(l) + _toStr(r);
        return _toNumber(l) + _toNumber(r);
      case '-':
        return _toNumber(l) - _toNumber(r);
      case '*':
        return _toNumber(l) * _toNumber(r);
      case '/':
        final d = _toNumber(r);
        if (d == 0) return double.nan; // JS division by zero
        return _toNumber(l) / d;
      case '%':
        // JS remainder keeps the sign of the dividend (Java's % too).
        return _toNumber(l).remainder(_toNumber(r));
      case '<':
        return _toNumber(l) < _toNumber(r);
      case '>':
        return _toNumber(l) > _toNumber(r);
      case '<=':
        return _toNumber(l) <= _toNumber(r);
      case '>=':
        return _toNumber(l) >= _toNumber(r);
      case '==':
        return _looseEquals(l, r);
      case '!=':
        return !_looseEquals(l, r);
      case '===':
        return _strictEquals(l, r);
      case '!==':
        return !_strictEquals(l, r);
    }
    throw ScriptException('Unknown binary operator $op');
  }
}

class _Ternary implements _Node {
  final _Node condition;
  final _Node thenExpr;
  final _Node elseExpr;
  _Ternary(this.condition, this.thenExpr, this.elseExpr);

  @override
  Object? eval(Object? Function(String name) resolve) {
    return _truthy(condition.eval(resolve))
        ? thenExpr.eval(resolve)
        : elseExpr.eval(resolve);
  }
}

class _Property implements _Node {
  final _Node target;
  final String name;
  _Property(this.target, this.name);

  @override
  Object? eval(Object? Function(String name) resolve) {
    final t = target.eval(resolve);
    return _getProperty(t, name);
  }
}

class _MethodCall implements _Node {
  final _Node target;
  final String name;
  final List<_Node> args;
  _MethodCall(this.target, this.name, this.args);

  @override
  Object? eval(Object? Function(String name) resolve) {
    final t = target.eval(resolve);
    final evaluated = [for (final a in args) a.eval(resolve)];
    if (t is ScriptObject) {
      return t.callMethod(name, evaluated);
    }
    if (t == null) {
      return null; // forgiving: null.foo() -> null
    }
    throw ScriptException('Object of type ${t.runtimeType} has no method $name');
  }
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

class _Token {
  final String type; // num, str, ident, op, eof
  final String text;
  final Object? value;
  _Token(this.type, this.text, [this.value]);
}

class _Tokenizer {
  final String src;
  int pos = 0;
  _Tokenizer(this.src);

  _Token next() {
    while (pos < src.length && _isSpace(src[pos])) {
      pos++;
    }
    if (pos >= src.length) return _Token('eof', '');
    final c = src[pos];
    if (_isDigit(c) || (c == '.' && pos + 1 < src.length && _isDigit(src[pos + 1]))) {
      final start = pos;
      while (pos < src.length && (_isDigit(src[pos]) || src[pos] == '.')) {
        pos++;
      }
      if (pos < src.length && (src[pos] == 'e' || src[pos] == 'E')) {
        final save = pos;
        pos++;
        if (pos < src.length && (src[pos] == '+' || src[pos] == '-')) pos++;
        if (pos < src.length && _isDigit(src[pos])) {
          while (pos < src.length && _isDigit(src[pos])) {
            pos++;
          }
        } else {
          pos = save;
        }
      }
      final text = src.substring(start, pos);
      return _Token('num', text, double.tryParse(text) ?? 0.0);
    }
    if (c == '\'' || c == '"') {
      final quote = c;
      pos++;
      final buf = StringBuffer();
      while (pos < src.length && src[pos] != quote) {
        if (src[pos] == '\\' && pos + 1 < src.length) {
          pos++;
          final esc = src[pos];
          switch (esc) {
            case 'n':
              buf.write('\n');
              break;
            case 't':
              buf.write('\t');
              break;
            case 'r':
              buf.write('\r');
              break;
            default:
              buf.write(esc);
          }
        } else {
          buf.write(src[pos]);
        }
        pos++;
      }
      if (pos >= src.length) throw ScriptException('Unterminated string');
      pos++;
      return _Token('str', buf.toString(), buf.toString());
    }
    if (_isIdentStart(c)) {
      final start = pos;
      while (pos < src.length && _isIdentPart(src[pos])) {
        pos++;
      }
      return _Token('ident', src.substring(start, pos));
    }
    for (final op in const [
      '===', '!==', '==', '!=', '<=', '>=', '&&', '||',
    ]) {
      if (src.startsWith(op, pos)) {
        pos += op.length;
        return _Token('op', op);
      }
    }
    pos++;
    return _Token('op', c);
  }

  static bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isIdentStart(String c) => _isLetter(c) || c == '_' || c == '\$';
  static bool _isIdentPart(String c) => _isLetter(c) || _isDigit(c) || c == '_' || c == '\$';
  static bool _isLetter(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u > 0x7F;
  }
}

// ---------------------------------------------------------------------------
// Parser (recursive descent)
// ---------------------------------------------------------------------------

class ExpressionParser {
  final List<_Token> tokens;
  int index = 0;

  ExpressionParser._(this.tokens);

  static Expression parse(String source) {
    final tokenizer = _Tokenizer(source);
    final tokens = <_Token>[];
    while (true) {
      final t = tokenizer.next();
      tokens.add(t);
      if (t.type == 'eof') break;
    }
    final parser = ExpressionParser._(tokens);
    final node = parser.parseTernary();
    if (parser.peek().type != 'eof') {
      throw ScriptException('Unexpected token: "${parser.peek().text}"');
    }
    return Expression._(node);
  }

  _Token peek() => tokens[index];
  _Token advance() => tokens[index++];

  bool matchOp(String op) {
    final t = peek();
    if (t.type == 'op' && t.text == op) {
      index++;
      return true;
    }
    return false;
  }

  _Token expectOp(String op) {
    final t = advance();
    if (t.type != 'op' || t.text != op) {
      throw ScriptException('Expected "$op" but found "${t.text}"');
    }
    return t;
  }

  _Node parseTernary() {
    final cond = parseOr();
    if (matchOp('?')) {
      final thenExpr = parseTernary();
      expectOp(':');
      final elseExpr = parseTernary();
      return _Ternary(cond, thenExpr, elseExpr);
    }
    return cond;
  }

  _Node parseOr() {
    var node = parseAnd();
    while (matchOp('||')) {
      node = _Binary('||', node, parseAnd());
    }
    return node;
  }

  _Node parseAnd() {
    var node = parseEquality();
    while (matchOp('&&')) {
      node = _Binary('&&', node, parseEquality());
    }
    return node;
  }

  _Node parseEquality() {
    var node = parseRelational();
    while (true) {
      final t = peek();
      if (t.type == 'op' &&
          (t.text == '==' || t.text == '!=' || t.text == '===' || t.text == '!==')) {
        index++;
        node = _Binary(t.text, node, parseRelational());
      } else {
        return node;
      }
    }
  }

  _Node parseRelational() {
    var node = parseAdditive();
    while (true) {
      final t = peek();
      if (t.type == 'op' &&
          (t.text == '<' || t.text == '>' || t.text == '<=' || t.text == '>=')) {
        index++;
        node = _Binary(t.text, node, parseAdditive());
      } else {
        return node;
      }
    }
  }

  _Node parseAdditive() {
    var node = parseMultiplicative();
    while (true) {
      final t = peek();
      if (t.type == 'op' && (t.text == '+' || t.text == '-')) {
        index++;
        node = _Binary(t.text, node, parseMultiplicative());
      } else {
        return node;
      }
    }
  }

  _Node parseMultiplicative() {
    var node = parseUnary();
    while (true) {
      final t = peek();
      if (t.type == 'op' && (t.text == '*' || t.text == '/' || t.text == '%')) {
        index++;
        node = _Binary(t.text, node, parseUnary());
      } else {
        return node;
      }
    }
  }

  _Node parseUnary() {
    final t = peek();
    if (t.type == 'op' && (t.text == '!' || t.text == '-' || t.text == '+')) {
      index++;
      return _Unary(t.text, parseUnary());
    }
    return parsePostfix();
  }

  _Node parsePostfix() {
    var node = parsePrimary();
    while (true) {
      final t = peek();
      if (t.type == 'op' && t.text == '.') {
        index++;
        final nameTok = advance();
        if (nameTok.type != 'ident') {
          throw ScriptException('Expected property name after "."');
        }
        if (peek().type == 'op' && peek().text == '(') {
          index++;
          final args = <_Node>[];
          if (!(peek().type == 'op' && peek().text == ')')) {
            args.add(parseTernary());
            while (matchOp(',')) {
              args.add(parseTernary());
            }
          }
          expectOp(')');
          node = _MethodCall(node, nameTok.text, args);
        } else {
          node = _Property(node, nameTok.text);
        }
      } else {
        return node;
      }
    }
  }

  _Node parsePrimary() {
    final t = advance();
    switch (t.type) {
      case 'num':
        return _Literal(t.value as double);
      case 'str':
        return _Literal(t.value as String);
      case 'ident':
        switch (t.text) {
          case 'true':
            return _Literal(true);
          case 'false':
            return _Literal(false);
          case 'null':
            return _Literal(null);
        }
        return _Ident(t.text);
      case 'op':
        if (t.text == '(') {
          final node = parseTernary();
          expectOp(')');
          return node;
        }
        throw ScriptException('Unexpected token "${t.text}"');
      default:
        throw ScriptException('Unexpected token "${t.text}"');
    }
  }
}
