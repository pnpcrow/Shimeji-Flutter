/// Port of `Settings.java` — reads/writes the `conf/settings.properties` file
/// with the same keys and defaults as the Java original.
library;

import 'dart:convert';
import 'dart:io';

import 'image/filter.dart';

class Settings {
  String shimejiEeNameOverride = '';
  List<String> activeImageSets = [];
  List<String> informationDismissed = [];

  String language = '';
  Map<String, List<String>> disabledBehaviors = {};
  bool breeding = true;
  bool transients = true;
  bool transformation = true;
  bool throwing = true;
  bool sounds = true;
  bool multiscreen = true;

  bool showTrayIcon = true;
  bool alwaysShowShimejiChooser = false;
  bool alwaysShowInformationScreen = false;
  bool drawShimejiBounds = false;
  Filter filter = Filter.nearestNeighbour;
  double opacity = 1.0;
  double scaling = 1.0;

  List<String> interactiveWindows = [];
  List<String> interactiveWindowsBlacklist = [];

  /// The screen presentation mode. 'legacy' renders each mascot in its own
  /// per-pixel-alpha native window (the original Java architecture).
  String renderingMode = 'legacy';

  // Window mode settings (the virtual "windowed" environment is not ported;
  // kept so settings files round-trip losslessly).
  bool windowedMode = false;
  int windowWidth = 600;
  int windowHeight = 500;
  int backgroundRed = 0x00;
  int backgroundGreen = 0xFF;
  int backgroundBlue = 0x00;
  String? backgroundImage;
  String backgroundMode = 'centre';

  final Map<String, String> _properties = {};

