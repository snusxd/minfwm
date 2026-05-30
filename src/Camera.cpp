#include "Camera.hpp"
#include <algorithm>
#include <iostream>

void Camera::Pan(double dx, double dy)
{
  m_x -= dx / m_scale;
  m_y -= dy / m_scale;
}

void Camera::Zoom(double delta, double centerX, double centerY)
{
  double oldScale = m_scale;
  m_scale += delta * 0.02 * m_scale;
  m_scale = std::max(0.1, std::min(m_scale, 5.0));

  if (oldScale != m_scale)
  {
    m_x += centerX * (1.0 / oldScale - 1.0 / m_scale);
    m_y += centerY * (1.0 / oldScale - 1.0 / m_scale);

    std::cout << "[Camera] scale: " << oldScale << " -> " << m_scale
              << " position: (" << m_x << "," << m_y << ")" << std::endl;
  }
}

void Camera::WorldToScreen(double worldX, double worldY, int32_t &screenX,
                           int32_t &screenY) const
{
  screenX = static_cast<int32_t>((worldX - m_x) * m_scale);
  screenY = static_cast<int32_t>((worldY - m_y) * m_scale);
}

void Camera::ScreenToWorld(double screenX, double screenY, double &worldX,
                           double &worldY) const
{
  worldX = screenX / m_scale + m_x;
  worldY = screenY / m_scale + m_y;
}
