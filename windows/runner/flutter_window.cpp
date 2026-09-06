#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "mascot_windows.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const char kChannelName[] = "shimeji/mascots";

int32_t GetInt(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return 0;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int32_t>(*value);
  }
  return 0;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The Flutter engine runs headless: the host window is never shown. The
  // visible surface is a set of per-mascot layered windows managed through
  // the channel below.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  RegisterMascotChannel();

  return true;
}

void FlutterWindow::RegisterMascotChannel() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method_name = call.method_name();
        const EncodableValue* args = call.arguments();
        EncodableMap map;
        if (args) {
          if (const auto* m = std::get_if<EncodableMap>(args)) {
            map = *m;
          }
        }

        if (method_name == "createMascotWindow") {
          MascotWindows::Instance().Create(GetInt(map, "id"));
          result->Success();
          return;
        }
        if (method_name == "updateMascotWindow") {
          int id = GetInt(map, "id");
          int x = GetInt(map, "x");
          int y = GetInt(map, "y");
          int w = GetInt(map, "w");
          int h = GetInt(map, "h");
          const uint8_t* bytes = nullptr;
          size_t byte_count = 0;
          auto bytes_it = map.find(EncodableValue("bytes"));
          if (bytes_it != map.end()) {
            if (const auto* list =
                    std::get_if<std::vector<uint8_t>>(&bytes_it->second)) {
              bytes = list->data();
              byte_count = list->size();
            }
          }
          bool ok = MascotWindows::Instance().Update(id, x, y, w, h, bytes,
                                                     byte_count);
          result->Success(EncodableValue(ok));
          return;
        }
        if (method_name == "destroyMascotWindow") {
          MascotWindows::Instance().Destroy(GetInt(map, "id"));
          result->Success();
          return;
        }
        if (method_name == "destroyAllMascotWindows") {
          MascotWindows::Instance().DestroyAll();
          result->Success();
          return;
        }
        if (method_name == "showSettingsWindow") {
          int width = GetInt(map, "width");
          int height = GetInt(map, "height");
          if (width <= 0) width = 980;
          if (height <= 0) height = 720;
          ShowSettingsWindow(width, height);
          result->Success();
          return;
        }
        if (method_name == "hideSettingsWindow") {
          HideSettingsWindow();
          result->Success();
          return;
        }
        if (method_name == "showContextMenu") {
          int id = GetInt(map, "id");
          int x = GetInt(map, "x");
          int y = GetInt(map, "y");
          std::vector<MascotWindows::MenuItem> items;
          auto items_it = map.find(EncodableValue("items"));
          if (items_it != map.end()) {
            if (const auto* list =
                    std::get_if<EncodableList>(&items_it->second)) {
              for (const EncodableValue& entry : *list) {
                if (const auto* item = std::get_if<EncodableMap>(&entry)) {
                  MascotWindows::MenuItem out;
                  auto label_it = item->find(EncodableValue("label"));
                  if (label_it != item->end()) {
                    if (const auto* label =
                            std::get_if<std::string>(&label_it->second)) {
                      out.label = std::wstring(label->begin(), label->end());
                    }
                  }
                  auto checked_it = item->find(EncodableValue("checked"));
                  if (checked_it != item->end()) {
                    if (const auto* checked =
                            std::get_if<bool>(&checked_it->second)) {
                      out.checked = *checked;
                    }
                  }
                  auto separator_it = item->find(EncodableValue("separator"));
                  if (separator_it != item->end()) {
                    if (const auto* separator =
                            std::get_if<bool>(&separator_it->second)) {
                      out.separator = *separator;
                    }
                  }
                  items.push_back(std::move(out));
                }
              }
            }
          }
          int selected =
              MascotWindows::Instance().ShowContextMenu(id, x, y, items);
          result->Success(EncodableValue(selected));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::ShowSettingsWindow(int width, int height) {
  settings_visible_ = true;
  HWND hwnd = GetHandle();

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~WS_POPUP;
  style |= WS_OVERLAPPEDWINDOW | WS_VISIBLE;
  SetWindowLongPtr(hwnd, GWL_STYLE, style);
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style &= ~(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  const int screen_w = GetSystemMetrics(SM_CXSCREEN);
  const int screen_h = GetSystemMetrics(SM_CYSCREEN);
  SetWindowPos(hwnd, HWND_TOP, (screen_w - width) / 2,
               (screen_h - height) / 2, width, height,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  ShowWindow(hwnd, SW_SHOW);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::HideSettingsWindow() {
  settings_visible_ = false;
  HWND hwnd = GetHandle();
  ShowWindow(hwnd, SW_HIDE);

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~WS_OVERLAPPEDWINDOW;
  style |= WS_POPUP;
  SetWindowLongPtr(hwnd, GWL_STYLE, style);
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST;
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  const int vs_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int vs_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int vs_w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int vs_h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  SetWindowPos(hwnd, HWND_TOPMOST, vs_x, vs_y, vs_w, vs_h,
               SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void FlutterWindow::OnDestroy() {
  MascotWindows::Instance().DestroyAll();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  channel_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      // The host window doubles as the settings dialog. Closing it hides it
      // again instead of tearing down the engine.
      if (settings_visible_) {
        HideSettingsWindow();
        if (channel_) {
          channel_->InvokeMethod("settingsClosed", nullptr);
        }
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
