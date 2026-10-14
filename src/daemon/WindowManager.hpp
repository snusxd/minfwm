#pragma once

#import <AppKit/AppKit.h>
#include <memory>
#include <vector>
#include <map>
#include <set>
#include "Camera.hpp"
#include "WindowPool.hpp"
#include "../core/DisplayState.hpp"
#include "AXBackend.hpp"
#include "YabaiSA.hpp"
#include "WindowRenderer.hpp"

namespace minfwm {

class Display {
public:
    Display(int64_t displayId, core::Rect bounds, WindowPool::WindowIdResolver windowIdResolver = nullptr,
            std::optional<core::Rect> usableBounds = {})
        : m_id(displayId), m_state(core::DisplayGeometry{displayId, bounds}), m_usableBounds(usableBounds.value_or(bounds)) {
        m_windowPool = std::make_unique<WindowPool>(windowIdResolver);
    }

    int64_t id() const { return m_id; }
    Camera& camera() { return m_state.camera(); }
    const core::DisplayState& state() const { return m_state; }
    core::DisplayState& state() { return m_state; }
    WindowPool& windowPool() { return *m_windowPool; }
    core::Rect usableBounds() const { return m_usableBounds; }

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
    core::Rect m_usableBounds;
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
    Display& displayForPoint(core::Point point);
    Display* displayById(int64_t id);
    Display& displayForWindow(AXUIElementRef window);
    
    void updateWindows(int64_t displayId = 0);
    void adoptWindow(Display& display, const std::shared_ptr<ClientWindow>& window);
    void centerWindow(std::shared_ptr<ClientWindow> window);
    bool toggleFocusedWindowPin();
    void centerCameraOnWindow(AXUIElementRef element);
    void syncPhysicalToVirtual(AXUIElementRef element);
    void beginNativeInteraction(core::Point pointer);
    void endNativeInteraction();
    void flushNativeInteractionForPan();
    bool requestOverviewZoom(core::Point pointer, float delta);
    bool overviewActive() const;
    bool overviewReturning() const;
    void exitOverview(core::Point pointer, bool selectWindow);

    // Helpers to find window across pools
    std::shared_ptr<ClientWindow> findWindow(AXUIElementRef element);
    void removeWindow(AXUIElementRef element);
    void removeWindowsForPid(pid_t pid);
    void setApplicationState(pid_t pid, std::string name, bool hidden);
    void reconcileApplicationWindows(pid_t pid, const std::vector<AXUIElementRef>& liveWindows);

    bool isPanning() const { return m_isPanning; }
    void setPanning(bool panning) { m_isPanning = panning; }

private:
    WindowManager() = default;

    NSScreen* screenForDisplay(int64_t displayId) const;
    float axTopOriginForScreen(NSScreen* screen) const;
    bool isWhitelisted(const ClientWindow& window) const;
    void commitNativeInteraction();
    void refreshWindowSnapshot(double now);
    void addNativeCandidate(const std::shared_ptr<ClientWindow>& window);
    std::shared_ptr<ClientWindow> windowAtPoint(core::Point pointer) const;
    void applyOverviewExit();

    std::vector<std::unique_ptr<Display>> m_displays;
    bool m_isPanning = false;
    bool m_initialized = false;
    CFRef<AXUIElementRef> m_focusedWindow;
    double m_focusRefreshTime = 0;
    double m_windowRefreshTime = 0;
    bool m_nativePointerHeld = false;
    bool m_nativeCommitPending = false;
    double m_nativeCommitTime = 0;
    std::map<int64_t, core::Point> m_nativeCameras;
    std::vector<std::shared_ptr<ClientWindow>> m_nativeCandidates;
    struct ZoomRequest { int64_t displayId; core::Point anchor; float delta; };
    std::optional<ZoomRequest> m_zoomRequest;
    struct OverviewExit { core::Point pointer; bool selectWindow; };
    std::optional<OverviewExit> m_overviewExit;
    std::map<int64_t, double> m_zoomFrameTimes;
    std::shared_ptr<ClientWindow> m_overviewFocus;
    std::weak_ptr<ClientWindow> m_lastFocusedWindow;
    std::map<pid_t, std::string> m_applicationNames;
    std::set<pid_t> m_hiddenApplications;
    std::optional<std::unordered_set<uint32_t>> m_onscreenWindows;
    AXBackend m_axBackend;
    YabaiSABackend m_yabaiBackend;
    WindowRenderer m_renderer{m_axBackend, m_yabaiBackend};
};

} // namespace minfwm
