/// Port of `platform/win/WindowsEnvironment.java` using the `win32` package
/// (Dart FFI) instead of JNA.
///
/// The active window is detected by enumerating top-level windows in z-order
/// and picking the first one that is visible, not DWM-cloaked, not maximized,
/// not minimized, and whose title passes the whitelist/blacklist rules.
///
/// All coordinates are physical screen pixels.
library;

import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'area.dart';
import 'environment.dart';

class WindowsEnvironment extends AbstractEnvironment {
  static WindowsEnvironment? _instance;

  final Map<int, bool> _interactiveCache = {};
  final Area _activeWindow = Area();
  String _activeWindowTitle = '';
  int _activeWindowHandle = 0;
  List<String> _windowTitles = const [];
  List<String> _windowTitlesBlacklist = const [];

  /// Callbacks into the app: whitelist/blacklist of interactive window titles.
  List<String> Function() interactiveWindows = () => const [];
  List<String> Function() interactiveWindowsBlacklist = () => const [];

  WindowsEnvironment() {
    _instance = this;
  }

  @override
  void tick() {
    // Refresh the cursor first: input polling and the engine read it this
    // tick (the Java original updated it inside AbstractEnvironment.tick).
    pollCursor();
    super.tick();
    final prevWindowId = getActiveWindowId();
    _windowTitles = interactiveWindows();
    _windowTitlesBlacklist = interactiveWindowsBlacklist();
    final windowRect = _getWindowRect(_findActiveWindow());
    if (windowRect == null) {
      _activeWindow.setRect(-1, -1, 0, 0);
    } else {
      _activeWindow.setFromRect(windowRect);
    }
    _activeWindow.visible = _activeWindow.intersectsRect(_screenUnionRect());
    if (prevWindowId != getActiveWindowId()) {
      _activeWindow.resetDeltas();
    }
    _activeWindowTitle = _activeWindowHandle == 0
        ? ''
        : _getWindowTitle(_activeWindowHandle);
  }

  bool _isInteractive(int hWnd) {
    final cachedValue = _interactiveCache[hWnd];
    if (cachedValue != null) return cachedValue;

    final windowTitle = _getWindowTitle(hWnd);
    if (windowTitle.isEmpty) {
      _interactiveCache[hWnd] = false;
      return false;
    }

    var blacklistInUse = false;
    for (final title in _windowTitlesBlacklist) {
      if (title.trim().isNotEmpty) {
        blacklistInUse = true;
        if (windowTitle.contains(title)) {
          _interactiveCache[hWnd] = false;
          return false;
        }
      }
    }

    var whitelistInUse = false;
    for (final title in _windowTitles) {
      if (title.trim().isNotEmpty) {
        whitelistInUse = true;
        if (windowTitle.contains(title)) {
          _interactiveCache[hWnd] = true;
          return true;
        }
      }
    }

    if (whitelistInUse || !blacklistInUse) {
      _interactiveCache[hWnd] = false;
      return false;
    } else {
      _interactiveCache[hWnd] = true;
      return true;
    }
  }

  static const int _statusValid = 0;
  static const int _statusInvalid = 1;
  static const int _statusIgnored = 2;
  static const int _statusOutOfBounds = 3;

  int _getWindowStatus(int hWnd) {
    if (IsWindowVisible(HWND(Pointer.fromAddress(hWnd)))) {
      if (_isCloaked(hWnd)) return _statusIgnored;
      if (IsZoomed(HWND(Pointer.fromAddress(hWnd)))) return _statusInvalid;
      if (_isInteractive(hWnd) &&
          !IsIconic(HWND(Pointer.fromAddress(hWnd)))) {
        final windowRect = _getWindowRect(hWnd);
        if (windowRect != null && _screenUnionRect().intersects(windowRect)) {
          return _statusValid;
        } else {
          return _statusOutOfBounds;
        }
      }
    }
    return _statusIgnored;
  }

