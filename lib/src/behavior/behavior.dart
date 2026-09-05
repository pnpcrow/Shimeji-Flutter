/// Port of `behavior/Behavior.java` and `behavior/BehaviorExecutionException`.
library;

import '../environment/area.dart' show JPoint;
import '../mascot.dart';

export 'behavior_execution_exception.dart';

/// A mascot behavior: wraps an action and reacts to input.
abstract class Behavior {
  void init(Mascot mascot);
  void next();
  void mousePressed(JPoint point);
  void mouseReleased(JPoint point);
}
