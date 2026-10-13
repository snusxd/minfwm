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
    const bool yabaiAvailable = m_yabaiBackend.initialize(ConfigManager::instance().snapshot().experimentalWindowTransforms);

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
        m_displays.push_back(std::make_unique<Display>(
            id, bounds, yabaiAvailable ? WindowPool::optionalWindowIdResolver() : nullptr));
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
                  << (m_yabaiBackend.usesTransforms() ? "enabled (experimental)" : "disabled (requires explicit opt-in and lifecycle v2 SA)") << std::endl;
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

void WindowManager::updateWindows() {
    if (!m_initialized || m_displays.empty()) return;

    CFRef<AXUIElementRef> systemWide = CFRef<AXUIElementRef>::adopt(AXUIElementCreateSystemWide());
    CFRef<CFTypeRef> focusedApplication;
    CFRef<CFTypeRef> focusedValue;
    AXUIElementRef focusedWindow = nullptr;
    if (systemWide && AXUIElementCopyAttributeValue(systemWide.get(), kAXFocusedApplicationAttribute,
                                                    focusedApplication.put()) == kAXErrorSuccess &&
        focusedApplication && CFGetTypeID(focusedApplication.get()) == AXUIElementGetTypeID() &&
        AXUIElementCopyAttributeValue(static_cast<AXUIElementRef>(focusedApplication.get()),
                                     kAXFocusedWindowAttribute, focusedValue.put()) == kAXErrorSuccess &&
        focusedValue && CFGetTypeID(focusedValue.get()) == AXUIElementGetTypeID()) {
        focusedWindow = static_cast<AXUIElementRef>(focusedValue.get());
    }

    const ConfigSnapshot config = ConfigManager::instance().snapshot();
    const core::VisibilityPolicy visibility(config.overscanBufferPx);
    const double now = CACurrentMediaTime();

    for (auto& display : m_displays) {
        const core::DisplayState& state = display->state();
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->ref()) continue;
            adoptWindow(*display, window);
            if (!window->virtualCoordinatesInitialized) continue;
            const bool focused = focusedWindow && CFEqual(window->ref(), focusedWindow);
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
        if (readWindowPosition(element, m_yabaiBackend.usesTransforms() ? window->wid() : 0, position)) {
            const core::Point virtualPosition = display->state().physicalToVirtual(
                core::Point{static_cast<float>(position.x), static_cast<float>(position.y)});
            window->virtualRect.x = virtualPosition.x;
            window->virtualRect.y = virtualPosition.y;
        }
        CGSize size{0.0, 0.0};
        if (readAXSize(element, size) && std::isfinite(size.width) && std::isfinite(size.height) &&
            size.width > 0 && size.height > 0) {
            window->virtualRect.w = static_cast<float>(size.width);
            window->virtualRect.h = static_cast<float>(size.height);
        }
        window->virtualCoordinatesInitialized = true;
        return;
    }
}

} // namespace minfwm
