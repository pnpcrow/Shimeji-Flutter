/// Configuration exceptions ported from the `config` package.
library;

class ConfigurationException implements Exception {
  final String message;
  final Object? cause;
  ConfigurationException(this.message, [this.cause]);

  @override
  String toString() => 'ConfigurationException: $message';
}

class ActionInstantiationException implements Exception {
  final String message;
  ActionInstantiationException(this.message);

  @override
  String toString() => 'ActionInstantiationException: $message';
}

class AnimationInstantiationException implements Exception {
  final String message;
  AnimationInstantiationException(this.message);

  @override
  String toString() => 'AnimationInstantiationException: $message';
}

class BehaviorInstantiationException implements Exception {
  final String message;
  final String behaviorName;
  BehaviorInstantiationException(this.message, [this.behaviorName = '']);

  @override
  String toString() => 'BehaviorInstantiationException: $message';
}
