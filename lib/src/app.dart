/// Port of `Main.java` — application bootstrap, configuration loading, mascot
/// spawning, input polling, and the shared application state.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' show GetAsyncKeyState, VK_LBUTTON, VK_RBUTTON;
import 'package:xml/xml.dart';

import 'action/globals.dart';
import 'behavior/behavior.dart';
import 'behavior/behavior_execution_exception.dart';
import 'config/configuration.dart';
import 'config/exceptions.dart';
import 'environment/environment.dart';
import 'environment/win32_environment.dart';
import 'image/hqx/hqx_scaler.dart';
import 'image/image_pairs.dart';
import 'manager.dart';
import 'mascot.dart';
import 'settings.dart';
import 'sound/sounds.dart';

export 'settings.dart' show LanguageBundle;

/// Central change notification for settings-driven UI surfaces (tray menu,
/// settings screen, context menus). Everything rebuilds when this fires,
/// so no surface can drift out of sync with another.
final class SettingsChangeNotifier extends ChangeNotifier {
  static final SettingsChangeNotifier instance = SettingsChangeNotifier();

  void notify() => notifyListeners();
}

class ShimejiApp {
  static final ShimejiApp instance = ShimejiApp._();

  ShimejiApp._();

  /// Broadcasts that settings changed. See [SettingsChangeNotifier].

  late Settings settings;
  late LanguageBundle languageBundle;
  final Map<String, Configuration> configurations = {};
  late final Manager manager = Manager();
  late final WindowsEnvironment environment = WindowsEnvironment();
  final math.Random _random = math.Random();

  String appRoot = '';
  String get confDirectory => '$appRoot/conf';
  String get imageDirectory => '$appRoot/img';
  String get soundDirectory => '$appRoot/sound';
  String get settingsFile => '$confDirectory/settings.properties';
  String get iconFile => '$appRoot/icon.png';

  /// The configuration for an image set (null if not loaded/failed).
  Configuration? configurationFor(String imageSet) =>
      configurations[imageSet];

  /// UI state hooks; assigned by the UI layer.
  void Function(Mascot mascot, int physicalX, int physicalY)? onShowContextMenu;
  VoidCallback? onRefreshUi;
  void Function()? onAppExit;

  /// Opens the settings screen (host window + UI), wired by the UI layer.
  void Function()? onOpenSettings;

  /// Opens the image set chooser UI, wired by the UI layer.
  void Function()? onOpenImageSetChooser;

  /// Broadcasts that settings changed. Called by EVERY surface that mutates
  /// settings (settings screen, tray menu, mascot context menu); listeners
  /// (tray rebuild, settings screen refresh) react in one place.
  void broadcastSettingsChanged() {
    SettingsChangeNotifier.instance.notify();
  }


  // -------------------------------------------------------------------------
  // Startup
  // -------------------------------------------------------------------------

  /// Fast startup phase: paths, settings, language, hooks and environment.
  /// The tray menu can be shown right after this returns.
  Future<void> prepare() async {
    _resolveAppRoot();
    await _extractAssets();

    settings = Settings();
    settings.load(settingsFile);
    Sounds.enabled = settings.sounds;

    languageBundle = _loadLanguageBundle();
    _wireHooks();

    environment.interactiveWindows = () => settings.interactiveWindows;
    environment.interactiveWindowsBlacklist = () =>
        settings.interactiveWindowsBlacklist;
    MascotEnvironment.multiscreenEnabled = () => settings.multiscreen;
    ShimejiEnvironmentHolder.instance = environment;

    environment.init();
  }

  /// Slow startup phase: parse configurations, decode poses and spawn the
  /// initial mascots.
  Future<void> loadConfigurationsAndSpawn() async {
    // Load active image set configurations.
    await _configurationLoadLoop();

    manager.onExitOnLastRemoved = exit;

    // Spawn one mascot per active image set (Java Main.run).
    for (final imageSet in settings.activeImageSets) {
      final configuration = configurations[imageSet];
      if (configuration == null) continue;
      _spawnMascot(imageSet, configuration);
    }
    onRefreshUi?.call();
  }

