/// Port of `behavior/BehaviorExecutionException.java`.
library;

class BehaviorExecutionException implements Exception {
  final String? message;
  final Object? cause;
  BehaviorExecutionException([this.message, this.cause]);

  @override
  String toString() => 'BehaviorExecutionException: $message';
}
