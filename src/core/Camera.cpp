#include "Camera.hpp"
#include <cmath>

namespace minfwm::core {

Camera::Camera() noexcept : Camera(0.0f, 0.0f) {}

Camera::Camera(float x, float y) noexcept : m_x(0), m_y(0) {
    (void)setPosition(x, y);
}

bool Camera::move(float dx, float dy) noexcept {
    return setPosition(m_x + dx, m_y + dy);
}

bool Camera::move(Point delta) noexcept {
    return move(delta.x, delta.y);
}

bool Camera::setPosition(float x, float y) noexcept {
    if (!std::isfinite(x) || !std::isfinite(y)) return false;
    m_x = x;
    m_y = y;
    return true;
}

float Camera::x() const noexcept {
    return m_x;
}

float Camera::y() const noexcept {
    return m_y;
}

Point Camera::position() const noexcept {
    return { m_x, m_y };
}

} // namespace minfwm::core
