#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that hosts a Flutter view and manages the desktop overlay.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Registers the mascot window management channel.
  void RegisterMascotChannel();

  // Settings-screen host window management: reveals the (normally hidden)
  // host window as a chromeless dialog (the Flutter UI draws its own
  // header), hides it again, and lets the Flutter header drag it.
  void ShowSettingsWindow(int width, int height);
  void HideSettingsWindow();
  void BeginWindowDrag();

  bool settings_visible() const { return settings_visible_; }

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The mascot/control channel.
  std::unique_ptr<
      flutter::MethodChannel<flutter::EncodableValue>>
      channel_;

  // Whether the host window currently displays the settings screen.
  bool settings_visible_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
