/// Mascot context menu model, mirroring `Mascot.showPopup` in the Java
/// original. The menu is presented as a native Win32 popup; each entry maps
/// to the action it triggers when chosen.
library;

import '../app.dart';
import '../native/mascot_windows.dart';

/// Splits a CamelCase behavior name for display, matching the Java
/// `replaceAll("([a-z])(IE)?([A-Z])", "$1 $2 $3")` formatting.
String splitCamelCase(String name) {
  final buffer = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final ch = name[i];
    final prev = i > 0 ? name[i - 1] : '';
    final next = i + 1 < name.length ? name[i + 1] : '';
    final boundary = _isLower(prev) && _isUpper(ch);
    if (boundary) {
      buffer.write(' ');
      // Java keeps "IE" pairs together ("PullUpIE" -> "Pull Up IE").
      if (ch == 'I' && next == 'E') {
        buffer.write('IE');
        i++;
        continue;
      }
    }
    buffer.write(ch);
  }
  return buffer.toString().replaceAll('  ', ' ');
}

bool _isLower(String c) => c.isNotEmpty && c.toLowerCase() == c;
bool _isUpper(String c) => c.isNotEmpty && c.toUpperCase() == c;

/// Builds the context menu entries for [mascot]. The returned list is
/// positional: the native menu returns the chosen index into this list.
List<NativeMenuEntry> buildContextMenu(ShimejiApp app, dynamic mascot) {
  final lang = app.languageBundle;
  final configuration = app.configurationFor(mascot.imageSet as String);
  final entries = <NativeMenuEntry>[];
  final actions = <void Function()>[];

  void add(NativeMenuEntry entry, void Function()? action) {
    entries.add(entry);
    actions.add(action ?? () {});
  }

  add(NativeMenuEntry.label(lang.getString('CallAnother')),
      () => app.createMascot(mascot.imageSet as String));

  add(const NativeMenuEntry.separator(), null);

  add(
    NativeMenuEntry.label(lang.getString('FollowCursor')),
    () {
      final configuration = app.configurationFor(mascot.imageSet as String);
      if (configuration != null) {
        app.manager.setBehaviorAllFor(
            configuration, 'ChaseMouse', mascot.imageSet as String);
      }
    },
  );
  add(NativeMenuEntry.label(lang.getString('RestoreWindows')),
      () => mascot.environment.restoreIE());
  // RevealStatistics opens the Java DebugWindow; the headless port has no
  // stats surface, so the entry is omitted.

  if (configuration != null) {
    for (final behaviorName in configuration.behaviorNames) {
      if (configuration.isBehaviorHidden(behaviorName)) continue;
      if (behaviorName.contains('/')) continue;
      if (!configuration.isBehaviorEnabled(behaviorName, mascot)) continue;
      final displayName = lang.containsKey(behaviorName)
          ? lang.getString(behaviorName)
          : splitCamelCase(behaviorName);
      add(NativeMenuEntry.label(displayName), () {
        try {
          mascot.setBehavior(configuration.buildBehavior(behaviorName));
        } catch (_) {}
      });
    }
    for (final behaviorName in configuration.behaviorNames) {
      if (!configuration.isBehaviorToggleable(behaviorName)) continue;
      if (behaviorName.contains('/')) continue;
      final enabled = configuration.isBehaviorEnabled(behaviorName, mascot);
      final displayName = lang.containsKey(behaviorName)
          ? lang.getString(behaviorName)
          : splitCamelCase(behaviorName);
      add(NativeMenuEntry.label(displayName, checked: enabled), () {
        final disabled = app.settings.disabledBehaviors[mascot.imageSet] ?? [];
        final newDisabled = <String>[...disabled];
        if (enabled) {
          newDisabled.add(behaviorName);
        } else {
          newDisabled.remove(behaviorName);
        }
        if (newDisabled.isEmpty) {
          app.settings.disabledBehaviors.remove(mascot.imageSet);
        } else {
          app.settings.disabledBehaviors[mascot.imageSet] = newDisabled;
        }
        app.saveSettings();
      });
    }
  }

  add(const NativeMenuEntry.separator(), null);
  add(
    NativeMenuEntry.label(mascot.paused
        ? lang.getString('ResumeAnimations')
        : lang.getString('PauseAnimations')),
    () => mascot.paused = !(mascot.paused as bool),
  );
  add(const NativeMenuEntry.separator(), null);
  add(NativeMenuEntry.label(lang.getString('Dismiss')),
      () => mascot.dispose());
  add(NativeMenuEntry.label(lang.getString('DismissOthers')),
      () => app.manager.remainOneImageSetExcept(mascot.imageSet as String, mascot));
  add(NativeMenuEntry.label(lang.getString('DismissAllOthers')),
      () => app.manager.remainOneMascot(mascot));
  add(NativeMenuEntry.label(lang.getString('DismissAll')), () => app.exit());

  // The native layer returns a positional index; expose the actions in the
  // same order through the app-level hook.
  mascot.contextMenuActions = actions;
  return entries;
}
