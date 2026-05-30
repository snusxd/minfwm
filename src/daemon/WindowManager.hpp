#pragma once

#include <memory>
#include <vector>
#include <map>
#include "Camera.hpp"
#include "WindowPool.hpp"

namespace minfwm {

class Display {
public:
    Display(int64_t displayId) : m_id(displayId) {
        m_camera = std::make_unique<Camera>();
        m_windowPool = std::make_unique<WindowPool>();
    }

    int64_t id() const { return m_id; }
    Camera& camera() { return *m_camera; }
    WindowPool& windowPool() { return *m_windowPool; }

    void saveBookmark(int index) {
        m_bookmarks[index] = { m_camera->x(), m_camera->y() };
    }

    void loadBookmark(int index) {
        if (m_bookmarks.count(index)) {
            auto pos = m_bookmarks[index];
            m_camera->setPosition(pos.x, pos.y);
        }
    }

private:
    int64_t m_id;
    std::unique_ptr<Camera> m_camera;
    std::unique_ptr<WindowPool> m_windowPool;
    std::map<int, CGPoint> m_bookmarks;
};

class WindowManager {
public:
    static WindowManager& instance() {
        static WindowManager instance;
        return instance;
    }

    void initialize();
    
    // Get display for a window or camera
    Display& mainDisplay() { return *m_displays[0]; }
    Display& displayForWindow(AXUIElementRef window);
    
    void updateWindows();
    void centerWindow(std::shared_ptr<ClientWindow> window);
    void centerCameraOnWindow(AXUIElementRef element);
    void syncPhysicalToVirtual(AXUIElementRef element);

    // Helpers to find window across pools
    std::shared_ptr<ClientWindow> findWindow(AXUIElementRef element);
    void removeWindow(AXUIElementRef element);

private:
    WindowManager() = default;
    
    std::vector<std::unique_ptr<Display>> m_displays;
};

} // namespace minfwm
