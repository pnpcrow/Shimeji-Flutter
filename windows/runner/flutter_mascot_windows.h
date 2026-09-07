#ifndef RUNNER_FLUTTER_MASCOT_WINDOWS_H_
#define RUNNER_FLUTTER_MASCOT_WINDOWS_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

// Per-mascot native windows of the "flutter" renderer mode.
//
// Like the legacy mode every mascot owns its own top-level window, so
// mascots stay separate desktop objects whose geometry is applied in
// physical screen coordinates (they can move across monitors; no
// fullscreen overlay is involved). Instead of UpdateLayeredWindow bitmaps,
// each window hosts a dedicated Flutter engine painting the current pose:
// transparency comes from a borderless window with the DWM glass frame
// extended across the client area, and per-pixel click-through is kept by
// hit testing the cached pose alpha in WM_NCHITTEST -- transparent pixels
// pass clicks through and opaque pixels swallow them, mirroring the legacy
// layered windows. (Input for the shimeji engine itself is still polled
// globally by the main engine, exactly like the legacy mode.)
class FlutterMascotWindows {
 public:
  static FlutterMascotWindows& Instance();

  // Creates the borderless topmost window and boots its Flutter engine
  // with the 'mascot_window' entrypoint arguments. The window stays hidden
  // until the first Update.
  void Create(int id);

  // Moves/resizes the window to physical screen (x, y, w, h). When |rgba|
  // is non-null the pose changed: it is cached (hit testing + late delivery
  // to engines that finish booting after the window exists) and forwarded
  // to the engine for painting. Returns false when the window is unknown.
  bool Update(int id, int x, int y, int w, int h,
              const std::vector<uint8_t>* rgba, bool flipped, double opacity,
              int64_t hash);

  void Destroy(int id);
  void DestroyAll();

 private:
  struct MascotWindow {
    HWND hwnd = nullptr;
    HWND flutter_hwnd = nullptr;
    std::unique_ptr<flutter::FlutterViewController> controller;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
    // Last pose (straight RGBA, unflipped) for hit testing and re-delivery.
    std::vector<uint8_t> rgba;
    int pose_w = 0;
    int pose_h = 0;
    bool flipped = false;
    double opacity = 1.0;
    int64_t hash = 0;
    bool engine_ready = false;  // engine installed its channel handler
  };

  FlutterMascotWindows() = default;

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  static void EnsureClass();

  void SendPose(MascotWindow& window);

  std::map<int, std::unique_ptr<MascotWindow>> windows_;
};

#endif  // RUNNER_FLUTTER_MASCOT_WINDOWS_H_