  bool _isCloaked(int hWnd) {
    final flags = calloc<Uint32>();
    try {
      DwmGetWindowAttribute(
        HWND(Pointer.fromAddress(hWnd)),
        DWMWA_CLOAKED,
        flags,
        sizeOf<Uint32>(),
      );
      return flags.value != 0;
    } catch (_) {
      // Pre-Windows 8 systems do not support this attribute.
      return false;
    } finally {
      calloc.free(flags);
    }
  }

  int _findActiveWindow() {
    _activeWindowHandle = 0;
    EnumWindows(
      Pointer.fromFunction<WNDENUMPROC>(_enumProc, 0),
      LPARAM(0),
    );
    return _activeWindowHandle;
  }

  static int _enumProc(Pointer hWnd, int lParam) {
    final self = _instance;
    if (self == null) return 0;
    final address = hWnd.address;
    switch (self._getWindowStatus(address)) {
      case _statusValid:
        self._activeWindowHandle = address;
        return 0; // stop enumeration
      case _statusIgnored:
      case _statusOutOfBounds:
        return 1; // continue
      default:
        self._activeWindowHandle = 0;
        return 0; // abort search
    }
  }

  JRect? _getWindowRect(int? hWnd) {
    if (hWnd == null || hWnd == 0) return null;
    final rect = calloc<RECT>();
    try {
      // Prefer the DWM extended frame bounds (excludes invisible borders).
      try {
        DwmGetWindowAttribute(
          HWND(Pointer.fromAddress(hWnd)),
          DWMWA_EXTENDED_FRAME_BOUNDS,
          rect,
          sizeOf<RECT>(),
        );
        return JRect(rect.ref.left, rect.ref.top,
            rect.ref.right - rect.ref.left, rect.ref.bottom - rect.ref.top);
      } catch (_) {
        // Fall through to GetWindowRect.
      }
      if (!GetWindowRect(HWND(Pointer.fromAddress(hWnd)), rect).value) {
        return null;
      }
      return JRect(rect.ref.left, rect.ref.top,
          rect.ref.right - rect.ref.left, rect.ref.bottom - rect.ref.top);
    } finally {
      calloc.free(rect);
    }
  }

