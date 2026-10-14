#pragma once

#include "Geometry.hpp"
#include <cmath>

namespace minfwm::core {

// Only an observed user drag may change the canvas that owns a window.
[[nodiscard]] inline bool shouldTransferWindow(bool windowDragged, bool cameraUnchanged,
                                                Rect start, Rect end, std::int64_t sourceDisplay,
                                                std::int64_t targetDisplay) noexcept {
    return windowDragged && cameraUnchanged && sourceDisplay != targetDisplay &&
        std::isfinite(start.x) && std::isfinite(start.y) &&
        std::isfinite(end.x) && std::isfinite(end.y) &&
        (std::abs(end.x - start.x) > 1.0f || std::abs(end.y - start.y) > 1.0f);
}

[[nodiscard]] inline bool frameFitsDisplay(Rect frame, Rect bounds) noexcept {
    return std::isfinite(frame.x) && std::isfinite(frame.y) &&
        std::isfinite(frame.right()) && std::isfinite(frame.bottom()) &&
        frame.x >= bounds.x && frame.y >= bounds.y &&
        frame.right() <= bounds.right() && frame.bottom() <= bounds.bottom();
}

} // namespace minfwm::core
