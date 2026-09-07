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
import 'src/flutter_renderer/context_menu_window_app.dart'
    show runContextMenuWindowApp;
import 'src/flutter_renderer/mascot_window_app.dart' show runMascotWindowApp;
import 'src/manager.dart';
import 'src/menu/context_menu_model.dart';
import 'src/native/app_window.dart' as app_window;
import 'src/native/flutter_mascot_windows.dart';
import 'src/native/mascot_windows.dart';
import 'src/ui/settings_screen.dart';

final ValueNotifier<bool> settingsOpen = ValueNotifier<bool>(false);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Secondary engines run the same entry point with a leading mode argument:
  // per-mascot render windows and the Flutter context-menu window of the
  // "flutter" renderer mode. Each hosts its own Flutter engine.
  if (args.isNotEmpty) {
    if (args.first == 'mascot_window') {
      return runMascotWindowApp(args.length > 1 ? args[1] : '');
    }
    if (args.first == 'context_menu') {
      return runContextMenuWindowApp();
    }
  }

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
                // Rebuilt on language switches so labels follow the bundle.
                key: ValueKey('settings-${ShimejiApp.instance.effectiveLanguageTag}'),
                app: ShimejiApp.instance,
                onClose: () async {
                  settingsOpen.value = false;
                  await app_window.AppWindow.hideSettingsWindow();
                },
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
      // The renderer mode picks the presentation: the legacy native Win32
      // popup, or the Flutter-rendered menu window.
      final selectedId = app.settings.renderingMode == 'flutter'
          ? await FlutterMascotWindows.showContextMenu(
              id: mascot.id,
              x: physicalX,
              y: physicalY,
              items: entries,
            )
          : await MascotNativeWindows.showContextMenu(
              id: mascot.id,
              x: physicalX,
              y: physicalY,
              items: entries,
            );
      final action = mascot.contextMenuActionFor(selectedId);
      if (action != null) {
        action();
      }
    } finally {
      mascot.animating = true;
      app.uiModal = false;
    }
  };
  app.onAppExit = () async {
    await FlutterMascotWindows.destroyAll();
    await MascotNativeWindows.destroyAll();
    exit(0);
  };
  app.onOpenSettings = () async {
    settingsOpen.value = true;
    await app_window.AppWindow.showSettingsWindow();
  };
  app.onOpenImageSetChooser = () {
    settingsOpen.value = true;
  };
  app_window.AppWindow.onSettingsClosed = () => settingsOpen.value = false;

  // Fast phase first so the tray icon appears immediately: even if the
  // screen ever ends up covered, the app stays controllable and can be
  // exited from the tray.
  await app.prepare();
  await _setupTray();

  // Slow phase: parse configurations, decode poses, spawn mascots.
  await app.loadConfigurationsAndSpawn();

  // The Flutter context-menu window hosts its own engine; boot it now so
  // the first right-click opens without engine start-up latency.
  if (app.settings.renderingMode == 'flutter') {
    unawaited(FlutterMascotWindows.prewarmContextMenu());
  }

  // Any settings change anywhere (settings screen, mascot context menu)
  // broadcasts through the notifier; the tray menu rebuilds itself here so
  // labels and checkmarks can never drift out of sync.
  SettingsChangeNotifier.instance.addListener(_onSettingsBroadcast);

  // Convenience: open the settings screen right after startup.
  if (Platform.environment['SHIMEJI_OPEN_SETTINGS'] == '1') {
    settingsOpen.value = true;
    await app_window.AppWindow.showSettingsWindow();
  }

  // Diagnostic: pop a mascot context menu at a fixed position so the
  // selection round-trip (Dart -> native popup -> id -> action) can be
  // exercised without relying on input polling.
  if (Platform.environment['SHIMEJI_TEST_MENU'] == '1') {
    Future.delayed(const Duration(seconds: 3), () {
      // The check runs inside the callback: at this point in start-up the
      // freshly spawned mascots are still pending in the manager (moved to
      // the live list by the first tick), so checking earlier finds none.
      final mascot =
          app.manager.mascots.isNotEmpty ? app.manager.mascots.first : null;
      if (mascot != null) {
        // ignore: avoid_print
        print('TESTMENU opening at 400,400');
        app.onShowContextMenu!(mascot, 400, 400);
      }
    });
  }

  Timer.periodic(const Duration(milliseconds: Manager.tickInterval), (_) {
    _tick(app);
  });
}

