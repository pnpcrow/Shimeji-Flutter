/// Shimeji Flutter — a desktop mascot ported from Shimeji-Desktop (Java).
///
/// The Windows runner window becomes a transparent, frameless, always-on-top
/// overlay covering the entire virtual desktop; all mascots render on it and
/// mouse input passes through wherever no mascot or UI region sits.
///
/// The overlay background is pure magenta; the runner's layered-window color
/// key turns those pixels fully transparent and click-through.
library;

import 'dart:async';
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import 'package:win32/win32.dart';

import 'src/app.dart';
import 'src/manager.dart';
import 'src/overlay/overlay_controller.dart';
import 'src/ui/app_ui_state.dart';
import 'src/ui/overlay_painter.dart';
import 'src/ui/panels.dart';

/// The overlay key color: pure magenta, turned transparent by the runner.
const kOverlayKeyColor = Color(0xFFFF00FF);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await OverlayController.initialize();

  // Make the runner window a transparent overlay covering the virtual screen.
  // Transparency is achieved with a color-keyed layered window (see the
  // runner); no DWM accent effect is used, so the app also works over remote
  // desktop sessions.
  final vs = _virtualScreen();
  await OverlayController.setWindowBounds(vs[0], vs[1], vs[2], vs[3]);
  await OverlayController.setTopmost(true);

  runApp(const ShimejiFlutterApp());
}

/// [x, y, w, h] of the virtual screen in physical pixels.
List<int> _virtualScreen() {
  final x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  final y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  final w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  final h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  return [x, y, w <= 0 ? 1920 : w, h <= 0 ? 1080 : h];
}

class ShimejiFlutterApp extends StatelessWidget {
  const ShimejiFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      home: const OverlayView(),
    );
  }
}

/// Drives the engine and hosts the overlay widget tree.
class OverlayView extends StatefulWidget {
  const OverlayView({super.key});

  @override
  State<OverlayView> createState() => _OverlayViewState();
}

class _OverlayViewState extends State<OverlayView> {
  final ShimejiApp app = ShimejiApp.instance;
  final ValueNotifier<int> _tickNotifier = ValueNotifier<int>(0);
  Timer? _ticker;
  int _tickCount = 0;
  bool _booted = false;
  SystemTray? _systemTray;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    app.onShowContextMenu = (mascot, physicalX, physicalY) {
      final model = buildContextMenu(app, mascot);
      final dpr = View.of(context).devicePixelRatio;
      AppUiState.instance.openContextMenu(
        mascot,
        model,
        (physicalX - OverlayController.windowX) / dpr,
        (physicalY - OverlayController.windowY) / dpr,
      );
      _syncClickThrough();
    };
    app.onAppExit = () {
      exit(0);
    };

    await app.run();

    if (app.settings.showTrayIcon) {
      await _setupTray();
    }

    if (app.settings.alwaysShowShimejiChooser ||
        app.settings.activeImageSets.isEmpty) {
      AppUiState.instance.show(UiMode.chooser);
    } else if (app.settings.alwaysShowInformationScreen &&
        app.settings.activeImageSets.any((set) =>
            app.configurationFor(set)?.splashImagePath != null ||
            app.configurationFor(set)?.displayName != null)) {
      AppUiState.instance.show(UiMode.info);
    }

