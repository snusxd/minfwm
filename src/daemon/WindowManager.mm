#include "WindowManager.hpp"
#include "CFRAII.hpp"
#include "ConfigManager.hpp"
#include "YabaiSA.hpp"
#include "../core/Visibility.hpp"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <algorithm>
#include <cstdlib>

namespace minfwm {

namespace {

bool readAXPoint(AXUIElementRef element, CGPoint& point) {
    CFRef<CFTypeRef> value;
    if (!element || AXUIElementCopyAttributeValue(element, kAXPositionAttribute, value.put()) != kAXErrorSuccess) {
        return false;
    }
    return value && CFGetTypeID(value.get()) == AXValueGetTypeID() &&
           AXValueGetType(static_cast<AXValueRef>(value.get())) == kAXValueTypeCGPoint &&
           AXValueGetValue(static_cast<AXValueRef>(value.get()), kAXValueTypeCGPoint, &point);
}

bool readAXSize(AXUIElementRef element, CGSize& size) {
    CFRef<CFTypeRef> value;
    if (!element || AXUIElementCopyAttributeValue(element, kAXSizeAttribute, value.put()) != kAXErrorSuccess) {
        return false;
    }
    return value && CFGetTypeID(value.get()) == AXValueGetTypeID() &&
           AXValueGetType(static_cast<AXValueRef>(value.get())) == kAXValueTypeCGSize &&
           AXValueGetValue(static_cast<AXValueRef>(value.get()), kAXValueTypeCGSize, &size);
}

} // namespace

bool WindowManager::initialize() {
    if (m_initialized) return true;

    std::cout << "WindowManager: Initializing public AX backend" << std::endl;
    ConfigManager::instance().load();
    m_displays.clear();
    const bool yabaiAvailable = m_yabaiBackend.initialize();

    for (NSScreen* screen in [NSScreen screens]) {
        NSDictionary* description = [screen deviceDescription];
        NSNumber* displayID = [description objectForKey:@"NSScreenNumber"];
        if (!displayID) continue;

        const float topOrigin = axTopOriginForScreen(screen);
        const NSRect frame = [screen frame];
        const core::Rect bounds{
            static_cast<float>(frame.origin.x),
            topOrigin,
            static_cast<float>(frame.size.width),
            static_cast<float>(frame.size.height),
        };
        const int64_t id = [displayID longLongValue];
        const NSRect usable = [screen visibleFrame];
        const core::Rect usableBounds{static_cast<float>(usable.origin.x),
            topOrigin + static_cast<float>(NSMaxY(frame) - NSMaxY(usable)),
            static_cast<float>(usable.size.width), static_cast<float>(usable.size.height)};
        m_displays.push_back(std::make_unique<Display>(
            id, bounds, yabaiAvailable ? WindowPool::optionalWindowIdResolver() : nullptr, usableBounds));
        std::cout << "WindowManager: Found display " << id << " ["
                  << frame.size.width << "x" << frame.size.height << "]" << std::endl;
    }

    if (m_displays.empty()) {
        std::cerr << "WindowManager: no displays available" << std::endl;
        return false;
    }

    if (yabaiAvailable) {
        std::cout << "WindowManager: Yabai SA backend enabled" << std::endl;
        std::cout << "WindowManager: absolute transforms "
                  << (m_yabaiBackend.usesTransforms() ? "enabled" : "unavailable") << std::endl;
    } else {
        std::cout << "WindowManager: Yabai SA unavailable; using AX fallback" << std::endl;
    }
    m_initialized = true;
    return true;
}

Display& WindowManager::mainDisplay() {
    if (m_displays.empty()) {
        throw std::runtime_error("WindowManager: no display is initialized");
    }
    return *m_displays.front();
}

Display* WindowManager::displayById(int64_t id) {
    for (auto& display : m_displays) {
        if (display->id() == id) return display.get();
    }
    return nullptr;
}

Display& WindowManager::displayForPoint(core::Point point) {
    std::vector<core::DisplayGeometry> geometry;
    geometry.reserve(m_displays.size());
    for (const auto& display : m_displays) geometry.push_back(display->state().geometry());
    if (const auto id = core::nearestDisplay(geometry, point)) {
        if (Display* display = displayById(*id)) return *display;
    }
    return mainDisplay();
}

void WindowManager::shutdown() {
    if (!m_initialized) return;

    for (auto& display : m_displays) {
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->ref() || !window->originalPhysicalRect) continue;
            if (!m_renderer.restore(*window, CACurrentMediaTime()).succeeded()) {
                std::cerr << "WindowManager: failed to restore window during shutdown (WID "
                          << window->wid() << ")" << std::endl;
            }
        }
    }
    m_isPanning = false;
    m_focusedWindow.reset();
    m_focusRefreshTime = 0;
    m_nativePointerHeld = false;
    m_nativeCommitPending = false;
    m_nativeCameras.clear();
    m_nativeCandidates.clear();
    m_displays.clear();
    m_initialized = false;
}

