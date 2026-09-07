#include "flutter_mascot_windows.h"

#include <dwmapi.h>
#include <windowsx.h>
#include <optional>

namespace {

constexpr wchar_t kFlutterMascotClassName[] = L"SHIMEJI_FLUTTER_MASCOT";

bool g_flutter_mascot_class_registered = false;

}  // namespace

FlutterMascotWindows& FlutterMascotWindows::Instance() {
  static FlutterMascotWindows instance;
  return instance;
}

void FlutterMascotWindows::EnsureClass() {
  if (g_flutter_mascot_class_registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.lpfnWndProc = FlutterMascotWindows::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kFlutterMascotClassName;
  window_class.hbrBackground = nullptr;
  RegisterClass(&window_class);
  g_flutter_mascot_class_registered = true;
}

LRESULT CALLBACK FlutterMascotWindows::WndProc(HWND window, UINT message,
                                               WPARAM wparam,
                                               LPARAM lparam) {
  auto* mascot = reinterpret_cast<MascotWindow*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  switch (message) {
    case WM_NCCREATE:
      // Store the MascotWindow* passed to CreateWindowEx so later messages
      // (WM_NCHITTEST, WM_SIZE) reach the instance.
      SetWindowLongPtr(
          window, GWLP_USERDATA,
          reinterpret_cast<LONG_PTR>(
              reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams));
      return DefWindowProc(window, message, wparam, lparam);
    case WM_NCHITTEST: {
      // Per-pixel click-through against the cached pose alpha, matching the
      // legacy UpdateLayeredWindow behavior: transparent pixels let clicks
      // fall through to whatever is underneath, opaque pixels are swallowed
      // by the mascot window. (The Flutter child is WS_EX_TRANSPARENT so
      // hit tests reach this window.)
      if (mascot == nullptr || mascot->rgba.empty()) {
        break;
      }
      POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(window, &pt);
      const int w = mascot->pose_w;
      const int h = mascot->pose_h;
      if (w <= 0 || h <= 0 || pt.x < 0 || pt.y < 0 || pt.x >= w ||
          pt.y >= h) {
        break;
      }
      const int source_x = mascot->flipped ? (w - 1 - pt.x) : pt.x;
      const uint8_t alpha =
          mascot->rgba[(static_cast<size_t>(pt.y) * w + source_x) * 4 + 3];
      if (alpha < 8) {
        return HTTRANSPARENT;
      }
      return HTCLIENT;
    }
    case WM_SIZE:
      if (mascot != nullptr && mascot->flutter_hwnd != nullptr) {
        MoveWindow(mascot->flutter_hwnd, 0, 0, LOWORD(lparam),
                   HIWORD(lparam), FALSE);
      }
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_DESTROY:
      return 0;
  }
  // Give the Flutter engine a chance to see top-level messages. WM_DPICHANGED
  // in particular MUST reach the engine (the view is a child window and only
  // learns about scale changes through this forwarding); the engine then
  // re-renders at the new DPR while the window geometry stays owned by the
  // main engine in physical pixels (RawImage stretches to the exact window
  // size either way).
  if (mascot != nullptr && mascot->controller != nullptr) {
    std::optional<LRESULT> engine_result =
        mascot->controller->HandleTopLevelWindowProc(window, message, wparam,
                                                     lparam);
    if (engine_result) {
      return *engine_result;
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

void FlutterMascotWindows::Create(int id) {
  if (windows_.count(id) != 0) {
    return;
  }
  EnsureClass();
  auto window = std::make_unique<MascotWindow>();
  HWND hwnd = CreateWindowEx(
      WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST,
      kFlutterMascotClassName, L"shimeji_flutter_mascot", WS_POPUP, 0, 0, 1,
      1, nullptr, nullptr, GetModuleHandle(nullptr), window.get());
  if (!hwnd) {
    return;
  }
  window->hwnd = hwnd;

  // Extend the DWM glass frame across the whole client area: the Flutter
  // view's per-pixel alpha then composites against the desktop, giving the
  // same visual result as the legacy layered windows.
  MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(
      {"mascot_window", std::to_string(id)});
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
  window->controller =
      std::make_unique<flutter::FlutterViewController>(1, 1, project);
  if (!window->controller->engine() || !window->controller->view()) {
    window->controller.reset();
    DestroyWindow(hwnd);
    return;
  }

  HWND flutter_hwnd = window->controller->view()->GetNativeWindow();
  window->flutter_hwnd = flutter_hwnd;
  // Mouse input is polled globally by the main engine; the Flutter child
  // must never intercept hit tests, or WM_NCHITTEST above could not apply
  // the per-pixel alpha rule.
  LONG_PTR ex_style = GetWindowLongPtr(flutter_hwnd, GWL_EXSTYLE);
  SetWindowLongPtr(flutter_hwnd, GWL_EXSTYLE, ex_style | WS_EX_TRANSPARENT);
  SetParent(flutter_hwnd, hwnd);
  MoveWindow(flutter_hwnd, 0, 0, 1, 1, FALSE);

  window->channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          window->controller->engine()->messenger(), "shimeji/mascot_view",
          &flutter::StandardMethodCodec::GetInstance());
  MascotWindow* raw = window.get();
  window->channel->SetMethodCallHandler(
      [this, raw](const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                      result) {
        if (call.method_name() == "ready") {
          // The engine installed its handler; hand over the pose that
          // arrived while it was still booting.
          raw->engine_ready = true;
          SendPose(*raw);
        }
        result->Success();
        return;
      });

  windows_[id] = std::move(window);
}

bool FlutterMascotWindows::Update(int id, int x, int y, int w, int h,
                                  const std::vector<uint8_t>* rgba,
                                  bool flipped, double opacity, int64_t hash) {
  auto it = windows_.find(id);
  if (it == windows_.end() || w <= 0 || h <= 0) {
    return false;
  }
  MascotWindow& window = *it->second;
  if (rgba != nullptr &&
      rgba->size() >= static_cast<size_t>(w) * static_cast<size_t>(h) * 4) {
    window.rgba = *rgba;
    window.pose_w = w;
    window.pose_h = h;
    window.flipped = flipped;
    window.opacity = opacity;
    window.hash = hash;
    if (window.engine_ready) {
      SendPose(window);
    }
  }
  UINT flags = SWP_NOACTIVATE | SWP_NOZORDER;
  if (!IsWindowVisible(window.hwnd)) {
    flags |= SWP_SHOWWINDOW;
    // Wake the engine's frame production when the window first becomes
    // visible (vsync can stay paused for windows shown after creation).
    if (window.controller != nullptr) {
      window.controller->ForceRedraw();
    }
  }
  SetWindowPos(window.hwnd, nullptr, x, y, w, h, flags);
  if (window.flutter_hwnd != nullptr) {
    MoveWindow(window.flutter_hwnd, 0, 0, w, h, FALSE);
  }
  return true;
}

void FlutterMascotWindows::SendPose(MascotWindow& window) {
  if (window.rgba.empty() || window.channel == nullptr) {
    return;
  }
  flutter::EncodableMap args;
  args[flutter::EncodableValue("bytes")] = flutter::EncodableValue(window.rgba);
  args[flutter::EncodableValue("w")] =
      flutter::EncodableValue(static_cast<int32_t>(window.pose_w));
  args[flutter::EncodableValue("h")] =
      flutter::EncodableValue(static_cast<int32_t>(window.pose_h));
  args[flutter::EncodableValue("flipped")] =
      flutter::EncodableValue(window.flipped);
  args[flutter::EncodableValue("opacity")] =
      flutter::EncodableValue(window.opacity);
  args[flutter::EncodableValue("hash")] = flutter::EncodableValue(window.hash);
  window.channel->InvokeMethod(
      "pose", std::make_unique<flutter::EncodableValue>(args));
}

void FlutterMascotWindows::Destroy(int id) {
  auto it = windows_.find(id);
  if (it == windows_.end()) {
    return;
  }
  MascotWindow& window = *it->second;
  if (window.channel != nullptr) {
    // Detach before teardown: the handler captures the MascotWindow.
    window.channel->SetMethodCallHandler(nullptr);
  }
  window.channel.reset();
  window.controller.reset();  // shuts the engine and its view down
  if (window.hwnd != nullptr) {
    SetWindowLongPtr(window.hwnd, GWLP_USERDATA, 0);
    DestroyWindow(window.hwnd);
  }
  windows_.erase(it);
}

void FlutterMascotWindows::DestroyAll() {
  std::vector<int> ids;
  ids.reserve(windows_.size());
  for (auto& entry : windows_) {
    ids.push_back(entry.first);
  }
  for (int id : ids) {
    Destroy(id);
  }
}
