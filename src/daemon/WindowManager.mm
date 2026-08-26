#include "WindowManager.hpp"
#include "CFRAII.hpp"
#include "ConfigManager.hpp"
#include "YabaiSA.hpp"
#include "../core/Visibility.hpp"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>

namespace minfwm {

namespace {

constexpr float kHiddenCornerInset = 1.0f;

bool readAXPoint(AXUIElementRef element, CGPoint& point) {
    CFRef<CFTypeRef> value;
    if (!element || AXUIElementCopyAttributeValue(element, kAXPositionAttribute, value.put()) != kAXErrorSuccess) {
        return false;
    }
    return CFGetTypeID(value.get()) == AXValueGetTypeID() &&
           AXValueGetType(static_cast<AXValueRef>(value.get())) == kAXValueTypeCGPoint &&
           AXValueGetValue(static_cast<AXValueRef>(value.get()), kAXValueTypeCGPoint, &point);
}

bool readAXSize(AXUIElementRef element, CGSize& size) {
    CFRef<CFTypeRef> value;
    if (!element || AXUIElementCopyAttributeValue(element, kAXSizeAttribute, value.put()) != kAXErrorSuccess) {
        return false;
    }
    return CFGetTypeID(value.get()) == AXValueGetTypeID() &&
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

void WindowManager::shutdown() {
    if (!m_initialized) return;

    for (auto& display : m_displays) {
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->ref()) continue;
            const core::Rect physical = display->state().virtualToPhysical(window->virtualRect);
            if (window->isAXHidden) {
                const BackendResult unhidden = m_axBackend.setHidden(window->ref(), window->wid(), false);
                if (!unhidden.succeeded()) {
                    std::cerr << "WindowManager: failed to unhide window during shutdown" << std::endl;
                }
            }
            const BackendResult geometry = m_axBackend.restore(
                window->ref(), window->wid(), static_cast<int>(std::lround(physical.x)),
                static_cast<int>(std::lround(physical.y)), physical.w, physical.h);
            if (!geometry.succeeded()) {
                std::cerr << "WindowManager: failed to restore window geometry during shutdown" << std::endl;
            }
            window->isHidden = false;
            window->isAXHidden = false;
            window->lastRenderedX = physical.x;
            window->lastRenderedY = physical.y;
        }
    }
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
    CGPoint position{0.0, 0.0};
    if (readAXPoint(window, position)) {
        Display* closest = nullptr;
        float closestDistance = std::numeric_limits<float>::max();
        for (auto& display : m_displays) {
            const core::Rect bounds = display->state().geometry().bounds;
            const float dx = position.x < bounds.left() ? bounds.left() - static_cast<float>(position.x) :
                             position.x > bounds.right() ? static_cast<float>(position.x) - bounds.right() : 0.0f;
            const float dy = position.y < bounds.top() ? bounds.top() - static_cast<float>(position.y) :
                             position.y > bounds.bottom() ? static_cast<float>(position.y) - bounds.bottom() : 0.0f;
            const float distance = dx * dx + dy * dy;
            if (distance < closestDistance) {
                closestDistance = distance;
                closest = display.get();
            }
            if (distance == 0.0f) break;
        }
        if (closest) return *closest;
    }
    return *m_displays.front();
}

std::shared_ptr<ClientWindow> WindowManager::findWindow(AXUIElementRef element) {
    for (auto& display : m_displays) {
        if (auto window = display->windowPool().findWindowByAXRef(element)) return window;
    }
    return nullptr;
}

void WindowManager::removeWindow(AXUIElementRef element) {
    for (auto& display : m_displays) display->windowPool().removeWindow(element);
}

void WindowManager::adoptWindow(Display& display, const std::shared_ptr<ClientWindow>& window) {
    if (!window || window->virtualCoordinatesInitialized) return;
    window->virtualRect = display.state().physicalToVirtual(window->virtualRect);
    window->virtualCoordinatesInitialized = true;
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
    CFRef<CFTypeRef> focusedValue;
    AXUIElementRef focusedWindow = nullptr;
    if (systemWide && AXUIElementCopyAttributeValue(systemWide.get(), kAXFocusedWindowAttribute,
                                                     focusedValue.put()) == kAXErrorSuccess) {
        focusedWindow = static_cast<AXUIElementRef>(focusedValue.get());
    }

    const ConfigSnapshot config = ConfigManager::instance().snapshot();
    const core::VisibilityPolicy visibility(config.overscanBufferPx);
    const double now = CACurrentMediaTime();

    for (auto& display : m_displays) {
        const core::DisplayState& state = display->state();
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->ref()) continue;
            const bool focused = focusedWindow && CFEqual(window->ref(), focusedWindow);
            const bool protectedWindow = focused || isWhitelisted(window->ref());
            const bool shouldRender = protectedWindow ||
                visibility.shouldRender(window->virtualRect, state.viewport(), focused);

            if (!shouldRender) {
                if (!window->isHidden) {
                    window->lastProgrammaticMoveTime = now;
                    bool usedAXHidden = false;
                    BackendResult hidden = m_axBackend.setHidden(window->ref(), window->wid(), true);
                    usedAXHidden = hidden.succeeded();
                    if (!hidden.succeeded()) {
                        const core::Rect bounds = state.geometry().bounds;
                        const BackendResult resized = m_axBackend.resize(window->ref(), window->wid(), 1.0f, 1.0f);
                        const BackendResult moved = m_axBackend.move(
                            window->ref(), window->wid(), static_cast<int>(bounds.right() - kHiddenCornerInset),
                            static_cast<int>(bounds.bottom() - kHiddenCornerInset));
                        hidden = {resized.succeeded() && moved.succeeded() ? BackendCode::ok : BackendCode::failed};
                    }
                    if (hidden.succeeded()) {
                        window->isHidden = true;
                        window->isAXHidden = usedAXHidden;
                        window->lastRenderedX = std::numeric_limits<float>::quiet_NaN();
                        window->lastRenderedY = std::numeric_limits<float>::quiet_NaN();
                    }
                }
                continue;
            }

            const core::Rect physical = state.virtualToPhysical(window->virtualRect);
            const int targetX = static_cast<int>(std::lround(physical.x));
            const int targetY = static_cast<int>(std::lround(physical.y));
            const bool geometryDirty = window->isHidden ||
                !std::isfinite(window->lastRenderedX) || !std::isfinite(window->lastRenderedY) ||
                window->lastRenderedX != physical.x || window->lastRenderedY != physical.y;
            if (!geometryDirty && window->isLayerSet) continue;

            window->lastProgrammaticMoveTime = now;
            bool moved = false;
            if (window->isHidden) {
                if (window->isAXHidden) {
                    const BackendResult unhidden = m_axBackend.setHidden(window->ref(), window->wid(), false);
                    if (!unhidden.succeeded()) continue;
                }
                moved = m_axBackend.restore(window->ref(), window->wid(), targetX, targetY,
                                            physical.w, physical.h).succeeded();
            } else {
                const BackendResult saMove = m_yabaiBackend.move(window->ref(), window->wid(), targetX, targetY);
                moved = saMove.succeeded();
                if (!moved) {
                    moved = m_axBackend.move(window->ref(), window->wid(), targetX, targetY).succeeded();
                }
            }
            if (!moved) continue;

            if (!window->isLayerSet) {
                const BackendResult layer = m_yabaiBackend.setLayer(window->ref(), window->wid(), 11);
                if (!layer.succeeded()) {
                    // AX has no public z-layer setter. Calling it preserves the
                    // fallback contract and makes the unsupported result explicit.
                    (void)m_axBackend.setLayer(window->ref(), window->wid(), 11);
                }
                window->isLayerSet = true;
            }

            window->isHidden = false;
            window->isAXHidden = false;
            window->lastRenderedX = physical.x;
            window->lastRenderedY = physical.y;
        }
    }
}

