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
    bool checked = false;
    bool separator = false;
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

  // Shows a popup menu at physical screen (x, y) and returns the selected
  // item index, or -1 when dismissed. Items with |checked| show a checkmark;
  // |separator| items render as separators.
  int ShowContextMenu(int id, int x, int y,
                      const std::vector<MenuItem>& items);

 private:
  MascotWindows() = default;

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  void EnsureClass();

  // Recursively appends |items| to |menu|. Selectable entries get sequential
  // command ids so the returned id maps back to a flat index.
  void AppendItems(HMENU menu, const std::vector<MenuItem>& items,
                   int* next_command_id);

  std::map<int, HWND> windows_;
};

#endif  // RUNNER_MASCOT_WINDOWS_H_
