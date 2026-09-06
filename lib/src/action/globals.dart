/// Engine-level hooks set at startup, replacing `Main.getInstance()` calls in
/// the Java original.
library;

import '../manager.dart';
import '../mascot.dart' show Mascot;

class EngineHooks {
  static EngineHooks instance = EngineHooks();

  late double Function() scaling = () => 1.0;
  late bool Function() breeding = () => true;
  late bool Function() transients = () => true;
  late bool Function() transformation = () => true;
  late bool Function() throwing = () => true;
  late bool Function() multiscreen = () => true;
  late ConfigurationGetter configuration = (_) => null;
  late List<String>? Function(String imageSet) disabledBehaviorsFor =
      (_) => null;
  late void Function(String message, [Object? error]) showError = (_, [_]) {};
  late Manager? Function() manager = () => null;

  /// Factory every mascot creation must go through so popups stay wired.
  late MascotFactory createMascot = (imageSet) => Mascot(imageSet);
}

typedef ConfigurationGetter = dynamic Function(String imageSet);
typedef MascotFactory = Mascot Function(String imageSet);