NSScreen* WindowManager::screenForDisplay(int64_t displayId) const {
    for (NSScreen* screen in [NSScreen screens]) {
        NSNumber* number = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
        if (number && [number longLongValue] == displayId) return screen;
    }
    return nil;
}

float WindowManager::axTopOriginForScreen(NSScreen* screen) const {
    NSScreen* primary = [[NSScreen screens] firstObject];
    if (!screen || !primary) return 0.0f;
    const NSRect primaryFrame = [primary frame];
    const NSRect frame = [screen frame];
    return static_cast<float>(primaryFrame.origin.y + primaryFrame.size.height -
                              frame.origin.y - frame.size.height);
}

Display& WindowManager::displayForWindow(AXUIElementRef window) {
    for (auto& display : m_displays) {
        if (display->windowPool().findWindowByAXRef(window)) return *display;
    }
    CGPoint position{0.0, 0.0};
    if (readAXPoint(window, position)) {
        return displayForPoint({static_cast<float>(position.x), static_cast<float>(position.y)});
    }
    return mainDisplay();
}

std::shared_ptr<ClientWindow> WindowManager::findWindow(AXUIElementRef element) {
    for (auto& display : m_displays) {
        if (auto window = display->windowPool().findWindowByAXRef(element)) return window;
    }
    return nullptr;
}

void WindowManager::removeWindow(AXUIElementRef element) {
    if (auto window = findWindow(element)) (void)m_yabaiBackend.resetTransform(window->wid());
    for (auto& display : m_displays) display->windowPool().removeWindow(element);
}

void WindowManager::removeWindowsForPid(pid_t pid) {
    for (auto& display : m_displays) {
        for (const auto& window : display->windowPool().windows()) {
            if (window->pid() == pid) (void)m_yabaiBackend.resetTransform(window->wid());
        }
    }
    for (auto& display : m_displays) display->windowPool().removeWindowsForPid(pid);
}

void WindowManager::adoptWindow(Display& display, const std::shared_ptr<ClientWindow>& window) {
    if (!window || window->virtualCoordinatesInitialized) return;
    if (!window->captureInitialGeometry()) return;
    window->virtualRect = display.state().physicalToVirtual(window->virtualRect);
    window->virtualCoordinatesInitialized = true;
    if (window->centerOnAdoption) {
        centerWindow(window);
        window->centerOnAdoption = false;
    }
}

bool WindowManager::isWhitelisted(AXUIElementRef element) const {
    if (!element) return false;
    pid_t pid = 0;
    if (AXUIElementGetPid(element, &pid) != kAXErrorSuccess || pid <= 0) return false;
    NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    NSString* name = app.localizedName;
    if (!name) return false;
    const std::string appName = [name UTF8String] ? [name UTF8String] : "";
    for (const std::string& allowed : ConfigManager::instance().snapshot().whitelist) {
        if (allowed == appName) return true;
    }
    return false;
}

