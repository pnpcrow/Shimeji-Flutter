/// Shimeji Flutter — a desktop mascot ported from Shimeji-Desktop (Java).
///
/// Like the Java original, every mascot owns a top-level per-pixel-alpha
/// window. The Flutter engine runs headless; each tick it pushes the current
/// pose bitmaps to native layered windows (`UpdateLayeredWindow`), giving
/// true transparency and click-through on every session type. Menus are
/// native Win32 popups; the tray menu carries the global commands.
library;

import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';

import 'src/app.dart';
import 'src/manager.dart';
import 'src/menu/context_menu_model.dart';
import 'src/native/app_window.dart' as app_window;
import 'src/native/mascot_windows.dart';
import 'src/ui/settings_screen.dart';

final ValueNotifier<bool> settingsOpen = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The engine is headless; the widget tree hosts the optional settings
  // screen inside the (normally hidden) host window.
  runApp(const ShimejiFlutterApp());
  unawaited(_runEngine());
}

class ShimejiFlutterApp extends StatelessWidget {
  const ShimejiFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      home: ValueListenableBuilder<bool>(
        valueListenable: settingsOpen,
        builder: (context, open, _) => open
            ? SettingsScreen(
                key: ValueKey('settings-${ShimejiApp.instance.effectiveLanguageTag}'),
                app: ShimejiApp.instance,
                onClose: () async {
                  settingsOpen.value = false;
                  await app_window.AppWindow.hideSettingsWindow();
                },
                onLanguageChanged: () => _rebuildTrayMenu(),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

int _tickCount = 0;

Future<void> _runEngine() async {
  final app = ShimejiApp.instance;

  app.onShowContextMenu = (mascot, physicalX, physicalY) async {
    if (app.uiModal) return;
    app.uiModal = true;
    mascot.animating = false;
    try {
      final entries = buildContextMenu(app, mascot);
      final selected = await MascotNativeWindows.showContextMenu(
        id: mascot.id,
        x: physicalX,
        y: physicalY,
        items: entries,
      );
      if (selected >= 0 && selected < mascot.contextMenuActions.length) {
        mascot.contextMenuActions[selected]();
      }
    } finally {
      mascot.animating = true;
      app.uiModal = false;
    }
  };
  app.onAppExit = () async {
    await MascotNativeWindows.destroyAll();
    exit(0);
  };
  app.onOpenSettings = () async {
    settingsOpen.value = true;
    await app_window.AppWindow.showSettingsWindow();
  };
  app_window.AppWindow.onSettingsClosed = () => settingsOpen.value = false;

  // Fast phase first so the tray icon appears immediately: even if the
  // screen ever ends up covered, the app stays controllable and can be
  // exited from the tray.
  await app.prepare();
  await _setupTray();

  // Slow phase: parse configurations, decode poses, spawn mascots.
  await app.loadConfigurationsAndSpawn();

  // Convenience: open the settings screen right after startup.
  if (Platform.environment['SHIMEJI_OPEN_SETTINGS'] == '1') {
    settingsOpen.value = true;
    await app_window.AppWindow.showSettingsWindow();
  }

  Timer.periodic(const Duration(milliseconds: Manager.tickInterval), (_) {
    _tick(app);
  });
}

void _tick(ShimejiApp app) {
  _tickCount++;
  try {
    if (app.manager.mascots.isNotEmpty && _tickCount % 200 == 0) {
      final c = app.environment.getCursor();
      // ignore: avoid_print
      print('DIAG tick=$_tickCount cursor=${c.x},${c.y} '
          'mascots=${app.manager.mascots.length} '
          'first=${app.manager.mascots.first.bounds}');
    }
    app.pollInput();
    app.manager.tick();
    unawaited(MascotNativeWindows.syncMascots([
      for (final mascot in app.manager.mascots)
        MascotSyncState(
          id: mascot.id,
          image: mascot.image,
          imageHash:
              mascot.image == null ? 0 : identityHashCode(mascot.image),
          flipped: mascot.image?.flipped ?? false,
          x: mascot.bounds.x,
          y: mascot.bounds.y,
          width: mascot.bounds.width,
          height: mascot.bounds.height,
          opacity: app.settings.opacity,
        ),
    ]));
  } catch (e) {
    // Never kill the ticker; surface failures in debug consoles.
    // ignore: avoid_print
    print('Engine tick error: $e');
  }
}

SystemTray? _systemTray;

Future<void> _setupTray() async {
  final tray = SystemTray();
  _systemTray = tray;
  try {
    await tray.initSystemTray(
      title: 'Shimeji Flutter',
      iconPath: _trayIconPath(),
    );
  } catch (e) {
    // The tray is the emergency control surface; make failures visible.
    // ignore: avoid_print
    print('Tray init failed (icon: ${_trayIconPath()}): $e');
    _systemTray = null;
    return;
  }
  // ignore: avoid_print
  print('Tray initialized');
  tray.registerSystemTrayEventHandler((eventName) {
    if (eventName == kSystemTrayEventClick ||
        eventName == kSystemTrayEventRightClick) {
      tray.popUpContextMenu();
    }
  });
  await _buildTrayMenu(tray);
}

Future<void> _rebuildTrayMenu() async {
  if (_systemTray != null) {
    await _buildTrayMenu(_systemTray!);
  }
}

/// Absolute path of the tray icon next to the executable.
String _trayIconPath() {
  final root = ShimejiApp.instance.appRoot;
  final separator =
      root.endsWith('/') || root.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator;
  return '$root$separator' 'icon.ico';
}

Future<void> _buildTrayMenu(SystemTray tray) async {
  final app = ShimejiApp.instance;
  final lang = app.languageBundle;
  final settings = app.settings;
  final menu = Menu();
  final firstSet = settings.activeImageSets.isNotEmpty
      ? settings.activeImageSets.first
      : null;
  final availableSets = await app.availableImageSets();
  await menu.buildFrom([
    MenuItemLabel(
      label: lang.getString('CallShimeji'),
      onClicked: (item) {
        if (firstSet != null) app.createMascot(firstSet);
      },
    ),
    MenuItemLabel(
      label: lang.getString('FollowCursor'),
      onClicked: (item) {
        if (firstSet == null) return;
        final configuration = app.configurationFor(firstSet);
        if (configuration != null) {
          app.manager.setBehaviorAllFor(configuration, 'ChaseMouse', firstSet);
        }
      },
    ),
    MenuItemLabel(
      label: lang.getString('ReduceToOne'),
      onClicked: (item) => app.manager.remainOne(),
    ),
    MenuItemLabel(
      label: lang.getString('RestoreWindows'),
      onClicked: (item) => app.environment.restoreWindows(),
    ),
    MenuSeparator(),
    SubMenu(
      label: lang.getString('ChooseShimeji'),
      children: [
        for (final set in availableSets)
          MenuItemCheckbox(
            label: set,
            checked: settings.activeImageSets.contains(set),
            onClicked: (item) {
              final next = <String>[...settings.activeImageSets];
              if (next.contains(set)) {
                next.remove(set);
              } else {
                next.add(set);
              }
              if (next.isEmpty) return;
              unawaited(app.switchImageSets(next..sort()).then((_) {
                MascotNativeWindows.clearCache();
                _rebuildTrayMenu();
              }));
            },
          ),
      ],
    ),
    MenuSeparator(),
    SubMenu(
      label: lang.getString('Language'),
      children: [
        MenuItemCheckbox(
          label: app.systemLanguageLabel,
          checked: app.effectiveLanguageTag.isEmpty ||
              settings.language.isEmpty,
          onClicked: (item) {
            app.setLanguage('');
            _rebuildTrayMenu();
          },
        ),
        for (final tag in app.availableLanguages())
          MenuItemCheckbox(
            label: app.languageDisplayName(tag),
            checked: app.effectiveLanguageTag == tag &&
                settings.language.isNotEmpty,
            onClicked: (item) {
              app.setLanguage(tag);
              _rebuildTrayMenu();
            },
          ),
      ],
    ),
    MenuSeparator(),
    MenuItemCheckbox(
      label: lang.getString('Breeding'),
      checked: settings.breeding,
      onClicked: (item) {
        settings.breeding = !settings.breeding;
        _rebuildTrayMenu();
      },
    ),
    MenuItemCheckbox(
      label: lang.getString('Transients'),
      checked: settings.transients,
      onClicked: (item) {
        settings.transients = !settings.transients;
        _rebuildTrayMenu();
      },
    ),
    MenuItemCheckbox(
      label: lang.getString('Transformation'),
      checked: settings.transformation,
      onClicked: (item) {
        settings.transformation = !settings.transformation;
        _rebuildTrayMenu();
      },
    ),
    MenuItemCheckbox(
      label: lang.getString('ThrowingWindows'),
      checked: settings.throwing,
      onClicked: (item) {
        settings.throwing = !settings.throwing;
        _rebuildTrayMenu();
      },
    ),
    MenuItemCheckbox(
      label: lang.getString('SoundEffects'),
      checked: settings.sounds,
      onClicked: (item) {
        settings.sounds = !settings.sounds;
        _rebuildTrayMenu();
      },
    ),
    MenuItemCheckbox(
      label: lang.getString('Multiscreen'),
      checked: settings.multiscreen,
      onClicked: (item) {
        settings.multiscreen = !settings.multiscreen;
        _rebuildTrayMenu();
      },
    ),
    MenuSeparator(),
    MenuItemLabel(
      label: app.manager.isPaused
          ? lang.getString('ResumeAnimations')
          : lang.getString('PauseAnimations'),
      onClicked: (item) {
        app.manager.togglePauseAll();
        _rebuildTrayMenu();
      },
    ),
    MenuItemLabel(
      label: lang.getString('DismissAll'),
      onClicked: (item) => app.exit(),
    ),
    MenuSeparator(),
    MenuItemLabel(
      label: lang.getString('Settings'),
      onClicked: (item) async {
        settingsOpen.value = true;
        await app_window.AppWindow.showSettingsWindow();
      },
    ),
    // Always-available escape hatch, independent of any on-screen mascot.
    MenuItemLabel(
      label: 'Exit',
      onClicked: (item) => app.exit(),
    ),
  ]);
  await tray.setContextMenu(menu);
}
