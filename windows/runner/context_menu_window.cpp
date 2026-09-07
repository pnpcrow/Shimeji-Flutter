#include "context_menu_window.h"

#include <dwmapi.h>

#include <algorithm>

namespace {

constexpr wchar_t kContextMenuClassName[] = L"SHIMEJI_FLUTTER_CONTEXT_MENU";

bool g_context_menu_class_registered = false;

// Effective DPI of the monitor containing |pt| (GetDpiForMonitor from
// Shcore, loaded dynamically to avoid a header/link dependency). Falls
// back to the DPI of |fallback_window|.
UINT DpiAtPoint(const POINT& pt, HWND fallback_window) {
  using GetDpiForMonitorFn =
      HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);
  static GetDpiForMonitorFn get_dpi_for_monitor = []() {
    HMODULE shcore = LoadLibraryA("Shcore.dll");
    return shcore != nullptr
               ? reinterpret_cast<GetDpiForMonitorFn>(GetProcAddress(
                     shcore, "GetDpiForMonitor"))
               : nullptr;
  }();
  HMONITOR monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  if (get_dpi_for_monitor != nullptr && monitor != nullptr) {
    UINT dpi_x = 0;
    UINT dpi_y = 0;
    // 0 == MDT_EFFECTIVE_DPI.
    if (SUCCEEDED(get_dpi_for_monitor(monitor, 0, &dpi_x, &dpi_y)) &&
        dpi_x != 0) {
      return dpi_x;
    }
  }
  UINT dpi = fallback_window != nullptr ? GetDpiForWindow(fallback_window)
                                         : 0;
  return dpi != 0 ? dpi : 96;
}

}  // namespace

ContextMenuWindow& ContextMenuWindow::Instance() {
  static ContextMenuWindow instance;
  return instance;
}

void ContextMenuWindow::EnsureClass() {
  if (g_context_menu_class_registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.lpfnWndProc = ContextMenuWindow::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kContextMenuClassName;
  window_class.hbrBackground = nullptr;
  RegisterClass(&window_class);
  g_context_menu_class_registered = true;
}

LRESULT CALLBACK ContextMenuWindow::WndProc(HWND window, UINT message,
                                            WPARAM wparam, LPARAM lparam) {
  auto* menu = reinterpret_cast<ContextMenuWindow*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  switch (message) {
    case WM_NCCREATE:
      // Store the ContextMenuWindow* passed to CreateWindowEx so later
      // messages (WM_SIZE, WM_ACTIVATE) reach the instance.
      SetWindowLongPtr(
          window, GWLP_USERDATA,
          reinterpret_cast<LONG_PTR>(
              reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams));
      return DefWindowProc(window, message, wparam, lparam);
    case WM_NCCALCSIZE:
      // Frameless menu surface: WS_THICKFRAME is kept so DWM still draws
      // the shadow (and rounds the corners), but the whole window stays
      // client area for the Flutter view.
      if (wparam) {
        return 0;
      }
      break;
    case WM_NCHITTEST:
      // Menus are not resizable; swallow the thick-frame resize edges.
      return HTCLIENT;
    case WM_MOUSEACTIVATE:
      // Activate on the first click (an unactivated top-level window would
      // otherwise lose the activating click) and still deliver it, so a
      // single click selects an item even when the activation dance during
      // ApplySize failed to steal the foreground.
      if (wparam != 0 && menu != nullptr && (HWND)wparam == window) {
        return MA_ACTIVATE;
      }
      break;
    case WM_ACTIVATE:
      if (menu != nullptr) {
        if (LOWORD(wparam) == WA_INACTIVE) {
          // Click-away dismissal, like a native popup menu.
          menu->Complete("");
        } else if (menu->flutter_hwnd_ != nullptr) {
          SetFocus(menu->flutter_hwnd_);
        }
      }
      return 0;
    case WM_SIZE:
      if (menu != nullptr && menu->flutter_hwnd_ != nullptr) {
        MoveWindow(menu->flutter_hwnd_, 0, 0, LOWORD(lparam),
                   HIWORD(lparam), TRUE);
      }
      return 0;
    case WM_DPICHANGED:
      return 0;  // sizes are always re-derived from the menu engine
    case WM_ERASEBKGND:
      return 1;
    case WM_DESTROY:
      return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

void ContextMenuWindow::EnsureCreated() {
  if (controller_ != nullptr && hwnd_ != nullptr) {
    return;
  }
  EnsureClass();
  hwnd_ = CreateWindowEx(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kContextMenuClassName,
      L"shimeji_context_menu", WS_POPUP | WS_THICKFRAME, 0, 0, 1, 1, nullptr,
      nullptr, GetModuleHandle(nullptr), this);
  if (!hwnd_) {
    return;
  }

  // Windows-11 style rounded corners + shadow for the frameless surface.
  DWM_WINDOW_CORNER_PREFERENCE preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &preference,
                        sizeof(preference));

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({"context_menu"});
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
  controller_ = std::make_unique<flutter::FlutterViewController>(1, 1, project);
  if (!controller_->engine() || !controller_->view()) {
    controller_.reset();
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    return;
  }

  flutter_hwnd_ = controller_->view()->GetNativeWindow();
  SetParent(flutter_hwnd_, hwnd_);
  MoveWindow(flutter_hwnd_, 0, 0, 1, 1, FALSE);

  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          controller_->engine()->messenger(), "shimeji/context_menu",
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        const auto* args = call.arguments();
        flutter::EncodableMap map;
        if (args != nullptr) {
          if (const auto* m = std::get_if<flutter::EncodableMap>(args)) {
            map = *m;
          }
        }
        auto number_field = [&map](const char* key) -> double {
          auto it = map.find(flutter::EncodableValue(key));
          if (it == map.end()) {
            return 0;
          }
          if (const auto* v = std::get_if<double>(&it->second)) {
            return *v;
          }
          if (const auto* v = std::get_if<int32_t>(&it->second)) {
            return *v;
          }
          if (const auto* v = std::get_if<int64_t>(&it->second)) {
            return static_cast<double>(*v);
          }
          return 0;
        };
        if (method == "ready") {
          engine_ready_ = true;
          auto items = std::move(pending_items_);
          if (items != nullptr && pending_ != nullptr) {
            SendShow(*items);
          }
        } else if (method == "setMenuSize") {
          if (menu_active_) {
            ApplySize(number_field("w"), number_field("h"));
          }
        } else if (method == "selected") {
          std::string id;
          auto it = map.find(flutter::EncodableValue("id"));
          if (it != map.end()) {
            if (const auto* v = std::get_if<std::string>(&it->second)) {
              id = *v;
            }
          }
          Complete(id);
        }
        result->Success();
      });
}