void _onSettingsBroadcast() {
  // ignore: avoid_print
  print('BROADCAST received -> rebuilding tray menu');
  _rebuildTrayMenu();
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
    // While the rendering mode is switching, no presentation at all: the
    // teardown and respawn must not race window/engine creation.
    if (app.presenterSuspended) return;
    final states = [
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
    ];
    // Both presenters share the same sync signature; the renderer mode
    // picks which per-mascot windows actually present the mascots.
    final sync = app.settings.renderingMode == 'flutter'
        ? FlutterMascotWindows.syncMascots
        : MascotNativeWindows.syncMascots;
    unawaited(sync(states));
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
  await _rebuildTrayMenu();
}

/// The system_tray plugin keeps mutable per-Menu state (menu id, item id
/// counter, item list) and silently drops click callbacks while a menu
/// build is in flight. Overlapping rebuilds therefore corrupt the menu
/// (a language change fires several broadcasts at once) and the tray stops
/// responding until restart. Rebuilds are coalesced and strictly
/// serialized, and each build runs on a fresh Menu instance so its ids and
/// item list can never be clobbered by another build.
bool _trayRebuildQueued = false;
Future<void>? _trayRebuildLoop;

Future<void> _rebuildTrayMenu() {
  if (_systemTray == null) {
    // ignore: avoid_print
    print('TRAY rebuild skipped: tray is null');
    return Future.value();
  }
  _trayRebuildQueued = true;
  return _trayRebuildLoop ??= _processTrayRebuilds();
}

Future<void> _processTrayRebuilds() async {
  try {
    while (_trayRebuildQueued) {
      _trayRebuildQueued = false;
      try {
        await _buildTrayMenu(_systemTray!);
      } catch (e) {
        // Never let one failed build kill the loop; the next request
        // retries with fresh state.
        // ignore: avoid_print
        print('TRAY rebuild failed: $e');
      }
    }
  } finally {
    _trayRebuildLoop = null;
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
  // A fresh Menu per build: the plugin assigns each build its own menu id
  // and item id counter, so concurrent state can never collide.
  final menu = Menu();
  final firstSet = settings.activeImageSets.isNotEmpty
      ? settings.activeImageSets.first
      : null;
  final availableSets = await app.availableImageSets();

  // Persists the change and broadcasts it: the notifier rebuilds this tray
  // menu and refreshes the settings screen, so no surface can drift.
  void applySetting(void Function() mutate) {
    mutate();
    app.saveSettings();
  }

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
              unawaited(app.switchImageSets(next..sort()));
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
            applySetting(() => app.setLanguage(''));
          },
        ),
        for (final tag in app.availableLanguages())
          MenuItemCheckbox(
            label: app.languageDisplayName(tag),
            checked: app.effectiveLanguageTag == tag &&
                settings.language.isNotEmpty,
            onClicked: (item) {
              applySetting(() => app.setLanguage(tag));
            },
          ),
      ],
    ),
    MenuSeparator(),
    MenuItemCheckbox(
      label: lang.getString('Breeding'),
      checked: settings.breeding,
      onClicked: (item) =>
          applySetting(() => settings.breeding = !settings.breeding),
    ),
    MenuItemCheckbox(
      label: lang.getString('Transients'),
      checked: settings.transients,
      onClicked: (item) =>
          applySetting(() => settings.transients = !settings.transients),
    ),
    MenuItemCheckbox(
      label: lang.getString('Transformation'),
      checked: settings.transformation,
      onClicked: (item) =>
          applySetting(() => settings.transformation = !settings.transformation),
    ),
    MenuItemCheckbox(
      label: lang.getString('ThrowingWindows'),
      checked: settings.throwing,
      onClicked: (item) =>
          applySetting(() => settings.throwing = !settings.throwing),
    ),
    MenuItemCheckbox(
      label: lang.getString('SoundEffects'),
      checked: settings.sounds,
      onClicked: (item) =>
          applySetting(() => settings.sounds = !settings.sounds),
    ),
    MenuItemCheckbox(
      label: lang.getString('Multiscreen'),
      checked: settings.multiscreen,
      onClicked: (item) =>
          applySetting(() => settings.multiscreen = !settings.multiscreen),
    ),
    MenuSeparator(),
    MenuItemLabel(
      label: app.manager.isPaused
          ? lang.getString('ResumeAnimations')
          : lang.getString('PauseAnimations'),
      onClicked: (item) {
        app.manager.togglePauseAll();
        // Pause state is per-mascot runtime state; broadcast only refreshes
        // the tray label and the settings screen listeners.
        app.broadcastSettingsChanged();
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
    MenuSeparator(),
    MenuItemLabel(
      label: lang.getString('Exit'),
      onClicked: (item) => app.exit(),
    ),
  ]);
  await tray.setContextMenu(menu);
}
