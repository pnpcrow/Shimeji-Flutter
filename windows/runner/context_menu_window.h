#ifndef RUNNER_CONTEXT_MENU_WINDOW_H_
#define RUNNER_CONTEXT_MENU_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

// The Flutter-rendered context menu of the "flutter" renderer mode.
//
// One persistent borderless topmost window hosts a dedicated Flutter engine
// (created lazily, usually prewarmed at start-up). The main engine sends
// the localized entry tree over the channel; the menu engine lays it out
// and reports its desired logical size, the native side converts it to
// physical pixels, clamps it against the monitor work area at the anchor
// point, sizes/shows the window and activates it. Selecting an entry or
// losing activation completes the pending 'showContextMenu' result with
// the stable item id (or '' when dismissed).
class ContextMenuWindow {
 public:
  using Done = std::function<void(const std::string& selected_id)>;

  static ContextMenuWindow& Instance();

  // Creates the window and boots the menu engine (hidden). Idempotent;
  // also used to prewarm the engine before the first right-click.
  void EnsureCreated();

  // Shows the menu anchored at physical screen (x, y). |items| is the raw
  // encoded entry tree from the main engine, forwarded verbatim. |done| is
  // called exactly once with the selected stable id ('' = dismissed).
  void Show(const flutter::EncodableList& items, int x, int y, Done done);

  // Tears the window and engine down (app exit).
  void Destroy();

 private:
  ContextMenuWindow() = default;

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  static void EnsureClass();

  void SendShow(const flutter::EncodableList& items);
  // Sizes/positions the window for the menu content. |dpr| is the scale the
  // menu engine actually rendered the frame with (reported alongside the
  // logical size); the window is sized with exactly that factor so its
  // pixels map 1:1 onto the rendered content. 0 falls back to the anchor
  // monitor's DPI.
  void ApplySize(double logical_w, double logical_h, double dpr);
  void ActivateMenu();
  void Complete(const std::string& selected_id);

  HWND hwnd_ = nullptr;
  HWND flutter_hwnd_ = nullptr;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool engine_ready_ = false;

  bool menu_active_ = false;
  int anchor_x_ = 0;
  int anchor_y_ = 0;
  Done pending_;
  HWND previous_foreground_ = nullptr;
  // Items that arrived while the engine was still booting.
  std::shared_ptr<flutter::EncodableList> pending_items_;
};

#endif  // RUNNER_CONTEXT_MENU_WINDOW_H_
