#pragma once

namespace minfwm {

class Camera {
public:
    Camera() : m_x(0), m_y(0) {}

    void move(float dx, float dy) {
        m_x += dx;
        m_y += dy;
    }

    void setPosition(float x, float y) {
        m_x = x;
        m_y = y;
    }

    float x() const { return m_x; }
    float y() const { return m_y; }

private:
    float m_x;
    float m_y;
};

} // namespace minfwm
