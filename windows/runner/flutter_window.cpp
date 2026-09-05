#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"
#include "overlay_state.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const char kChannelName[] = "shimeji/overlay";

OverlayState::Region ParseRegion(const EncodableMap& map) {
  OverlayState::Region region;
  auto get_int = [&map](const char* key) -> int32_t {
    auto it = map.find(EncodableValue(key));
    if (it == map.end()) {
      return 0;
    }
    const auto* value = std::get_if<int32_t>(&it->second);
    if (value) {
      return *value;
    }
    const auto* long_value = std::get_if<int64_t>(&it->second);
    return long_value ? static_cast<int32_t>(*long_value) : 0;
  };
  region.x = get_int("x");
  region.y = get_int("y");
  region.w = get_int("w");
  region.h = get_int("h");
  region.cols = get_int("cols");
  region.rows = get_int("rows");
  region.cell = get_int("cell");
  auto mask_it = map.find(EncodableValue("mask"));
  if (mask_it != map.end()) {
    if (const auto* words = std::get_if<EncodableList>(&mask_it->second)) {
      region.mask.reserve(words->size());
      for (const EncodableValue& word : *words) {
        const auto* int_value = std::get_if<int32_t>(&word);
        if (int_value) {
          region.mask.push_back(static_cast<uint32_t>(*int_value));
          continue;
        }
        const auto* long_value = std::get_if<int64_t>(&word);
        if (long_value) {
          region.mask.push_back(static_cast<uint32_t>(*long_value));
        }
      }
    }
  }
  return region;
}

std::vector<OverlayState::Region> ParseRegions(const EncodableValue* args) {
  std::vector<OverlayState::Region> regions;
  if (const auto* list = std::get_if<EncodableList>(args)) {
    regions.reserve(list->size());
    for (const EncodableValue& entry : *list) {
      if (const auto* map = std::get_if<EncodableMap>(&entry)) {
        regions.push_back(ParseRegion(*map));
      }
    }
  }
  return regions;
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

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  RegisterOverlayChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterOverlayChannel() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& method_name = call.method_name();
        const EncodableValue* args = call.arguments();

        if (method_name == "setHitRects") {
          OverlayState::Instance().SetHitRects(ParseRegions(args));
          result->Success();
          return;
        }
        if (method_name == "setUiRects") {
          OverlayState::Instance().SetUiRects(ParseRegions(args));
          result->Success();
          return;
        }
        if (method_name == "setClickThrough") {
          int mode = -1;
          if (args) {
            if (const auto* map = std::get_if<EncodableMap>(args)) {
              auto it = map->find(EncodableValue("enabled"));
              if (it != map->end()) {
                if (const auto* flag = std::get_if<bool>(&it->second)) {
                  mode = *flag ? 1 : 0;
                } else if (it->second.IsNull()) {
                  mode = -1;
                }
              }
            }
          }
          OverlayState::Instance().SetClickThrough(mode);
          // WS_EX_LAYERED without attributes never displays content, so the
          // layered style is only applied while fully click-through.
          HWND hwnd = GetHandle();
          LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
          if (mode == 1) {
            ex_style |= WS_EX_LAYERED | WS_EX_TRANSPARENT;
            SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
            SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
          } else {
            ex_style &= ~(WS_EX_LAYERED | WS_EX_TRANSPARENT);
            SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
          }
          result->Success();
          return;
        }
        if (method_name == "setWindowBounds") {
          if (args) {
            if (const auto* map = std::get_if<EncodableMap>(args)) {
              auto get_int = [map](const char* key) -> int {
                auto it = map->find(EncodableValue(key));
                if (it == map->end()) {
                  return 0;
                }
                if (const auto* v = std::get_if<int32_t>(&it->second)) {
                  return *v;
                }
                if (const auto* v = std::get_if<int64_t>(&it->second)) {
                  return static_cast<int>(*v);
                }
                return 0;
              };
              const int x = get_int("x");
              const int y = get_int("y");
              const int w = get_int("w");
              const int h = get_int("h");
              HWND hwnd = GetHandle();
              SetWindowLongPtr(hwnd, GWL_STYLE,
                               GetWindowLongPtr(hwnd, GWL_STYLE) | WS_POPUP);
              SetWindowPos(hwnd, nullptr, x, y, w, h,
                           SWP_NOACTIVATE | SWP_FRAMECHANGED);
            }
          }
          result->Success();
          return;
        }
        if (method_name == "setTopmost") {
          bool topmost = true;
          if (args) {
            if (const auto* map = std::get_if<EncodableMap>(args)) {
              auto it = map->find(EncodableValue("topmost"));
              if (it != map->end()) {
                if (const auto* flag = std::get_if<bool>(&it->second)) {
                  topmost = *flag;
                }
              }
            }
          }
          // Tool window: hidden from the taskbar and Alt+Tab; NOACTIVATE
          // prevents stealing focus; LAYERED enables WS_EX_TRANSPARENT
          // toggling for click-through.
          LONG_PTR ex_style = GetWindowLongPtr(GetHandle(), GWL_EXSTYLE);
          ex_style |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED |
                      WS_EX_TOPMOST;
          SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, ex_style);
          SetWindowPos(GetHandle(), topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0,
                       0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                           SWP_FRAMECHANGED);
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::OnDestroy() {
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
    case WM_ERASEBKGND:
      // Keep the overlay flicker-free; the color key handles transparency.
      return 1;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
