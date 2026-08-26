#pragma once

#import <AppKit/AppKit.h>
#include <memory>
#include <vector>
#include <map>
#include "Camera.hpp"
#include "WindowPool.hpp"
#include "../core/DisplayState.hpp"
#include "AXBackend.hpp"
#include "YabaiSA.hpp"

namespace minfwm {

class Display {
public:
    Display(int64_t displayId, core::Rect bounds, WindowPool::WindowIdResolver windowIdResolver = nullptr)
        : m_id(displayId), m_state(core::DisplayGeometry{displayId, bounds}) {
        m_windowPool = std::make_unique<WindowPool>(windowIdResolver);
    }

    int64_t id() const { return m_id; }
    Camera& camera() { return m_state.camera(); }
    const core::DisplayState& state() const { return m_state; }
    core::DisplayState& state() { return m_state; }
    WindowPool& windowPool() { return *m_windowPool; }

    void saveBookmark(int index) {
        m_state.saveBookmark(index);
    }

    void loadBookmark(int index) {
        (void)m_state.loadBookmark(index);
    }

private:
    int64_t m_id;
    core::DisplayState m_state;
    std::unique_ptr<WindowPool> m_windowPool;
};

class WindowManager {
public:
    static WindowManager& instance() {
        static WindowManager instance;
        return instance;
    }

    bool initialize();
    void shutdown();
    
    // Get display for a window or camera
    Display& mainDisplay();
    Display& displayForWindow(AXUIElementRef window);
    
    void updateWindows();
    void adoptWindow(Display& display, const std::shared_ptr<ClientWindow>& window);
    void centerWindow(std::shared_ptr<ClientWindow> window);
    void centerCameraOnWindow(AXUIElementRef element);
    void syncPhysicalToVirtual(AXUIElementRef element);

    // Helpers to find window across pools
    std::shared_ptr<ClientWindow> findWindow(AXUIElementRef element);
    void removeWindow(AXUIElementRef element);

    bool isPanning() const { return m_isPanning; }
    void setPanning(bool panning) { m_isPanning = panning; }

private:
    WindowManager() = default;

    NSScreen* screenForDisplay(int64_t displayId) const;
    float axTopOriginForScreen(NSScreen* screen) const;
    bool isWhitelisted(AXUIElementRef element) const;

    std::vector<std::unique_ptr<Display>> m_displays;
    bool m_isPanning = false;
    bool m_initialized = false;
    AXBackend m_axBackend;
    YabaiSABackend m_yabaiBackend;
};

} // namespace minfwm
