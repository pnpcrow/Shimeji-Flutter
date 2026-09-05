#ifndef RUNNER_OVERLAY_STATE_H_
#define RUNNER_OVERLAY_STATE_H_

#include <cstdint>
#include <vector>

// Shared overlay input state, driven from Dart through the "shimeji/overlay"
// MethodChannel and consumed by WM_NCHITTEST handling.
//
// The overlay window covers the entire virtual desktop. Mouse events must
// pass through to the applications beneath wherever no mascot (or UI region)
// sits, so the runner hit-tests the cursor against per-mascot rectangles
// refined by a coarse alpha mask (8x8-pixel cells, packed as bits).
class OverlayState {
 public:
  static OverlayState& Instance();

  struct Region {
    int32_t x = 0;
    int32_t y = 0;
    int32_t w = 0;
    int32_t h = 0;
    // Alpha mask (optional): cols*rows cells of `cell` pixels each.
    int32_t cols = 0;
    int32_t rows = 0;
    int32_t cell = 0;
    std::vector<uint32_t> mask;  // bit per cell, row-major
  };

  // mode: -1 = auto (per-region hit testing), 0 = accept all input,
  // 1 = pass everything through.
  void SetHitRects(std::vector<Region> rects);
  void SetUiRects(std::vector<Region> rects);
  void SetClickThrough(int mode);

  int click_through_mode() const { return click_through_mode_; }

  // Returns true when the physical point (in window-local coordinates)
  // should be treated as part of the overlay (mascots or UI).
  bool HitsMascot(int32_t x, int32_t y) const;
  bool HitsUi(int32_t x, int32_t y) const;

 private:
  OverlayState() = default;

  static bool RegionContains(const Region& r, int32_t x, int32_t y);
  static bool MaskHits(const Region& r, int32_t local_x, int32_t local_y);

  std::vector<Region> hit_rects_;
  std::vector<Region> ui_rects_;
  int click_through_mode_ = -1;
};

#endif  // RUNNER_OVERLAY_STATE_H_
