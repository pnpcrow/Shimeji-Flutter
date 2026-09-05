#include "overlay_state.h"

OverlayState& OverlayState::Instance() {
  static OverlayState instance;
  return instance;
}

void OverlayState::SetHitRects(std::vector<Region> rects) {
  hit_rects_ = std::move(rects);
}

void OverlayState::SetUiRects(std::vector<Region> rects) {
  ui_rects_ = std::move(rects);
}

void OverlayState::SetClickThrough(int mode) {
  click_through_mode_ = mode;
}

bool OverlayState::RegionContains(const Region& r, int32_t x, int32_t y) {
  return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
}

bool OverlayState::MaskHits(const Region& r, int32_t local_x, int32_t local_y) {
  if (r.mask.empty() || r.cell <= 0 || r.cols <= 0 || r.rows <= 0) {
    return true;
  }
  const int32_t col = local_x / r.cell;
  const int32_t row = local_y / r.cell;
  if (col < 0 || col >= r.cols || row < 0 || row >= r.rows) {
    return false;
  }
  const int32_t index = row * r.cols + col;
  const int32_t word = index / 32;
  const int32_t bit = index % 32;
  if (word < 0 || word >= static_cast<int32_t>(r.mask.size())) {
    return false;
  }
  return (r.mask[word] >> bit) & 1u;
}

bool OverlayState::HitsMascot(int32_t x, int32_t y) const {
  for (const Region& r : hit_rects_) {
    if (RegionContains(r, x, y) && MaskHits(r, x - r.x, y - r.y)) {
      return true;
    }
  }
  return false;
}

bool OverlayState::HitsUi(int32_t x, int32_t y) const {
  for (const Region& r : ui_rects_) {
    if (RegionContains(r, x, y)) {
      return true;
    }
  }
  return false;
}
