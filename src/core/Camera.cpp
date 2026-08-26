#include "Camera.hpp"

namespace minfwm::core {

Camera::Camera() noexcept : Camera(0.0f, 0.0f) {}

Camera::Camera(float x, float y) noexcept : m_x(x), m_y(y) {}

void Camera::move(float dx, float dy) noexcept {
    m_x += dx;
    m_y += dy;
}

void Camera::move(Point delta) noexcept {
    move(delta.x, delta.y);
}

void Camera::setPosition(float x, float y) noexcept {
    m_x = x;
    m_y = y;
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