void WindowManager::updateWindows(int64_t displayId) {
    if (!m_initialized || m_displays.empty()) return;
    const double now = CACurrentMediaTime();
    // Native dragging owns the frame until the client has handled mouse-up.
    // Do not turn its first AX notification into another programmatic move.
    if (m_nativePointerHeld || (m_nativeCommitPending && now < m_nativeCommitTime)) return;
    if (m_nativeCommitPending) commitNativeInteraction();
    // Focus queries cross into another process; they must not run on every
    // presentation frame (especially on high-refresh-rate displays).
    if (now >= m_focusRefreshTime) {
        m_focusRefreshTime = now + 0.25;
        CFRef<AXUIElementRef> systemWide = CFRef<AXUIElementRef>::adopt(AXUIElementCreateSystemWide());
        CFRef<CFTypeRef> focusedApplication;
        CFRef<CFTypeRef> focusedValue;
        m_focusedWindow.reset();
        if (systemWide && AXUIElementCopyAttributeValue(systemWide.get(), kAXFocusedApplicationAttribute,
                                                        focusedApplication.put()) == kAXErrorSuccess &&
            focusedApplication && CFGetTypeID(focusedApplication.get()) == AXUIElementGetTypeID() &&
            AXUIElementCopyAttributeValue(static_cast<AXUIElementRef>(focusedApplication.get()),
                                         kAXFocusedWindowAttribute, focusedValue.put()) == kAXErrorSuccess &&
            focusedValue && CFGetTypeID(focusedValue.get()) == AXUIElementGetTypeID()) {
            m_focusedWindow = CFRef<AXUIElementRef>::retain(static_cast<AXUIElementRef>(focusedValue.get()));
        }
    }

    const ConfigSnapshot config = ConfigManager::instance().snapshot();
    const core::VisibilityPolicy visibility(config.overscanBufferPx);

    for (auto& display : m_displays) {
        if (displayId && display->id() != displayId) continue;
        const core::DisplayState& state = display->state();
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->ref()) continue;
            adoptWindow(*display, window);
            if (!window->virtualCoordinatesInitialized) continue;
            window->preferNativePosition = core::canUseNativePosition(state.virtualToPhysical(window->virtualRect), display->usableBounds());
            const bool focused = m_focusedWindow && CFEqual(window->ref(), m_focusedWindow.get());
            const bool protectedWindow = focused || isWhitelisted(window->ref());
            const bool shouldRender = protectedWindow ||
                visibility.shouldRender(window->virtualRect, state.viewport(), focused);

            if (!shouldRender) {
                (void)m_renderer.hide(*window, state.virtualToPhysical(window->virtualRect),
                                      state.geometry().bounds, now);
                continue;
            }
            (void)m_renderer.render(*window, state.virtualToPhysical(window->virtualRect), now);
        }
    }
}

void WindowManager::centerWindow(std::shared_ptr<ClientWindow> window) {
    if (!window || !window->virtualCoordinatesInitialized) return;
    Display& display = displayForWindow(window->ref());
    const core::Rect bounds = display.state().geometry().bounds;
    window->lastProgrammaticMoveTime = CACurrentMediaTime();
    window->virtualRect.x = display.camera().x() + bounds.w / 2.0f - window->virtualRect.w / 2.0f;
    window->virtualRect.y = display.camera().y() + bounds.h / 2.0f - window->virtualRect.h / 2.0f;
}

void WindowManager::centerCameraOnWindow(AXUIElementRef element) {
    m_focusedWindow = CFRef<AXUIElementRef>::retain(element);
    if (m_nativePointerHeld || m_nativeCommitPending || m_isPanning || CACurrentMediaTime() < m_nativeCommitTime + 0.25) return;
    const auto window = findWindow(element);
    if (!window || !window->virtualCoordinatesInitialized) return;
    for (auto& display : m_displays) {
        if (!display->windowPool().findWindowByAXRef(element)) continue;
        const core::Rect bounds = display->state().geometry().bounds;
        display->camera().setPosition(
            window->virtualRect.x - bounds.w / 2.0f + window->virtualRect.w / 2.0f,
            window->virtualRect.y - bounds.h / 2.0f + window->virtualRect.h / 2.0f);
        updateWindows();
        return;
    }
}

void WindowManager::syncPhysicalToVirtual(AXUIElementRef element) {
    const auto window = findWindow(element);
    if (m_nativePointerHeld || m_nativeCommitPending) {
        if (window) addNativeCandidate(window);
        return;
    }
    if (!window || window->isHidden || window->needsGeometryRestore || window->positionNeedsVerification ||
        window->rejectedPosition || m_isPanning) return;
    if (CACurrentMediaTime() - window->lastProgrammaticMoveTime < 0.25) return;

    for (auto& display : m_displays) {
        if (!display->windowPool().findWindowByAXRef(element)) continue;
        if (!window->virtualCoordinatesInitialized) {
            adoptWindow(*display, window);
            return;
        }
        CGPoint position{0.0, 0.0};
        if (!readWindowPosition(element, m_yabaiBackend.usesTransforms() ? window->wid() : 0, position)) return;
        CGSize size{0.0, 0.0};
        core::Rect physical{static_cast<float>(position.x), static_cast<float>(position.y), window->virtualRect.w, window->virtualRect.h};
        if (readAXSize(element, size) && std::isfinite(size.width) && std::isfinite(size.height) &&
            size.width > 0 && size.height > 0) {
            physical.w = static_cast<float>(size.width);
            physical.h = static_cast<float>(size.height);
        }
        (void)m_renderer.acceptNativeGeometry(*window, physical, display->state());
        return;
    }
}

