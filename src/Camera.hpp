#pragma once

#include <algorithm>

class Camera
{
public:
    Camera() = default;
    ~Camera() = default;

    void Pan(double dx, double dy);
    void Zoom(double delta, double centerX, double centerY);

    double GetX() const { return m_x; }
    double GetY() const { return m_y; }
    double GetScale() const { return m_scale; }

    void SetPosition(double x, double y) { m_x = x; m_y = y; }
    void SetScale(double scale) { m_scale = std::max(0.1, std::min(scale, 5.0)); }

    // Coordinate conversions
    void WorldToScreen(double worldX, double worldY, int32_t& screenX, int32_t& screenY) const;
    void ScreenToWorld(double screenX, double screenY, double& worldX, double& worldY) const;

private:
    double m_x = 0.0;
    double m_y = 0.0;
    double m_scale = 1.0;
};
