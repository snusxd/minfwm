#pragma once

#include <cstdint>

namespace minfwm::core {

struct Point {
    float x = 0.0f;
    float y = 0.0f;
};

struct Size {
    float width = 0.0f;
    float height = 0.0f;
};

struct Rect {
    float x = 0.0f;
    float y = 0.0f;
    float w = 0.0f;
    float h = 0.0f;

    [[nodiscard]] constexpr float left() const noexcept { return x; }
    [[nodiscard]] constexpr float top() const noexcept { return y; }
    [[nodiscard]] constexpr float right() const noexcept { return x + w; }
    [[nodiscard]] constexpr float bottom() const noexcept { return y + h; }

    [[nodiscard]] Rect expanded(float amount) const noexcept;
    [[nodiscard]] Rect translated(Point delta) const noexcept;
    [[nodiscard]] bool intersects(const Rect& other) const noexcept;
};

struct DisplayGeometry {
    std::int64_t id = 0;
    Rect bounds;
};

} // namespace minfwm::core

namespace minfwm {

// Compatibility alias for the existing Objective-C++ adapter surface.
using VirtualRect = core::Rect;

} // namespace minfwm