void WindowManager::addNativeCandidate(const std::shared_ptr<ClientWindow>& window) {
    if (std::find(m_nativeCandidates.begin(), m_nativeCandidates.end(), window) == m_nativeCandidates.end()) {
        m_nativeCandidates.push_back(window);
    }
}

void WindowManager::beginNativeInteraction(core::Point pointer) {
    if (!m_nativeCommitPending) {
        m_nativeCameras.clear();
        m_nativeCandidates.clear();
        for (const auto& display : m_displays) m_nativeCameras.emplace(display->id(), display->camera().position());
    }
    m_nativePointerHeld = true;
    m_nativeCommitPending = true;
    // The visual hit-test identifies the window even when its AX move
    // notifications are unavailable. No cross-process AX calls run in the tap.
    auto windows = CFRef<CFArrayRef>::adopt(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (CFIndex index = 0; windows && index < CFArrayGetCount(windows.get()); ++index) {
        auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows.get(), index));
        if (!info || CFGetTypeID(info) != CFDictionaryGetTypeID()) continue;
        auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(info, kCGWindowNumber));
        auto bounds = static_cast<CFDictionaryRef>(CFDictionaryGetValue(info, kCGWindowBounds));
        uint32_t wid = 0;
        CGRect frame{};
        if (!number || CFGetTypeID(number) != CFNumberGetTypeID() || !CFNumberGetValue(number, kCGWindowIDCFNumberType, &wid) ||
            !bounds || CFGetTypeID(bounds) != CFDictionaryGetTypeID() || !CGRectMakeWithDictionaryRepresentation(bounds, &frame) ||
            !CGRectContainsPoint(frame, CGPointMake(pointer.x, pointer.y))) continue;
        for (const auto& display : m_displays) {
            if (auto window = display->windowPool().findWindowByWID(wid)) {
                addNativeCandidate(window);
                if (std::getenv("MINFWM_TRACE_WINDOW_INPUT")) {
                    std::cout << "INPUT down WID=" << wid << " visual=" << frame.origin.x << ',' << frame.origin.y
                              << " cached=" << window->lastRenderedX << ',' << window->lastRenderedY
                              << " virtual=" << window->virtualRect.x << ',' << window->virtualRect.y << std::endl;
                }
                return;
            }
        }
    }
}

void WindowManager::endNativeInteraction() {
    if (!m_nativePointerHeld) return;
    m_nativePointerHeld = false;
    // The event tap sees mouse-up before the application processes it.
    m_nativeCommitTime = CACurrentMediaTime() + 0.05;
}

void WindowManager::flushNativeInteractionForPan() {
    m_nativePointerHeld = false;
    m_nativeCommitTime = 0;
}

void WindowManager::commitNativeInteraction() {
    for (auto& display : m_displays) {
        core::DisplayState observationState = display->state();
        if (const auto camera = m_nativeCameras.find(display->id()); camera != m_nativeCameras.end()) {
            observationState.camera().setPosition(camera->second.x, camera->second.y);
        }
        for (const auto& window : display->windowPool().windows()) {
            if (std::find(m_nativeCandidates.begin(), m_nativeCandidates.end(), window) == m_nativeCandidates.end()) continue;
            if (!window || !window->ref() || !window->virtualCoordinatesInitialized || window->isHidden || window->needsGeometryRestore) continue;
            CGPoint position{};
            if (!readWindowPosition(window->ref(), m_yabaiBackend.usesTransforms() ? window->wid() : 0, position)) continue;
            core::Rect physical{static_cast<float>(position.x), static_cast<float>(position.y), window->virtualRect.w, window->virtualRect.h};
            CGSize size{};
            if (readAXSize(window->ref(), size) && std::isfinite(size.width) && std::isfinite(size.height) && size.width > 0 && size.height > 0) {
                physical.w = size.width;
                physical.h = size.height;
            }
            const bool accepted = m_renderer.acceptNativeGeometry(*window, physical, observationState);
            if (std::getenv("MINFWM_TRACE_WINDOW_INPUT")) {
                std::cout << "INPUT drop WID=" << window->wid() << " physical=" << physical.x << ',' << physical.y
                          << " camera=" << observationState.camera().x() << ',' << observationState.camera().y()
                          << " virtual=" << window->virtualRect.x << ',' << window->virtualRect.y
                          << " accepted=" << accepted << std::endl;
            }
        }
    }
    m_nativeCommitPending = false;
    m_nativeCameras.clear();
    m_nativeCandidates.clear();
}

} // namespace minfwm