void ContextMenuWindow::Show(const flutter::EncodableList& items, int x, int y,
                             Done done) {
  EnsureCreated();
  if (hwnd_ == nullptr) {
    done("");
    return;
  }
  if (pending_ != nullptr) {
    Complete("");  // A menu is already open; dismiss it first.
  }
  pending_ = std::move(done);
  anchor_x_ = x;
  anchor_y_ = y;
  previous_foreground_ = GetForegroundWindow();
  menu_active_ = true;

  // Open as a full-work-area transparent window anchored at (x, y), BEFORE
  // the content is sent: the menu engine lays out against the window
  // constraints, so it needs the room up front, and reports the content
  // size back on 'setMenuSize' (which then shrinks the window to the menu
  // itself and activates it). Doing this first also keeps the Dart reply
  // from re-entering inside a nested SetWindowPos dispatch.
  POINT pt{anchor_x_, anchor_y_};
  HMONITOR monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  int big_w = GetSystemMetrics(SM_CXSCREEN);
  int big_h = GetSystemMetrics(SM_CYSCREEN);
  if (GetMonitorInfo(monitor, &info)) {
    big_w = info.rcWork.right - info.rcWork.left;
    big_h = info.rcWork.bottom - info.rcWork.top;
  }
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, big_w, big_h,
               SWP_SHOWWINDOW | SWP_NOACTIVATE);

  if (engine_ready_) {
    SendShow(items);
  } else {
    pending_items_ = std::make_shared<flutter::EncodableList>(items);
  }
}

void ContextMenuWindow::SendShow(const flutter::EncodableList& items) {
  if (channel_ == nullptr) {
    return;
  }
  // Cap the menu height to the monitor work area at the anchor (logical
  // units for the menu engine), using the anchor monitor's DPI.
  POINT pt{anchor_x_, anchor_y_};
  HMONITOR monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  double max_height = 10000.0;
  UINT dpi = DpiAtPoint(pt, hwnd_);
  if (GetMonitorInfo(monitor, &info)) {
    max_height = (info.rcWork.bottom - info.rcWork.top - 16) * 96.0 / dpi;
  }
  flutter::EncodableMap args;
  args[flutter::EncodableValue("items")] = flutter::EncodableValue(items);
  args[flutter::EncodableValue("maxHeight")] =
      flutter::EncodableValue(max_height);
  channel_->InvokeMethod(
      "show", std::make_unique<flutter::EncodableValue>(args));
}

