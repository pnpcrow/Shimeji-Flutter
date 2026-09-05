/// UI state shared between the engine and the overlay widget tree.
library;

import 'package:flutter/foundation.dart';

import '../app.dart';
import '../mascot.dart' show Mascot;

enum UiMode { none, contextMenu, chooser, settings, stats }

/// A context-menu item or separator.
class MenuItem {
  final String? label;
  final VoidCallback? onTap;
  final bool checked;

  const MenuItem.separator()
      : label = null,
        onTap = null,
        checked = false;

  const MenuItem(this.label, this.onTap, {this.checked = false});

  bool get isSeparator => label == null;
}

/// A context menu with an optional submenu chain rendered as one panel
/// (simplified from the nested JMenu/JPopupMenu structure).
class MenuModel {
  final List<MenuItem> items;
  const MenuModel(this.items);
}

class AppUiState extends ChangeNotifier {
  UiMode mode = UiMode.none;

  /// The mascot whose context menu is open.
  Mascot? menuMascot;
  MenuModel? menuModel;
  double menuLeft = 0;
  double menuTop = 0;

  /// Set while the chooser/settings panels cover the overlay.
  bool get isFullScreenUi => mode == UiMode.chooser || mode == UiMode.settings;

  static AppUiState instance = AppUiState();

  void openContextMenu(Mascot mascot, MenuModel model, double left, double top) {
    mode = UiMode.contextMenu;
    menuMascot = mascot;
    menuModel = model;
    menuLeft = left;
    menuTop = top;
    mascot.animating = false; // Java pauses the mascot while the menu is open
    notifyListeners();
  }

  void closeMenu({bool resume = true}) {
    if (mode == UiMode.contextMenu) {
      final mascot = menuMascot;
      if (mascot != null && resume) {
        mascot.animating = true;
      }
      menuMascot = null;
      menuModel = null;
      mode = UiMode.none;
      notifyListeners();
    }
  }

  void show(UiMode newMode) {
    mode = newMode;
    menuMascot = null;
    menuModel = null;
    notifyListeners();
  }

  void closePanels() {
    if (isFullScreenUi) {
      mode = UiMode.none;
      notifyListeners();
    }
  }
}

/// Builds the mascot context menu (port of Mascot.showPopup).
MenuModel buildContextMenu(ShimejiApp app, Mascot mascot) {
  final lang = app.languageBundle;
  final configuration = app.configurationFor(mascot.imageSet);
  final items = <MenuItem>[];

  items.add(MenuItem(lang.getString('CallAnother'),
      () => app.createMascot(mascot.imageSet)));
  items.add(const MenuItem.separator());
  items.add(MenuItem(lang.getString('FollowCursor'), () {
    final configuration = app.configurationFor(mascot.imageSet);
    if (configuration != null) {
      app.manager.setBehaviorAllFor(
          configuration, 'ChaseMouse', mascot.imageSet);
    }
  }));
  items.add(MenuItem(lang.getString('RestoreWindows'),
      () => mascot.environment.restoreIE()));
  items.add(MenuItem(lang.getString('RevealStatistics'), () {
    AppUiState.instance.show(UiMode.stats);
  }));

  if (configuration != null) {
    final setBehaviourItems = <MenuItem>[];
    final allowedItems = <MenuItem>[];
    for (final behaviorName in configuration.behaviorNames) {
      if (configuration.isBehaviorHidden(behaviorName)) continue;
      final displayName = lang.containsKey(behaviorName)
          ? lang.getString(behaviorName)
          : _splitCamelCase(behaviorName);
      if (configuration.isBehaviorEnabled(behaviorName, mascot) &&
          !behaviorName.contains('/')) {
        setBehaviourItems.add(MenuItem(displayName, () {
          try {
            mascot.setBehavior(configuration.buildBehavior(behaviorName));
          } catch (_) {}
        }));
      }
      if (configuration.isBehaviorToggleable(behaviorName) &&
          !behaviorName.contains('/')) {
        final enabled = configuration.isBehaviorEnabled(behaviorName, mascot);
        allowedItems.add(MenuItem(displayName, () {
          final disabled =
              app.settings.disabledBehaviors[mascot.imageSet] ?? [];
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
        }, checked: enabled));
      }
    }
    if (setBehaviourItems.isNotEmpty) {
      items.add(const MenuItem.separator());
      items.addAll(setBehaviourItems);
    }
    if (allowedItems.isNotEmpty) {
      items.add(const MenuItem.separator());
      items.addAll(allowedItems);
    }
  }

  items.add(const MenuItem.separator());
  items.add(MenuItem(
      mascot.paused
          ? lang.getString('ResumeAnimations')
          : lang.getString('PauseAnimations'),
      () => mascot.paused = !mascot.paused));
  items.add(const MenuItem.separator());
  items.add(MenuItem(lang.getString('Dismiss'), () => mascot.dispose()));
  items.add(MenuItem(lang.getString('DismissOthers'),
      () => app.manager.remainOneImageSetExcept(mascot.imageSet, mascot)));
  items.add(MenuItem(lang.getString('DismissAllOthers'),
      () => app.manager.remainOneMascot(mascot)));
  items.add(MenuItem(lang.getString('DismissAll'), () => app.exit()));
  return MenuModel(items);
}

String _splitCamelCase(String name) {
  // Java: replaceAll("([a-z])(IE)?([A-Z])", "$1 $2 $3").replaceAll(" {2}", " ")
  final buffer = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final ch = name[i];
    if (i > 0 &&
        _isLower(name[i - 1]) &&
        _isUpper(ch) &&
        (i + 1 >= name.length || _isLower(name[i + 1]))) {
      buffer.write(' ');
    } else if (i > 0 && _isLower(name[i - 1]) && _isUpper(ch)) {
      buffer.write(' ');
    }
    buffer.write(ch);
  }
  return buffer.toString();
}

bool _isLower(String c) => c.toLowerCase() == c && c.toUpperCase() != c;
bool _isUpper(String c) => c.toUpperCase() == c && c.toLowerCase() != c;
