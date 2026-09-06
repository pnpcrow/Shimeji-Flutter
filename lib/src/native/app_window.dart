/// Host-window commands for the settings screen.
///
/// The Flutter engine runs in a hidden host window; showing the settings
/// screen also reveals and activates that window, and closing it hides it
/// again. The runner notifies Dart when the window was closed natively
/// (title bar X) through the [settingsClosed] callback.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppWindow {
  AppWindow._();

  static const MethodChannel _channel = MethodChannel('shimeji/mascots');

  /// Set by the UI layer: fired when the user closes the settings window
  /// through native chrome.
  static VoidCallback? onSettingsClosed;

  static bool _handlerInstalled = false;

  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'settingsClosed') {
        onSettingsClosed?.call();
      }
      return null;
    });
  }

  static Future<void> showSettingsWindow(
      {int width = 980, int height = 720}) async {
    _ensureHandler();
    try {
      await _channel.invokeMethod('showSettingsWindow', {
        'width': width,
        'height': height,
      });
    } on PlatformException {
      // Without the native hook (other platforms) there is no window to show.
    }
  }

  static Future<void> hideSettingsWindow() async {
    try {
      await _channel.invokeMethod('hideSettingsWindow');
    } on PlatformException {
      // Ignore.
    }
  }
}
