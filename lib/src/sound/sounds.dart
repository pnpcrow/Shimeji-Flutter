/// Port of `sound/Sounds.java` using the `audioplayers` package.
///
/// Clips are keyed by `fileName:volume` like the Java original. The `Volume`
/// pose attribute is expressed in decibels (0 dB = full volume), matching the
/// Java MASTER_GAIN semantics.
library;

import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

class Sounds {
  static final Map<String, ClipEntry> _clips = {};
  static final Map<String, List<String>> _usage = {};

  /// Mirrors settings.sounds; set at startup.
  static bool enabled = true;

  Sounds._();

  static Future<String> load(String path, double volume) async {
    final key = '$path:$volume';
    if (_clips.containsKey(key)) return key;
    final entry = ClipEntry(path: path, volumeDb: volume);
    _clips[key] = entry;
    return key;
  }

  static void addUsage(String soundKey, String imageSet) {
    _usage.putIfAbsent(imageSet, () => []);
    if (!_usage[imageSet]!.contains(soundKey)) {
      _usage[imageSet]!.add(soundKey);
    }
  }

  static void removeAll(String imageSet) {
    final keys = _usage.remove(imageSet);
    if (keys == null) return;
    for (final key in keys) {
      _clips.remove(key)?.dispose();
    }
  }

  static void clear() {
    for (final clip in _clips.values) {
      clip.dispose();
    }
    _clips.clear();
    _usage.clear();
  }

  static bool contains(String? key) => key != null && _clips.containsKey(key);

  /// Called from Mascot.apply: restarts the clip if it is not running.
  static void play(String? key) {
    if (!enabled || key == null) return;
    final clip = _clips[key];
    if (clip == null) return;
    clip.start();
  }

  static List<ClipEntry> getAllByFile(String path) {
    return _clips.values.where((c) => c.path == path).toList();
  }

  /// Matches clips whose path ends with the given (relative) sound name.
  static List<ClipEntry> getAllByFileSuffix(String soundName) {
    final normalized = soundName.replaceAll('\\', '/');
    return _clips.values
        .where((c) => c.path.replaceAll('\\', '/').endsWith(normalized))
        .toList();
  }

  static void stopAll() {
    for (final clip in _clips.values) {
      clip.stop();
    }
  }

  static void dispose() => clear();
}

class ClipEntry {
  final String path;
  final double volumeDb;
  AudioPlayer? _player;
  bool _running = false;

  ClipEntry({required this.path, required this.volumeDb});

  double get linearVolume {
    // MASTER_GAIN 0 dB == full volume; audioplayers wants 0..1 linear.
    final v = math.pow(10, volumeDb / 20).toDouble();
    return v.clamp(0.0, 1.0);
  }

  void start() {
    if (_running) return;
    final player = _player ??= AudioPlayer();
    player.setVolume(linearVolume);
    player
      ..stop()
      ..play(DeviceFileSource(path));
    _running = true;
    player.onPlayerComplete.listen((_) {
      _running = false;
    });
  }

  void stop() {
    _running = false;
    _player?.stop();
  }

  bool get isRunning => _running;

  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}
