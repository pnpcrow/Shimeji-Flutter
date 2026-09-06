#ifndef RUNNER_MASCOT_WINDOWS_H_
#define RUNNER_MASCOT_WINDOWS_H_

#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

// Per-mascot top-level layered windows, mirroring the Java original's
// per-mascot translucent JWindow. Each window presents one sprite through
// UpdateLayeredWindow, giving true per-pixel alpha: fully transparent pixels
// are invisible AND click-through at the DWM level, which works on every
// session type (including remote desktop) unlike accent-based transparency.
class MascotWindows {
 public:
  struct MenuItem {
    std::wstring label;
    std::string id;  // stable identifier echoed back on selection
    bool checked = false;
    bool separator = false;
    int native_command_id = 0;  // assigned during menu construction
    // When set, this item opens a nested popup containing |children|.
    std::shared_ptr<std::vector<MenuItem>> children;
  };

  static MascotWindows& Instance();

  void Create(int id);
  // Presents a premultiplied BGRA bitmap (top-down, exactly w*h*4 bytes) with
  // its top-left corner at the physical screen position (x, y).
  bool Update(int id, int x, int y, int w, int h, const uint8_t* bgra,
              size_t byte_count);
  void Destroy(int id);
  void DestroyAll();
  bool Exists(int id) const;

  // Shows a popup menu at physical screen (x, y) and returns the |id| of the
  // selected item, or an empty string when dismissed. Items with |checked|
  // show a checkmark; |separator| items render as separators. Nested
  // |children| become submenus.
  std::wstring ShowContextMenu(int id, int x, int y,
                               std::vector<MenuItem>& items);

 private:
  MascotWindows() = default;

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  void EnsureClass();

  // Recursively appends |items| to |menu|, assigning sequential command ids
  // and recording them in each item's native_command_id.
  void AppendItems(HMENU menu, std::vector<MenuItem>& items,
                   int* next_command_id);

  std::map<int, HWND> windows_;
};

#endif  // RUNNER_MASCOT_WINDOWS_H_