void WindowManager::centerWindow(std::shared_ptr<ClientWindow> window) {
    if (!window) return;
    Display& display = displayForWindow(window->ref());
    const core::Rect bounds = display.state().geometry().bounds;
    window->lastProgrammaticMoveTime = CACurrentMediaTime();
    window->virtualRect.x = display.camera().x() + bounds.w / 2.0f - window->virtualRect.w / 2.0f;
    window->virtualRect.y = display.camera().y() + bounds.h / 2.0f - window->virtualRect.h / 2.0f;
}

void WindowManager::centerCameraOnWindow(AXUIElementRef element) {
    const auto window = findWindow(element);
    if (!window) return;
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
    if (!window || window->isHidden || m_isPanning) return;
    if (CACurrentMediaTime() - window->lastProgrammaticMoveTime < 0.25) return;

    for (auto& display : m_displays) {
        if (!display->windowPool().findWindowByAXRef(element)) continue;
        CGPoint position{0.0, 0.0};
        if (readAXPoint(element, position)) {
            const core::Point virtualPosition = display->state().physicalToVirtual(
                core::Point{static_cast<float>(position.x), static_cast<float>(position.y)});
            window->virtualRect.x = virtualPosition.x;
            window->virtualRect.y = virtualPosition.y;
        }
        CGSize size{0.0, 0.0};
        if (readAXSize(element, size)) {
            window->virtualRect.w = static_cast<float>(size.width);
            window->virtualRect.h = static_cast<float>(size.height);
        }
        window->virtualCoordinatesInitialized = true;
        return;
    }
}

} // namespace minfwm
