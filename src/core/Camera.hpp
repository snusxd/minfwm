#pragma once

#include "Geometry.hpp"

namespace minfwm::core {

class Camera final {
public:
    Camera() noexcept;
    Camera(float x, float y) noexcept;

    void move(float dx, float dy) noexcept;
    void move(Point delta) noexcept;
    void setPosition(float x, float y) noexcept;

    [[nodiscard]] float x() const noexcept;
    [[nodiscard]] float y() const noexcept;
    [[nodiscard]] Point position() const noexcept;

private:
    float m_x;
    float m_y;
};

} // namespace minfwm::core
