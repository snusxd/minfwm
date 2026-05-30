#pragma once

#include "Camera.hpp"
#include "DisplayManager.hpp"
#include "ILayout.hpp"
#include "WindowPool.hpp"
#include <chrono>
#include <memory>
#include <sys/types.h>

class WindowManager
{
public:
  static WindowManager &GetInstance()
  {
    static WindowManager instance;
    return instance;
  }

  void Initialize();

  // Delegates to components
  void Pan(double dx, double dy);
  void Zoom(double delta, double centerX, double centerY);
  void UpdateWindowPositions();
  void ForceUpdate();

  void ApplyCurrentLayout();
  void ScheduleLayout();

  void UpdateAbsolutePosition(AXUIElementRef windowRef);
  bool IsPanning() const { return m_isPanning; }
  bool IsZooming() const { return m_isZooming; }
  bool IsInitializing() const { return m_isInitializing; }
  void SetInitializing(bool val) { m_isInitializing = val; }

  Camera &GetCamera() { return m_camera; }
  WindowPool &GetWindowPool() { return m_windowPool; }
  DisplayManager &GetDisplayManager() { return m_displayManager; }

private:
  WindowManager() = default;
  ~WindowManager() = default;

  // Prevent copying
  WindowManager(const WindowManager &) = delete;
  WindowManager &operator=(const WindowManager &) = delete;

  void ScheduleUpdate();

  Camera m_camera;
  WindowPool m_windowPool;
  DisplayManager m_displayManager;

  std::unique_ptr<ILayout> m_currentLayout;

  std::chrono::steady_clock::time_point m_lastLayoutTime;
  bool m_layoutPending = false;

  bool m_updatePending = false;
  bool m_isPanning = false;
  bool m_isZooming = false;
  bool m_isUpdating = false;
  bool m_isInitializing = false;
};
