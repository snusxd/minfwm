#pragma once

#include "Geometry.hpp"

namespace minfwm::core {

class Camera final {
public:
    Camera() noexcept;
    Camera(float x, float y) noexcept;

    // Invalid or overflowing updates leave both coordinates unchanged.
    bool move(float dx, float dy) noexcept;
    bool move(Point delta) noexcept;
    bool setPosition(float x, float y) noexcept;

    [[nodiscard]] float x() const noexcept;
    [[nodiscard]] float y() const noexcept;
    [[nodiscard]] Point position() const noexcept;

private:
    float m_x;
    float m_y;
};

} // namespace minfwm::core
