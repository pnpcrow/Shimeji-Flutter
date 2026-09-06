#include "mascot_windows.h"

#include <windowsx.h>

#include <vector>

namespace {

constexpr wchar_t kMascotClassName[] = L"SHIMEJI_MASCOT_WINDOW";

bool g_class_registered = false;

}  // namespace

MascotWindows& MascotWindows::Instance() {
  static MascotWindows instance;
  return instance;
}

void MascotWindows::EnsureClass() {
  if (g_class_registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.lpfnWndProc = MascotWindows::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kMascotClassName;
  window_class.hbrBackground = nullptr;
  RegisterClass(&window_class);
  g_class_registered = true;
}

LRESULT CALLBACK MascotWindows::WndProc(HWND window, UINT message,
                                        WPARAM wparam, LPARAM lparam) {
  // The sprites are presented with UpdateLayeredWindow; hit testing against
  // per-pixel alpha is performed by the system, so only default handling is
  // required here.
  return DefWindowProc(window, message, wparam, lparam);
}

void MascotWindows::Create(int id) {
  if (windows_.count(id) != 0) {
    return;
  }
  EnsureClass();
  HWND window = CreateWindowEx(
      WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_LAYERED,
      kMascotClassName, L"shimeji", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr,
      GetModuleHandle(nullptr), nullptr);
  if (!window) {
    return;
  }
  windows_[id] = window;
}

bool MascotWindows::Update(int id, int x, int y, int w, int h,
                           const uint8_t* bgra, size_t byte_count) {
  auto it = windows_.find(id);
  if (it == windows_.end() || w <= 0 || h <= 0) {
    return false;
  }
  if (byte_count < static_cast<size_t>(w) * static_cast<size_t>(h) * 4) {
    return false;
  }
  HWND window = it->second;

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = w;
  bitmap_info.bmiHeader.biHeight = -h;  // top-down
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HDC screen_dc = GetDC(window);
  HDC memory_dc = CreateCompatibleDC(screen_dc);
  HBITMAP bitmap = CreateDIBSection(memory_dc, &bitmap_info, DIB_RGB_COLORS,
                                    &bits, nullptr, 0);
  bool presented = false;
  if (bitmap && bits) {
    memcpy(bits, bgra, static_cast<size_t>(w) * static_cast<size_t>(h) * 4);
    HGDIOBJ old = SelectObject(memory_dc, bitmap);

    SIZE size = {w, h};
    POINT destination = {x, y};
    POINT source = {0, 0};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    presented = UpdateLayeredWindow(window, screen_dc, &destination, &size,
                                    memory_dc, &source, 0, &blend,
                                    ULW_ALPHA) != 0;
    if (presented && !IsWindowVisible(window)) {
      ShowWindow(window, SW_SHOWNA);
    }
    SelectObject(memory_dc, old);
  }
  if (bitmap) {
    DeleteObject(bitmap);
  }
  DeleteDC(memory_dc);
  ReleaseDC(window, screen_dc);
  return presented;
}

void MascotWindows::Destroy(int id) {
  auto it = windows_.find(id);
  if (it == windows_.end()) {
    return;
  }
  DestroyWindow(it->second);
  windows_.erase(it);
}

void MascotWindows::DestroyAll() {
  for (auto& entry : windows_) {
    DestroyWindow(entry.second);
  }
  windows_.clear();
}

bool MascotWindows::Exists(int id) const { return windows_.count(id) != 0; }

HWND EnsureMenuHelperWindow() {
  static HWND helper = nullptr;
  if (helper == nullptr || !IsWindow(helper)) {
    // A plain activatable window: the menu owner must be able to take the
    // foreground, which the WS_EX_NOACTIVATE mascot windows cannot. It sits
    // off-screen at 1x1 so it is visible to the system but never seen.
    helper = CreateWindowEx(WS_EX_TOOLWINDOW, L"STATIC",
                            L"shimeji_menu_helper", WS_POPUP, -32000, -32000,
                            1, 1, nullptr, nullptr, GetModuleHandle(nullptr),
                            nullptr);
    ShowWindow(helper, SW_SHOWNOACTIVATE);
  }
  return helper;
}

int MascotWindows::ShowContextMenu(int id, int x, int y,
                                   const std::vector<MenuItem>& items) {
  auto it = windows_.find(id);
  if (it == windows_.end()) {
    return -1;
  }
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return -1;
  }
  int command_id = 1;
  for (const MenuItem& item : items) {
    if (item.separator) {
      AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
    } else {
      UINT flags = MF_STRING | (item.checked ? MF_CHECKED : 0);
      AppendMenu(menu, flags, command_id, item.label.c_str());
      command_id++;
    }
  }

  // TPM_RETURNCMD returns the chosen command id instead of posting
  // WM_COMMAND; TPM_NOACTIVATE keeps the mascot from stealing focus.
#ifndef TPM_NOACTIVATE
#define TPM_NOACTIVATE 0x0100L
#endif
  // The mascot window is WS_EX_NOACTIVATE, so it can never take the
  // foreground itself and a menu owned by it would close instantly. Attach
  // to the foreground thread, move the foreground to a plain helper window,
  // and run the menu owned by that helper.
  HWND helper = EnsureMenuHelperWindow();
  HWND foreground = GetForegroundWindow();
  DWORD foreground_thread =
      foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
  DWORD this_thread = GetCurrentThreadId();
  if (foreground_thread != 0 && foreground_thread != this_thread) {
    AttachThreadInput(this_thread, foreground_thread, TRUE);
  }
  SetForegroundWindow(helper);
  SetActiveWindow(helper);
  int selected = TrackPopupMenuEx(menu,
                                  TPM_RETURNCMD | TPM_RIGHTBUTTON |
                                      TPM_NONOTIFY,
                                  x, y, helper, nullptr);
  if (foreground != nullptr && foreground_thread != 0 &&
      foreground_thread != this_thread) {
    AttachThreadInput(this_thread, foreground_thread, FALSE);
    // Hand the foreground back so the user's application keeps focus.
    SetForegroundWindow(foreground);
  }
  DestroyMenu(menu);

  if (selected == 0) {
    return -1;
  }
  // Map the command id back to the index in the original item list (separators
  // are not selectable, so command ids only count selectable items).
  int selectable_index = -1;
  int current_id = 1;
  for (size_t i = 0; i < items.size(); i++) {
    if (items[i].separator) {
      continue;
    }
    if (current_id == selected) {
      selectable_index = static_cast<int>(i);
      break;
    }
    current_id++;
  }
  return selectable_index;
}