  String _getWindowTitle(int hWnd) {
    final length = GetWindowTextLength(HWND(Pointer.fromAddress(hWnd))).value;
    if (length <= 0) return '';
    final buffer = wsalloc(length + 1);
    try {
      GetWindowText(HWND(Pointer.fromAddress(hWnd)), buffer, length + 1);
      return buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  JRect _screenUnionRect() {
    return screenRect ?? JRect(0, 0, 0, 0);
  }

  @override
  void updateScreenRects() {
    final screens = <String, JRect>{};
    final workAreas = <String, JRect>{};
    int left = 0x7FFFFFFF, top = 0x7FFFFFFF, right = -0x80000000, bottom = -0x80000000;
    var monitorIndex = 0;

    _monitorContext = (int hMonitor) {
      final info = calloc<MONITORINFO>();
      try {
        info.ref.cbSize = sizeOf<MONITORINFO>();
        if (GetMonitorInfo(HMONITOR(Pointer.fromAddress(hMonitor)), info)) {
          final id = 'screen${monitorIndex++}';
          final bounds = JRect(
              info.ref.rcMonitor.left,
              info.ref.rcMonitor.top,
              info.ref.rcMonitor.right - info.ref.rcMonitor.left,
              info.ref.rcMonitor.bottom - info.ref.rcMonitor.top);
          screens[id] = bounds;
          workAreas[id] = JRect(
              info.ref.rcWork.left,
              info.ref.rcWork.top,
              info.ref.rcWork.right - info.ref.rcWork.left,
              info.ref.rcWork.bottom - info.ref.rcWork.top);
          left = math.min(left, bounds.x);
          top = math.min(top, bounds.y);
          right = math.max(right, bounds.x + bounds.width);
          bottom = math.max(bottom, bounds.y + bounds.height);
        }
      } finally {
        calloc.free(info);
      }
      return 1; // continue
    };

    EnumDisplayMonitors(
      null,
      null,
      Pointer.fromFunction<MONITORENUMPROC>(_monitorProc, 0),
      LPARAM(0),
    );
    _monitorContext = null;

    if (screens.isEmpty) {
      screenRect = JRect(0, 0, 1920, 1080);
      screenRects = {'screen0': screenRect!};
      workAreaRects = {'screen0': screenRect!};
    } else {
      screenRect = JRect(left, top, right - left, bottom - top);
      screenRects = screens;
      workAreaRects = workAreas;
    }
  }

  static int Function(int hMonitor)? _monitorContext;

  static int _monitorProc(
      Pointer hMonitor, Pointer hdcMonitor, Pointer<RECT> lprcMonitor, int dwData) {
    return _monitorContext?.call(hMonitor.address) ?? 0;
  }

  @override
  Area getActiveWindow() => _activeWindow;

  @override
  String getActiveWindowTitle() => _activeWindowTitle;

  @override
  int getActiveWindowId() => _activeWindowHandle;

  @override
  void moveActiveWindow(int x, int y) {
    if (_activeWindowHandle == 0) return;
    SetWindowPos(
      HWND(Pointer.fromAddress(_activeWindowHandle)),
      null,
      x,
      y,
      0,
      0,
      SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER,
    );
  }

  @override
  void restoreWindows() {
    var offset = 25;
    final workArea = _primaryWorkArea();

    _restoreContext = (int hWnd) {
      if (_getWindowStatus(hWnd) == _statusOutOfBounds) {
        final rect = _getWindowRect(hWnd);
        if (rect == null) return;
        MoveWindow(
          HWND(Pointer.fromAddress(hWnd)),
          workArea.x + offset,
          workArea.y + offset,
          rect.width,
          rect.height,
          true,
        );
        BringWindowToTop(HWND(Pointer.fromAddress(hWnd)));
        offset += 25;
      }
    };

    EnumWindows(
      Pointer.fromFunction<WNDENUMPROC>(_restoreEnumProc, 0),
      LPARAM(0),
    );
    _restoreContext = null;
  }

  static void Function(int hWnd)? _restoreContext;

  static int _restoreEnumProc(Pointer hWnd, int lParam) {
    _restoreContext?.call(hWnd.address);
    return 1; // continue
  }

  JRect _primaryWorkArea() {
    final point = calloc<POINT>();
    final info = calloc<MONITORINFO>();
    try {
      point.ref.x = 0;
      point.ref.y = 0;
      final monitor =
          MonitorFromPoint(point.ref, MONITOR_DEFAULTTOPRIMARY);
      info.ref.cbSize = sizeOf<MONITORINFO>();
      if (GetMonitorInfo(monitor, info)) {
        return JRect(
            info.ref.rcWork.left,
            info.ref.rcWork.top,
            info.ref.rcWork.right - info.ref.rcWork.left,
            info.ref.rcWork.bottom - info.ref.rcWork.top);
      }
      return JRect(0, 0, 1920, 1040);
    } finally {
      calloc.free(point);
      calloc.free(info);
    }
  }

  /// Refreshes the cursor position from the OS (called by the manager tick).
  void pollCursor() {
    final point = calloc<POINT>();
    try {
      if (GetCursorPos(point).value) {
        cursor.set(point.ref.x, point.ref.y);
      } else {
        cursor.set(0, 0);
      }
    } finally {
      calloc.free(point);
    }
  }

  /// Returns the async key state bit for the given virtual key.
  static bool isKeyDown(int vKey) =>
      (GetAsyncKeyState(vKey) & 0x8000) != 0;

  @override
  void refreshCache() {
    _interactiveCache.clear();
  }
}