  void load(String path) {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      final text = file.readAsStringSync();
      for (final rawLine in const LineSplitter().convert(text)) {
        var line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
          continue;
        }
        var sep = line.indexOf('=');
        if (sep < 0) sep = line.indexOf(':');
        if (sep < 0) continue;
        _properties[line.substring(0, sep).trim()] =
            line.substring(sep + 1).trim();
      }
    } catch (_) {
      // Ignore unreadable settings files.
    }

    shimejiEeNameOverride = getProperty('ShimejiEENameOverride', '').trim();
    activeImageSets = getStringList('ActiveShimeji', '/');
    informationDismissed = getStringList('InformationDismissed', '/');

    language = getProperty('Language', '');
    disabledBehaviors.clear();
    for (final key in _properties.keys) {
      if (key.startsWith('DisabledBehaviours.') &&
          key.length > 'DisabledBehaviours.'.length) {
        final imageSet = key.substring(key.indexOf('.') + 1);
        final list = getStringList(key, '/');
        if (list.isNotEmpty) disabledBehaviors[imageSet] = list;
      }
    }
    breeding = getBool('Breeding', true);
    transients = getBool('Transients', true);
    transformation = getBool('Transformation', true);
    throwing = getBool('Throwing', true);
    sounds = getBool('Sounds', true);
    multiscreen = getBool('Multiscreen', true);

    showTrayIcon = getBool('ShowTrayIcon', true);
    alwaysShowShimejiChooser = getBool('AlwaysShowShimejiChooser', false);
    alwaysShowInformationScreen =
        getBool('AlwaysShowInformationScreen', false);
    drawShimejiBounds = getBool('DrawShimejiBounds', false);
    filter = Filter.fromSetting(getProperty('Filter', 'false'));
    opacity = getDouble('Opacity', 1.0);
    scaling = getDouble('Scaling', 1.0);

    interactiveWindows = getStringList('InteractiveWindows', '/');
    interactiveWindowsBlacklist =
        getStringList('InteractiveWindowsBlacklist', '/');
    final mode = getProperty('RenderingMode', 'legacy').trim().toLowerCase();
    renderingMode = mode == 'legacy' ? 'legacy' : 'legacy';

    windowedMode = getProperty('Environment', 'generic') == 'virtual';
    final windowSize = getProperty('WindowSize', '600x500').split('x');
    if (windowSize.length >= 2) {
      windowWidth = int.tryParse(windowSize[0]) ?? 600;
      windowHeight = int.tryParse(windowSize[1]) ?? 500;
    }
    final background = getInt('Background', 0x00FF00);
    backgroundRed = (background >> 16) & 0xFF;
    backgroundGreen = (background >> 8) & 0xFF;
    backgroundBlue = background & 0xFF;
    final bgImage = getProperty('BackgroundImage', '');
    backgroundImage = bgImage.isEmpty ? null : bgImage;
    backgroundMode = getProperty('BackgroundMode', 'centre');
  }

  String getProperty(String key, String fallback) =>
      _properties[key] ?? fallback;

  List<String> getStringList(String key, String separator) {
    final value = _properties[key];
    if (value == null) return [];
    return value
        .split(separator)
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }

  bool getBool(String key, bool fallback) {
    final value = _properties[key];
    if (value == null) return fallback;
    return value.toLowerCase() == 'true' || value == '1';
  }

  int getInt(String key, int fallback) =>
      int.tryParse(_properties[key] ?? '') ?? fallback;

  double getDouble(String key, double fallback) =>
      double.tryParse(_properties[key] ?? '') ?? fallback;

  void save(String path) {
    void set(String key, String value) => _properties[key] = value;

    set('ShimejiEENameOverride', shimejiEeNameOverride.trim());
    set('ActiveShimeji', activeImageSets.join('/'));
    set('InformationDismissed', informationDismissed.join('/'));
    set('Language', language);
    _properties.removeWhere((key, v) =>
        key.startsWith('DisabledBehaviours.') &&
        !disabledBehaviors.containsKey(key.substring(key.indexOf('.') + 1)));
    for (final entry in disabledBehaviors.entries) {
      set('DisabledBehaviours.${entry.key}', entry.value.join('/'));
    }
    set('Breeding', breeding.toString());
    set('Transients', transients.toString());
    set('Transformation', transformation.toString());
    set('Throwing', throwing.toString());
    set('Sounds', sounds.toString());
    set('Multiscreen', multiscreen.toString());
    set('ShowTrayIcon', showTrayIcon.toString());
    set('AlwaysShowShimejiChooser', alwaysShowShimejiChooser.toString());
    set('AlwaysShowInformationScreen', alwaysShowInformationScreen.toString());
    set('DrawShimejiBounds', drawShimejiBounds.toString());
    switch (filter) {
      case Filter.nearestNeighbour:
        set('Filter', 'nearest');
      case Filter.bicubic:
        set('Filter', 'bicubic');
      case Filter.hqx:
        set('Filter', 'hqx');
    }
    set('Opacity', opacity.toString());
    set('Scaling', scaling.toString());
    set('InteractiveWindows', interactiveWindows.join('/'));
    set('InteractiveWindowsBlacklist', interactiveWindowsBlacklist.join('/'));
    set('RenderingMode', renderingMode);
    set('Environment', windowedMode ? 'virtual' : 'generic');
    set('WindowSize', '$windowWidth x $windowHeight'.replaceAll(' ', ''));
    set('Background',
        '#${_hex2(backgroundRed)}${_hex2(backgroundGreen)}${_hex2(backgroundBlue)}');
    set('BackgroundMode', backgroundMode);
    set('BackgroundImage', backgroundImage ?? '');

    final buf = StringBuffer('#Shimeji-ee Configuration Options\n');
    final sorted = _properties.keys.toList()..sort();
    for (final key in sorted) {
      buf.writeln('$key=${_properties[key]}');
    }
    File(path).writeAsStringSync(buf.toString(), flush: true);
  }

  static String _hex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
}

/// Minimal Java-`.properties` resource bundle reader for the language files.
class LanguageBundle {
  final Map<String, String> _values;

  LanguageBundle._(this._values);

  static LanguageBundle load(String path) {
    final values = <String, String>{};
    try {
      final file = File(path);
      if (file.existsSync()) {
        final text = file.readAsStringSync();
        for (final rawLine in const LineSplitter().convert(text)) {
          var line = rawLine.trim();
          if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
            continue;
          }
          // Handle simple backslash continuations.
          while (line.endsWith('\\')) {
            line = line.substring(0, line.length - 1);
          }
          var sep = line.indexOf('=');
          if (sep < 0) sep = line.indexOf(':');
          if (sep < 0) continue;
          final key = line.substring(0, sep).trim();
          final value = _unescape(line.substring(sep + 1).trim());
          values[key] = value;
        }
      }
    } catch (_) {
      // Ignore unreadable language files.
    }
    return LanguageBundle._(values);
  }

  static String _unescape(String s) {
    return s.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (m) {
      return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
    }).replaceAll('\\=', '=').replaceAll('\\:', ':');
  }

  bool containsKey(String key) => _values.containsKey(key);

  String getString(String key) => _values[key] ?? key;
}