void ContextMenuWindow::ApplySize(double logical_w, double logical_h) {
  if (hwnd_ == nullptr || logical_w <= 0 || logical_h <= 0) {
    return;
  }
  // The DPI of the monitor the menu is being placed on; the window itself
  // may still report the DPI of its previous (possibly hidden) position.
  POINT anchor{anchor_x_, anchor_y_};
  UINT dpi = DpiAtPoint(anchor, hwnd_);
  int w = static_cast<int>(logical_w * dpi / 96.0);
  int h = static_cast<int>(logical_h * dpi / 96.0);

  // Clamp against the work area of the monitor containing the anchor.
  HMONITOR monitor = MonitorFromPoint(anchor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  RECT work{};
  if (GetMonitorInfo(monitor, &info)) {
    work = info.rcWork;
  } else {
    work = {0, 0, GetSystemMetrics(SM_CXSCREEN),
            GetSystemMetrics(SM_CYSCREEN)};
  }
  w = std::min(w, static_cast<int>(work.right - work.left));
  h = std::min(h, static_cast<int>(work.bottom - work.top));
  int x = anchor_x_;
  int y = anchor_y_;
  if (x + w > work.right) {
    x = work.right - w;
  }
  if (y + h > work.bottom) {
    y = work.bottom - h;
  }
  x = std::max(x, static_cast<int>(work.left));
  y = std::max(y, static_cast<int>(work.top));

  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, w, h,
               SWP_SHOWWINDOW | SWP_NOACTIVATE);
  // Raise to the top of the topmost band: the mascot windows are topmost
  // too and must never cover the menu.
  SetWindowPos(hwnd_, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  ActivateMenu();
}

void ContextMenuWindow::ActivateMenu() {
  // The foreground lock prevents plain SetForegroundWindow from stealing
  // focus; attach to the foreground thread like the legacy menu path.
  HWND foreground = GetForegroundWindow();
  DWORD foreground_thread =
      foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
  DWORD this_thread = GetCurrentThreadId();
  if (foreground_thread != 0 && foreground_thread != this_thread) {
    AttachThreadInput(this_thread, foreground_thread, TRUE);
  }
  SetForegroundWindow(hwnd_);
  SetActiveWindow(hwnd_);
  if (foreground_thread != 0 && foreground_thread != this_thread) {
    AttachThreadInput(this_thread, foreground_thread, FALSE);
  }
}

void ContextMenuWindow::Complete(const std::string& selected_id) {
  if (pending_ == nullptr) {
    return;
  }
  Done done = std::move(pending_);
  pending_ = nullptr;
  pending_items_.reset();
  menu_active_ = false;
  ShowWindow(hwnd_, SW_HIDE);

  HWND foreground = previous_foreground_;
  previous_foreground_ = nullptr;
  if (foreground != nullptr && foreground != hwnd_ && IsWindow(foreground)) {
    DWORD foreground_thread =
        GetWindowThreadProcessId(foreground, nullptr);
    DWORD this_thread = GetCurrentThreadId();
    if (foreground_thread != 0 && foreground_thread != this_thread) {
      AttachThreadInput(this_thread, foreground_thread, TRUE);
    }
    SetForegroundWindow(foreground);
    if (foreground_thread != 0 && foreground_thread != this_thread) {
      AttachThreadInput(this_thread, foreground_thread, FALSE);
    }
  }
  done(selected_id);
}

void ContextMenuWindow::Destroy() {
  if (channel_ != nullptr) {
    // Detach before teardown: the handler captures |this|.
    channel_->SetMethodCallHandler(nullptr);
  }
  channel_.reset();
  controller_.reset();
  if (hwnd_ != nullptr) {
    SetWindowLongPtr(hwnd_, GWLP_USERDATA, 0);
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    flutter_hwnd_ = nullptr;
  }
  pending_ = nullptr;
  pending_items_.reset();
  menu_active_ = false;
  engine_ready_ = false;
}