  void _spawnMascot(String imageSet, Configuration configuration) {
    final mascot = createMascotObject(imageSet);
    mascot.anchor.setLocation(-4000, -4000);
    mascot.lookRight = _random.nextBool();
    try {
      final behavior = configuration.buildNextBehavior(null, mascot);
      mascot.setBehavior(behavior);
      manager.add(mascot);
    } on BehaviorInstantiationException catch (e) {
      _showError('Failed to create a mascot for "$imageSet"', e);
      mascot.dispose();
    }
  }

  void _resolveAppRoot() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final probe = Directory('$exeDir/.write_probe');
      probe.createSync(recursive: true);
      probe.deleteSync();
      appRoot = exeDir;
    } catch (_) {
      final appData =
          Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      appRoot = '$appData/shimeji_flutter';
      Directory(appRoot).createSync(recursive: true);
    }
  }

  /// Extracts bundled conf/ and img/ assets so users can edit them like the
  /// Java distribution.
  Future<void> _extractAssets() async {
    Directory(confDirectory).createSync(recursive: true);
    Directory(imageDirectory).createSync(recursive: true);
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final asset in manifest.listAssets()) {
        if (!asset.startsWith('assets/conf/') &&
            !asset.startsWith('assets/img/') &&
            asset != 'assets/icon.png' &&
            asset != 'assets/icon.ico') {
          continue;
        }
        final relative = asset.substring('assets/'.length);
        final target = File('$appRoot/$relative');
        if (target.existsSync()) continue;
        target.parent.createSync(recursive: true);
        final data = await rootBundle.load(asset);
        await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    } catch (e) {
      // Asset extraction is best-effort; bundled defaults may already exist.
    }
    // Extract the tray icon if it was not bundled into the manifest above.
    final icon = File(iconFile);
    if (!icon.existsSync()) {
      try {
        final data = await rootBundle.load('assets/icon.png');
        await icon.writeAsBytes(data.buffer.asUint8List(), flush: true);
      } catch (_) {}
    }
  }

  /// Languages with a translation in conf/ (BCP-47-ish tags).
  List<String> availableLanguages() {
    final tags = <String>[];
    final dir = Directory(confDirectory);
    if (!dir.existsSync()) return tags;
    final pattern = RegExp('^language_([a-zA-Z_-]+)[.]properties\$');
    for (final file in dir.listSync()) {
      if (file is! File) continue;
      final match = pattern.firstMatch(file.path.split(Platform.pathSeparator).last);
      if (match != null) {
        tags.add(match.group(1)!.replaceAll('_', '-'));
      }
    }
    tags.sort();
    return tags;
  }

  /// Switches the UI language at runtime (tray Language submenu, settings
  /// screen). An empty tag means "follow the system language". This is the
  /// single source of truth: both menus rebuild from
  /// [currentLanguageTag]/[effectiveLanguageTag].
  void setLanguage(String tag) {
    // Store the normalized supported tag ('ko-KR' -> 'ko') so checkmark
    // comparisons against availableLanguages() always match.
    settings.language = tag.isEmpty ? '' : (_availableTagFor(tag) ?? tag);
    if (tag.isEmpty) {
      final osTag = _availableTagFor(_osLanguageTag());
      _effectiveSystemTag = osTag;
      languageBundle = _bundleForTag(osTag ?? '', fallback: languageBundle);
    } else {
      _effectiveSystemTag = null;
      languageBundle = _bundleForTag(tag, fallback: languageBundle);
    }
    onRefreshUi?.call();
    broadcastSettingsChanged();
  }

  LanguageBundle _bundleForTag(String tag, {LanguageBundle? fallback}) {
    if (tag.isNotEmpty) {
      final localized = LanguageBundle.load(
          '$confDirectory/language_${tag.replaceAll('-', '_')}.properties');
      if (localized.containsKey('CallAnother')) return localized;
      final base = LanguageBundle.load(
          '$confDirectory/language_${tag.split('-').first}.properties');
      if (base.containsKey('CallAnother')) return base;
    }
    final defaultBundle = LanguageBundle.load('$confDirectory/language.properties');
    if (defaultBundle.containsKey('CallAnother')) return defaultBundle;
    return fallback ?? defaultBundle;
  }

  LanguageBundle _loadLanguageBundle() {
    // Java loads a ResourceBundle for the current locale; fall back to the
    // base English bundle.
    if (settings.language.isEmpty) {
      final osTag = _availableTagFor(_osLanguageTag());
      _effectiveSystemTag = osTag;
      return _bundleForTag(osTag ?? '', fallback: null) ??
          LanguageBundle.load('$confDirectory/language.properties');
    }
    _effectiveSystemTag = null;
    return _bundleForTag(settings.language);
  }

  void _wireHooks() {
    EngineHooks.instance.scaling = () => settings.scaling;
    EngineHooks.instance.breeding = () => settings.breeding;
    EngineHooks.instance.transients = () => settings.transients;
    EngineHooks.instance.transformation = () => settings.transformation;
    EngineHooks.instance.throwing = () => settings.throwing;
    EngineHooks.instance.multiscreen = () => settings.multiscreen;
    EngineHooks.instance.configuration = configurationFor;
    EngineHooks.instance.createMascot = createMascotObject;
    EngineHooks.instance.disabledBehaviorsFor =
        (imageSet) => settings.disabledBehaviors[imageSet];
    EngineHooks.instance.showError = _showError;
    EngineHooks.instance.manager = () => manager;
    ConfigurationForHook = configurationFor;
    ShowErrorHook = _showError;
    resolveAppPath = (path) {
      if (path.startsWith('/')) return '$appRoot$path';
      return '$appRoot/$path';
    };
    ImagePairs.hqxScaler = applyHqx;
    ImagePairs.resolveImagePath = (path) {
      if (path.startsWith('/')) return '$imageDirectory$path';
      return '$imageDirectory/$path';
    };
  }

  // -------------------------------------------------------------------------
  // Configuration loading
  // -------------------------------------------------------------------------

  static const List<String> _actionsNames = [
    'actions.xml', '動作.xml', 'one.xml', '1.xml',
  ];
  static const List<String> _behaviorsNames = [
    'behaviors.xml', 'behavior.xml', '行動.xml', 'two.xml', '2.xml',
  ];

  /// Searches img/<set>/conf/, conf/<set>/ and conf/ like the Java original.
  List<String> _configCandidates(String imageSet, List<String> filenames) {
    return [
      for (final dir in ['img/$imageSet/conf', 'conf/$imageSet', 'conf'])
        for (final name in filenames) '$dir/$name',
    ];
  }

  String? _findConfigFile(String imageSet, List<String> filenames) {
    for (final candidate in _configCandidates(imageSet, filenames)) {
      final file = File(resolveAppPath(candidate));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  Future<Configuration?> loadConfiguration(String imageSet,
      {Set<String>? loading}) async {
    if (configurations.containsKey(imageSet)) return configurations[imageSet];
    loading ??= <String>{};
    if (!loading.add(imageSet)) return null;

    final actionsPath = _findConfigFile(imageSet, _actionsNames);
    final behaviorsPath = _findConfigFile(imageSet, _behaviorsNames);
    if (actionsPath == null) {
      return null;
    }

    final configuration = Configuration();
    configuration.settings = settings;
    try {
      final actionsXml =
          XmlDocument.parse(await File(actionsPath).readAsString());
      configuration.load(actionsXml.rootElement, imageSet);
      if (behaviorsPath != null) {
        final behaviorsXml =
            XmlDocument.parse(await File(behaviorsPath).readAsString());
        configuration.load(behaviorsXml.rootElement, imageSet);
      }
    } catch (e) {
      _showError('Failed to load the configuration for "$imageSet"', e);
      return null;
    }

    // Load referenced child image sets (BornMascot / TransformMascot).
    final referenced = <String>{};
    for (final actionBuilder in configuration.actionBuilders.values) {
      for (final key in const ['BornMascot', 'TransformMascot']) {
        final value = actionBuilder.params[key];
        if (value != null && value.isNotEmpty && !value.contains('{')) {
          referenced.add(value);
        }
      }
    }
    for (final child in referenced) {
      if (child != imageSet) {
        await loadConfiguration(child, loading: loading);
      }
    }

    try {
      await configuration.loadPoseImages();
      configuration.validate();
    } catch (e) {
      _showError('Failed to load the configuration for "$imageSet"', e);
      return null;
    }

    configurations[imageSet] = configuration;
    return configuration;
  }

  Future<void> _configurationLoadLoop() async {
    if (!settings.alwaysShowShimejiChooser && settings.activeImageSets.isEmpty) {
      // First launch: auto-select every image set with a valid config.
      settings.activeImageSets.addAll(await availableImageSets());
    }
    final valid = <String>[];
    for (final imageSet in settings.activeImageSets) {
      final configuration = await loadConfiguration(imageSet);
      if (configuration != null) valid.add(imageSet);
    }
    settings.activeImageSets
      ..clear()
      ..addAll(valid);
    _saveSettings();
  }

  /// Image set directories under img/ that contain at least one PNG frame.
  Future<List<String>> availableImageSets() async {
    final result = <String>[];
    final dir = Directory(imageDirectory);
    if (!dir.existsSync()) return result;
    for (final entry in dir.listSync()) {
      if (entry is Directory) {
        final name = entry.path.split(Platform.pathSeparator).last;
        if (name == 'unused') continue;
        if (configurations.containsKey(name)) {
          result.add(name);
          continue;
        }
        final hasPng = entry
            .listSync()
            .whereType<File>()
            .any((f) => f.path.toLowerCase().endsWith('.png'));
        if (hasPng) result.add(name);
      }
    }
    result.sort();
    return result;
  }

  void saveSettings() {
    try {
      settings.save(settingsFile);
    } catch (_) {}
    broadcastSettingsChanged();
  }

  void _saveSettings() => saveSettings();

  // -------------------------------------------------------------------------
  // Mascots
  // -------------------------------------------------------------------------

  /// Human-readable name for a language tag. The stock bundles keep the
  /// native name only in a commented `#LanguageName=` hint, so that is read
  /// too; the tag itself is the last resort.
  String languageDisplayName(String tag) {
    final fileName = '$confDirectory/language_${tag.replaceAll('-', '_')}.properties';
    final native = peekCommentedValue(fileName, 'LanguageName');
    if (native != null && native.trim().isNotEmpty) return native.trim();
    final bundle = LanguageBundle.load(fileName);
    final value = bundle.getString('LanguageName');
    if (value != 'LanguageName') return value;
    return tag;
  }

  /// The language tag currently in effect ('' while following the system).
  String get currentLanguageTag => settings.language;

  /// The tag whose bundle is actually loaded right now ('' if none matched).
  String get effectiveLanguageTag {
    if (settings.language.isEmpty) return _effectiveSystemTag ?? '';
    return settings.language;
  }

  String? _effectiveSystemTag;

  /// Label of the "system language" entry in the language menus, e.g.
  /// "System language (한국어)" when the OS locale is ko.
  String get systemLanguageLabel {
    final tag = _osLanguageTag();
    final name = _availableTagFor(tag);
    if (name != null) {
      return 'System language (${languageDisplayName(name)})';
    }
    return 'System language (${tag.isEmpty ? 'default' : tag})';
  }

  /// Best matching supported tag for the OS locale, or null.
  String? _availableTagFor(String tag) {
    if (tag.isEmpty) return null;
    final available = availableLanguages();
    final normalized = tag.replaceAll('_', '-');
    for (final candidate in available) {
      if (candidate.toLowerCase() == normalized.toLowerCase()) {
        return candidate;
      }
    }
    final base = normalized.split('-').first.toLowerCase();
    for (final candidate in available) {
      if (candidate.split('-').first.toLowerCase() == base) {
        return candidate;
      }
    }
    return null;
  }

  String _osLanguageTag() {
    // Windows locale names look like ko-KR or Korean_Korea; keep the
    // language subtag (and region if present).
    final locale = Platform.localeName.replaceAll('_', '-');
    final parts = locale.split('.');
    final cleaned = (parts.isNotEmpty ? parts.first : locale).trim();
    final segments = cleaned.split('-');
    if (segments.length >= 2) {
      return '${segments[0]}-${segments[1]}';
    }
    return cleaned;
  }

  /// Spawns one more mascot of the given image set (menu "Call Another").
  void createMascot(String imageSet) {
    final configuration = configurationFor(imageSet);
    if (configuration == null) return;
    _spawnMascot(imageSet, configuration);
  }

  /// Creates a mascot with the popup wiring attached. All mascot creation
  /// must go through this factory: mascots built elsewhere (breeding,
  /// transformation) would otherwise lack context-menu support.
  Mascot createMascotObject(String imageSet) {
    final mascot = Mascot(imageSet);
    mascot.onShowPopup = (x, y) {
      final bounds = mascot.bounds;
      onShowContextMenu?.call(mascot, bounds.x + x, bounds.y + y);
    };
    return mascot;
  }

  /// Menu "Choose Shimeji": switches to the given list of image sets.
  Future<void> switchImageSets(List<String> imageSets) async {
    manager.disposeAll();
    configurations.clear();
    settings.activeImageSets
      ..clear()
      ..addAll(imageSets);
    for (final imageSet in imageSets) {
      await loadConfiguration(imageSet);
    }
    _saveSettings();
    for (final imageSet in settings.activeImageSets) {
      final configuration = configurations[imageSet];
      if (configuration == null) continue;
      _spawnMascot(imageSet, configuration);
    }
    onRefreshUi?.call();
  }

  void _showError(String message, [Object? error]) {
    // The Java original shows a Swing error dialog; log to the console and
    // keep the app alive.
    // ignore: avoid_print
    print('Shimeji error: $message${error == null ? '' : ' ($error)'}');
  }

  // -------------------------------------------------------------------------
  // Exit
  // -------------------------------------------------------------------------

  void exit() {
    _saveSettings();
    manager.stop();
    Sounds.dispose();
    onAppExit?.call();
  }

  // -------------------------------------------------------------------------
  // Input (polled; mirrors the Java mouse event flow)
  // -------------------------------------------------------------------------

  bool _lastLeftDown = false;
  bool _lastRightDown = false;
  Mascot? _dragMascot;

  /// True while a native context menu is open; input polling is suspended.
  bool uiModal = false;

  /// Runs once per engine tick before the mascots tick.
  void pollInput() {
    if (uiModal) return;
    final cursor = environment.getCursor();
    final leftDown =
        (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0; // VK_LBUTTON
    final rightDown =
        (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0; // VK_RBUTTON

    final mascotAtCursor = _mascotAt(cursor.x, cursor.y);

    if (leftDown && !_lastLeftDown) {
      // Left press: hotspot handling happens inside the behavior.
      if (mascotAtCursor != null) {
        final bounds = mascotAtCursor.bounds;
        _dragMascot = mascotAtCursor;
        try {
          mascotAtCursor.mousePressed(false, cursor.x - bounds.x,
              cursor.y - bounds.y);
        } on BehaviorExecutionException {
          // Mascot disposed inside the handler.
        }
      }
    } else if (!leftDown && _lastLeftDown) {
      final mascot = _dragMascot;
      if (mascot != null) {
        _dragMascot = null;
        try {
          final bounds = mascot.bounds;
          mascot.mouseReleased(false, cursor.x - bounds.x, cursor.y - bounds.y);
        } on BehaviorExecutionException {
          // Disposed.
        }
      }
    }

    // The context menu opens on right-button RELEASE: opening it during the
    // press makes the same button's release dismiss the menu instantly.
    if (!rightDown && _lastRightDown) {
      if (mascotAtCursor != null && _dragMascot == null) {
        final bounds = mascotAtCursor.bounds;
        mascotAtCursor.mousePressed(
            true, cursor.x - bounds.x, cursor.y - bounds.y);
      }
    }

    _lastLeftDown = leftDown;
    _lastRightDown = rightDown;
  }

  Mascot? _mascotAt(int physicalX, int physicalY) {
    final mascots = manager.mascots;
    for (var i = mascots.length - 1; i >= 0; i--) {
      final mascot = mascots.elementAt(i);
      if (mascot.image == null) continue;
      final bounds = mascot.bounds;
      if (physicalX >= bounds.x &&
          physicalX < bounds.x + bounds.width &&
          physicalY >= bounds.y &&
          physicalY < bounds.y + bounds.height) {
        final localX = physicalX - bounds.x;
        final localY = physicalY - bounds.y;
        if (mascot.image!.hitTest(localX, localY)) {
          return mascot;
        }
      }
    }
    return null;
  }
}

