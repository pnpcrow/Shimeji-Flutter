/// Mascot context menu model, mirroring `Mascot.showPopup` in the Java
/// original. The menu is presented as a native Win32 popup.
///
/// The behavior list is grouped into nested submenus so the top level stays
/// short even with the 40+ behaviors of the default image set:
///
/// ```
/// Call Another / Follow Cursor / Restore Windows
/// ──
/// 핵심 행동 (ChaseMouse, ...)
/// Set Behaviour ▸  (그룹별 하위 메뉴: Sit / Walk & Run / Jump / Wall / Ceiling / IE / Throw / Other)
/// Allowed Behaviours ▸ (토글 가능한 행동, 체크박스)
/// ──
/// Pause
/// ──
/// Dismiss 그룹
/// ──
/// 설정
/// ```
///
/// Selection is positional: the native side numbers every selectable entry
/// depth-first (separators and submenu headers are not selectable), and Dart
/// walks its tree in the same order to find the matching action.
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
    if (_isLower(prev) && _isUpper(ch)) {
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

/// Keyword-based grouping rules. The first matching keyword decides the
/// group; unmatched behaviors land in [_groupOther].
const List<(String groupKey, List<String> keywords)> _groupRules = [
  ('groupSit', ['Sit', 'LieDown', 'Dangle', 'PullUp']),
  ('groupJump', ['Jump', 'Split', 'Divid']),
  ('groupWall', ['Wall', 'Climb']),
  ('groupCeiling', ['Ceiling']),
  ('groupIE', ['IE', 'Edge']),
  ('groupThrow', ['Throw']),
  ('groupWalkRun', ['Walk', 'Run', 'Crawl', 'Grab', 'Hold', 'Fall']),
];

const String _groupOther = 'groupOther';

const List<String> _groupOrder = [
  'groupSit',
  'groupWalkRun',
  'groupJump',
  'groupWall',
  'groupCeiling',
  'groupIE',
  'groupThrow',
  _groupOther,
];

String _groupFor(String behaviorName) {
  for (final (key, keywords) in _groupRules) {
    for (final keyword in keywords) {
      if (behaviorName.toLowerCase().contains(keyword.toLowerCase())) {
        return key;
      }
    }
  }
  return _groupOther;
}

/// One selectable menu entry and the action to run when it is chosen.
class _ActionEntry {
  final NativeMenuEntry entry;
  final void Function() action;
  _ActionEntry(this.entry, this.action);
}

/// Mutable builder shared while assembling the menu: keeps the flat list of
/// actions aligned with the native depth-first selectable numbering.
class _MenuBuilder {
  final entries = <NativeMenuEntry>[];
  final actions = <void Function()>[];

  void addItem(NativeMenuEntry entry, void Function() action) {
    entries.add(entry);
    actions.add(action);
  }

  void addSeparator() => entries.add(const NativeMenuEntry.separator());

  void addSubmenu(String label, List<_ActionEntry> children) {
    entries.add(NativeMenuEntry.submenu(label,
        [for (final child in children) child.entry]));
    actions.addAll([for (final child in children) child.action]);
  }
}

/// Builds the context menu entries for [mascot]. The returned list is
/// positional: the native menu returns the chosen index into this list.
List<NativeMenuEntry> buildContextMenu(ShimejiApp app, dynamic mascot) {
  final lang = app.languageBundle;
  final configuration = app.configurationFor(mascot.imageSet as String);
  final builder = _MenuBuilder();

  builder.addItem(NativeMenuEntry.label(lang.getString('CallAnother')),
      () => app.createMascot(mascot.imageSet as String));
  builder.addSeparator();
  builder.addItem(
    NativeMenuEntry.label(lang.getString('FollowCursor')),
    () {
      final configuration = app.configurationFor(mascot.imageSet as String);
      if (configuration != null) {
        app.manager.setBehaviorAllFor(
            configuration, 'ChaseMouse', mascot.imageSet as String);
      }
    },
  );
  builder.addItem(NativeMenuEntry.label(lang.getString('RestoreWindows')),
      () => mascot.environment.restoreIE());

  if (configuration != null) {
    // Core behaviors that the original keeps at the top level.
    const core = {'ChaseMouse', 'Fall', 'Dragged', 'Thrown'};
    for (final behaviorName in configuration.behaviorNames) {
      if (configuration.isBehaviorHidden(behaviorName)) continue;
      if (behaviorName.contains('/')) continue;
      if (!core.contains(behaviorName)) continue;
      if (!configuration.isBehaviorEnabled(behaviorName, mascot)) continue;
      final displayName = lang.containsKey(behaviorName)
          ? lang.getString(behaviorName)
          : splitCamelCase(behaviorName);
      builder.addItem(NativeMenuEntry.label(displayName), () {
        try {
          mascot.setBehavior(configuration.buildBehavior(behaviorName));
        } catch (_) {}
      });
    }

    // Grouped behaviors: nested submenu per group.
    final groups = <String, List<_ActionEntry>>{};
    for (final behaviorName in configuration.behaviorNames) {
      if (configuration.isBehaviorHidden(behaviorName)) continue;
      if (behaviorName.contains('/')) continue;
      if (core.contains(behaviorName)) continue;
      if (!configuration.isBehaviorEnabled(behaviorName, mascot)) continue;
      final displayName = lang.containsKey(behaviorName)
          ? lang.getString(behaviorName)
          : splitCamelCase(behaviorName);
      final group = _groupFor(behaviorName);
      groups.putIfAbsent(group, () => []);
      groups[group]!.add(_ActionEntry(
        NativeMenuEntry.label(displayName),
        () {
          try {
            mascot.setBehavior(configuration.buildBehavior(behaviorName));
          } catch (_) {}
        },
      ));
    }
    builder.addSeparator();
    for (final groupKey in _groupOrder) {
      final items = groups[groupKey];
      if (items == null || items.isEmpty) continue;
      builder.addSubmenu(lang.getString(groupKey), items);
    }
  }

  builder.addSeparator();
  builder.addItem(
    NativeMenuEntry.label(mascot.paused
        ? lang.getString('ResumeAnimations')
        : lang.getString('PauseAnimations')),
    () => mascot.paused = !(mascot.paused as bool),
  );
  builder.addSeparator();
  builder.addItem(NativeMenuEntry.label(lang.getString('Dismiss')),
      () => mascot.dispose());
  builder.addItem(NativeMenuEntry.label(lang.getString('DismissOthers')),
      () => app.manager.remainOneImageSetExcept(mascot.imageSet as String, mascot));
  builder.addItem(NativeMenuEntry.label(lang.getString('DismissAllOthers')),
      () => app.manager.remainOneMascot(mascot));
  builder.addItem(NativeMenuEntry.label(lang.getString('DismissAll')),
      () => app.exit());

  builder.addSeparator();
  if (app.onOpenSettings != null) {
    builder.addItem(NativeMenuEntry.label(lang.getString('Settings')),
        () => app.onOpenSettings!());
  }

  // The native layer numbers selectable entries depth-first; register the
  // actions in that same order so selection indices map correctly.
  mascot.contextMenuActions = builder.actions;
  return builder.entries;
}