    _ticker = Timer.periodic(
        const Duration(milliseconds: Manager.tickInterval), (_) => _tick());
    _booted = true;
    if (mounted) setState(() {});
  }

  void _tick() {
    _tickCount++;
    try {
      // Refresh virtual screen bounds occasionally (display changes).
      if (_tickCount % 100 == 0) {
        final vs = _virtualScreen();
        if (vs[0] != OverlayController.windowX ||
            vs[1] != OverlayController.windowY ||
            vs[2] != OverlayController.windowWidth ||
            vs[3] != OverlayController.windowHeight) {
          OverlayController.setWindowBounds(vs[0], vs[1], vs[2], vs[3]);
        }
      }

      if (AppUiState.instance.mode == UiMode.none) {
        app.pollInput();
      }
      app.manager.tick();
      app.updateOverlayRects();
      _syncClickThrough();
      _tickNotifier.value++;
    } catch (e) {
      // Never kill the ticker; surface the failure in debug consoles.
      // ignore: avoid_print
      print('Engine tick error: $e');
    }
  }

  /// Keeps the runner's click-through mode in sync with the engine state.
  void _syncClickThrough() {
    final state = AppUiState.instance;
    if (state.mode != UiMode.none) {
      OverlayController.setClickThrough(false);
      return;
    }
    final dragging = app.manager.mascots.any((m) => m.dragging);
    if (dragging) {
      OverlayController.setClickThrough(false);
      return;
    }
    final cursor = app.environment.getCursor();
    final overMascot = app.manager.mascots.any((m) {
      final image = m.image;
      if (image == null) return false;
      final bounds = m.bounds;
      return cursor.x >= bounds.x &&
          cursor.x < bounds.x + bounds.width &&
          cursor.y >= bounds.y &&
          cursor.y < bounds.y + bounds.height &&
          image.hitTest(cursor.x - bounds.x, cursor.y - bounds.y);
    });
    OverlayController.setClickThrough(overMascot ? false : true);
  }

  Future<void> _setupTray() async {
    final tray = SystemTray();
    _systemTray = tray;
    try {
      await tray.initSystemTray(
        title: 'Shimeji Flutter',
        iconPath: '${app.appRoot}icon.ico',
      );
    } catch (_) {
      _systemTray = null;
      return;
    }
    tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventRightClick) {
        tray.popUpContextMenu();
      }
    });
    await _buildTrayMenu(tray);
  }

  Future<void> _buildTrayMenu(SystemTray tray) async {
    final lang = app.languageBundle;
    final settings = app.settings;
    final menu = Menu();
    final firstSet = settings.activeImageSets.isNotEmpty
        ? settings.activeImageSets.first
        : null;
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
      MenuItemLabel(
        label: lang.getString('ChooseShimeji'),
        onClicked: (item) => AppUiState.instance.show(UiMode.chooser),
      ),
      MenuItemLabel(
        label: lang.getString('Settings'),
        onClicked: (item) => AppUiState.instance.show(UiMode.settings),
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
    ]);
    await tray.setContextMenu(menu);
  }

  Future<void> _rebuildTrayMenu() async {
    if (_systemTray != null) {
      await _buildTrayMenu(_systemTray!);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = View.of(context).devicePixelRatio;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: kOverlayKeyColor,
        child: ValueListenableBuilder<int>(
        valueListenable: _tickNotifier,
        builder: (context, tick, _) {
          final state = AppUiState.instance;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Mascot layer.
              Positioned.fill(
                child: CustomPaint(
                  painter: MascotPainter(
                    _buildRenders(dpr),
                    drawBounds: _booted && app.settings.drawShimejiBounds,
                  ),
                ),
              ),
              // Click-away catcher while a context menu is open; placed below
              // the menu so menu items receive their taps.
              if (state.mode == UiMode.contextMenu)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      state.closeMenu();
                      _syncClickThrough();
                    },
                  ),
                ),
              if (state.mode == UiMode.contextMenu && state.menuModel != null)
                ContextMenuWidget(
                  model: state.menuModel!,
                  left: state.menuLeft,
                  top: state.menuTop,
                  onClose: () {
                    state.closeMenu();
                    _syncClickThrough();
                  },
                ),
              if (state.mode == UiMode.chooser) ImageSetChooser(app: app),
              if (state.mode == UiMode.settings) SettingsPanel(app: app),
              if (state.mode == UiMode.info) InfoPanel(app: app),
              if (state.mode == UiMode.stats) StatsPanel(app: app),
            ],
          );
        },
        ),
      ),
    );
  }

  List<MascotRender> _buildRenders(double dpr) {
    final opacity = _booted ? app.settings.opacity : 0.0;
    final renders = <MascotRender>[];
    for (final mascot in app.manager.mascots) {
      final image = mascot.image;
      if (image == null) continue;
      final bounds = mascot.bounds;
      renders.add(MascotRender(
        image,
        Rect.fromLTWH(
          (bounds.x - OverlayController.windowX) / dpr,
          (bounds.y - OverlayController.windowY) / dpr,
          bounds.width / dpr,
          bounds.height / dpr,
        ),
        opacity,
      ));
    }
    return renders;
  }
}
