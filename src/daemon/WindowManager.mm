#include "WindowManager.hpp"
#include "CFRAII.hpp"
#include "ConfigManager.hpp"
#include "YabaiSA.hpp"
#include "../core/Visibility.hpp"
#include "../core/WindowOwnership.hpp"
#include "../core/OverviewPreviewPolicy.hpp"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <algorithm>
#include <cstdlib>
#include <limits>
#include <sys/stat.h>

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

NSString* layoutSnapshotPath() {
    NSString* support = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSString* directory = [support stringByAppendingPathComponent:@"minfwm"];
    return [directory stringByAppendingPathComponent:@"layout.plist"];
}

bool numberValue(NSDictionary* dictionary, NSString* key, double& value) {
    id candidate = dictionary[key];
    if (![candidate isKindOfClass:[NSNumber class]]) return false;
    value = [candidate doubleValue];
    return std::isfinite(value);
}

bool isIgnoredDisplayName(NSString* name, const std::vector<std::string>& ignoredDisplays) {
    if (!name) return false;
    const char* value = name.UTF8String;
    if (!value) return false;
    return std::find(ignoredDisplays.begin(), ignoredDisplays.end(), value) != ignoredDisplays.end();
}

} // namespace

bool WindowManager::initialize(bool allowAdministratorLoad) {
    if (m_initialized) return true;

    std::cout << "WindowManager: Initializing public AX backend" << std::endl;
    ConfigManager::instance().load();
    const auto ignoredDisplays = ConfigManager::instance().snapshot().ignoredDisplays;
    m_displays.clear();
    const bool yabaiAvailable = m_yabaiBackend.initialize(allowAdministratorLoad);
    if (!yabaiAvailable || !m_yabaiBackend.usesTransforms() || !m_yabaiBackend.supportsPinnedLevels()) {
        std::cerr << "WindowManager: required Yabai Scripting Addition transform and pinned-level capabilities are unavailable"
                  << std::endl;
        return false;
    }

    for (NSScreen* screen in [NSScreen screens]) {
        NSDictionary* description = [screen deviceDescription];
        NSNumber* displayID = [description objectForKey:@"NSScreenNumber"];
        if (!displayID) continue;
        if (isIgnoredDisplayName(screen.localizedName, ignoredDisplays)) {
            std::cout << "WindowManager: Ignoring display " << displayID.longLongValue << " ("
                      << screen.localizedName.UTF8String << ")" << std::endl;
            continue;
        }

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
            id, bounds, WindowPool::yabaiWindowIdResolver(), usableBounds));
        std::cout << "WindowManager: Found display " << id << " ["
                  << frame.size.width << "x" << frame.size.height << "]" << std::endl;
    }

    if (m_displays.empty()) {
        std::cerr << "WindowManager: no displays available" << std::endl;
        return false;
    }

    restoreLayoutSnapshot();

    std::cout << "WindowManager: required Yabai SA backend enabled" << std::endl;
    std::cout << "WindowManager: absolute transforms enabled" << std::endl;
    std::cout << "WindowManager: pinned always-on-top enabled" << std::endl;
    m_initialized = true;
    return true;
}

void WindowManager::refreshDisplays() {
    if (!m_initialized) return;
    // Drop canvases before adapting their physical coordinate systems. Parked
    // originals will resume through the ordinary rendering path below.
    m_overviewPreviews.reset();

    std::size_t added = 0;
    std::size_t updated = 0;
    for (NSScreen* screen in NSScreen.screens) {
        NSDictionary* description = [screen deviceDescription];
        NSNumber* displayID = description[@"NSScreenNumber"];
        if (!displayID) continue;
        const bool ignored = isIgnoredDisplayName(
            screen.localizedName, ConfigManager::instance().snapshot().ignoredDisplays);

        const int64_t id = displayID.longLongValue;
        const float topOrigin = axTopOriginForScreen(screen);
        const NSRect frame = screen.frame;
        const core::Rect bounds{static_cast<float>(frame.origin.x), topOrigin,
                                static_cast<float>(frame.size.width), static_cast<float>(frame.size.height)};
        const NSRect usable = screen.visibleFrame;
        const core::Rect usableBounds{
            static_cast<float>(usable.origin.x),
            topOrigin + static_cast<float>(NSMaxY(frame) - NSMaxY(usable)),
            static_cast<float>(usable.size.width), static_cast<float>(usable.size.height)};

        if (Display* display = displayById(id)) {
            if (display->updateScreen(bounds, usableBounds)) ++updated;
            continue;
        }
        if (ignored) continue;

        m_displays.push_back(std::make_unique<Display>(
            id, bounds, WindowPool::yabaiWindowIdResolver(), usableBounds));
        ++added;
        std::cout << "WindowManager: Added display " << id << " ["
                  << frame.size.width << "x" << frame.size.height << "]" << std::endl;
    }

    if (added || updated) {
        std::cout << "WindowManager: refreshed displays (added=" << added
                  << ", updated=" << updated << ")" << std::endl;
        updateWindows();
    }
}

Display& WindowManager::mainDisplay() {
    if (m_displays.empty()) {
        throw std::runtime_error("WindowManager: no display is initialized");
    }
    for (auto& display : m_displays) {
        if (!isIgnoredDisplay(display->id())) return *display;
    }
    return *m_displays.front();
}

Display* WindowManager::displayById(int64_t id) {
    for (auto& display : m_displays) {
        if (display->id() == id) return display.get();
    }
    return nullptr;
}

bool WindowManager::saveLayoutSnapshot(std::string& error) {
    if (!m_initialized) {
        error = "window manager is not initialized";
        return false;
    }
    if (m_nativeCommitPending) commitNativeInteraction();

    NSMutableArray* displays = [NSMutableArray arrayWithCapacity:m_displays.size()];
    NSMutableArray* windows = [NSMutableArray array];
    for (const auto& display : m_displays) {
        const core::Point camera = display->camera().position();
        if (!std::isfinite(camera.x) || !std::isfinite(camera.y)) continue;
        [displays addObject:@{@"id": @(display->id()), @"x": @(camera.x), @"y": @(camera.y)}];
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->virtualCoordinatesInitialized || window->pid() <= 0 || window->wid() == 0) continue;
            const core::Rect rect = window->virtualRect;
            if (!std::isfinite(rect.x) || !std::isfinite(rect.y) ||
                !std::isfinite(rect.w) || !std::isfinite(rect.h) || rect.w <= 0 || rect.h <= 0) continue;
            [windows addObject:@{@"display": @(display->id()), @"pid": @(window->pid()),
                                 @"wid": @(window->wid()), @"x": @(rect.x), @"y": @(rect.y),
                                 @"w": @(rect.w), @"h": @(rect.h)}];
        }
    }

    NSDictionary* snapshot = @{@"version": @1, @"created": @([NSDate date].timeIntervalSince1970),
                               @"displays": displays, @"windows": windows};
    NSError* fileError = nil;
    NSString* path = layoutSnapshotPath();
    NSString* directory = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES
                                                    attributes:@{NSFilePosixPermissions: @0700}
                                                         error:&fileError]) {
        const char* message = fileError.localizedDescription.UTF8String;
        error = message ? message : "could not create the layout snapshot directory";
        return false;
    }
    if (::chmod(directory.fileSystemRepresentation, S_IRWXU) != 0) {
        error = "could not secure the layout snapshot directory permissions";
        return false;
    }

    NSData* data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&fileError];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&fileError]) {
        const char* message = fileError.localizedDescription.UTF8String;
        error = message ? message : "could not write the layout snapshot";
        return false;
    }
    if (::chmod(path.fileSystemRepresentation, S_IRUSR | S_IWUSR) != 0) {
        error = "could not secure the layout snapshot file permissions";
        return false;
    }
    return true;
}

void WindowManager::restoreLayoutSnapshot() {
    NSString* path = layoutSnapshotPath();
    NSData* data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                                 options:NSPropertyListImmutable
                                                                  format:nil
                                                                   error:nil];
    if (![propertyList isKindOfClass:[NSDictionary class]]) {
        std::cerr << "WindowManager: ignoring invalid layout snapshot" << std::endl;
        (void)[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    NSDictionary* snapshot = (NSDictionary*)propertyList;
    double version = 0;
    double created = 0;
    if (!numberValue(snapshot, @"version", version) || version != 1 ||
        !numberValue(snapshot, @"created", created) ||
        std::abs([NSDate date].timeIntervalSince1970 - created) > 300.0) {
        std::cerr << "WindowManager: ignoring expired or unsupported layout snapshot" << std::endl;
        (void)[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    id displayValues = snapshot[@"displays"];
    if ([displayValues isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray*)displayValues) {
            if (![value isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary* saved = (NSDictionary*)value;
            double displayId = 0, x = 0, y = 0;
            if (!numberValue(saved, @"id", displayId) || !numberValue(saved, @"x", x) ||
                !numberValue(saved, @"y", y) || displayId < 0 ||
                displayId >= std::ldexp(1.0, 63) || std::floor(displayId) != displayId ||
                std::abs(x) > std::numeric_limits<float>::max() ||
                std::abs(y) > std::numeric_limits<float>::max()) continue;
            if (Display* display = displayById(static_cast<int64_t>(displayId))) {
                (void)display->camera().setPosition(static_cast<float>(x), static_cast<float>(y));
            }
        }
    }

    id windowValues = snapshot[@"windows"];
    if ([windowValues isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray*)windowValues) {
            if (![value isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary* saved = (NSDictionary*)value;
            double displayId = 0, pid = 0, wid = 0, x = 0, y = 0, w = 0, h = 0;
            if (!numberValue(saved, @"display", displayId) || !numberValue(saved, @"pid", pid) ||
                !numberValue(saved, @"wid", wid) || !numberValue(saved, @"x", x) ||
                !numberValue(saved, @"y", y) || !numberValue(saved, @"w", w) ||
                !numberValue(saved, @"h", h) || displayId < 0 || pid <= 0 || wid <= 0 ||
                displayId >= std::ldexp(1.0, 63) || std::floor(displayId) != displayId ||
                pid > std::numeric_limits<pid_t>::max() || wid > std::numeric_limits<uint32_t>::max() ||
                std::floor(pid) != pid || std::floor(wid) != wid ||
                w <= 0 || h <= 0 || std::abs(x) > std::numeric_limits<float>::max() ||
                std::abs(y) > std::numeric_limits<float>::max() ||
                w > std::numeric_limits<float>::max() || h > std::numeric_limits<float>::max()) continue;
            const auto key = std::make_tuple(static_cast<int64_t>(displayId), static_cast<pid_t>(pid),
                                             static_cast<uint32_t>(wid));
            m_savedWindowLayouts[key] = SavedWindowLayout{
                core::Rect{static_cast<float>(x), static_cast<float>(y),
                           static_cast<float>(w), static_cast<float>(h)}};
        }
    }

    (void)[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    std::cout << "WindowManager: restored layout snapshot for " << m_savedWindowLayouts.size()
              << " windows" << std::endl;
}

void WindowManager::finishLayoutRestore() {
    m_savedWindowLayouts.clear();
}

Display& WindowManager::displayForPoint(core::Point point) {
    std::vector<core::DisplayGeometry> geometry;
    geometry.reserve(m_displays.size());
    for (const auto& display : m_displays) {
        if (!isIgnoredDisplay(display->id())) geometry.push_back(display->state().geometry());
    }
    if (const auto id = core::nearestDisplay(geometry, point)) {
        if (Display* display = displayById(*id)) return *display;
    }
    return mainDisplay();
}

bool WindowManager::isIgnoredDisplayAtPoint(core::Point point) const {
    for (NSScreen* screen in NSScreen.screens) {
        const NSRect frame = screen.frame;
        const float topOrigin = axTopOriginForScreen(screen);
        if (point.x < NSMinX(frame) || point.x >= NSMaxX(frame) ||
            point.y < topOrigin || point.y >= topOrigin + NSHeight(frame)) continue;
        return isIgnoredDisplayName(screen.localizedName,
                                    ConfigManager::instance().snapshot().ignoredDisplays);
    }
    return false;
}

bool WindowManager::isWindowOnIgnoredDisplay(AXUIElementRef window) const {
    CGPoint position{0.0, 0.0};
    CGSize size{0.0, 0.0};
    if (!readAXPoint(window, position) || !readAXSize(window, size)) return false;
    return isIgnoredDisplayAtPoint({static_cast<float>(position.x + size.width / 2.0),
                                    static_cast<float>(position.y + size.height / 2.0)});
}

void WindowManager::shutdown() {
    m_overviewPreviews.reset();
    if (!m_initialized) return;

    for (auto& display : m_displays) {
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->ref() || !window->originalPhysicalRect) continue;
            if (m_hiddenApplications.contains(window->pid()) || window->applicationSuspended) {
                (void)m_renderer.suspend(*window, CACurrentMediaTime());
                continue;
            }
            if (!m_renderer.restore(*window, CACurrentMediaTime()).succeeded()) {
                std::cerr << "WindowManager: failed to restore window during shutdown (WID "
                          << window->wid() << ")" << std::endl;
            }
        }
    }
    m_isPanning = false;
    m_focusedWindow.reset();
    m_focusRefreshTime = 0;
    m_windowRefreshTime = 0;
    m_nativePointerHeld = false;
    m_nativeCommitPending = false;
    m_nativeWindowDragged = false;
    m_nativeCameras.clear();
    m_nativeCandidates.clear();
    m_nativeStartFrames.clear();
    m_draggedWindow.reset();
    m_dragStartVirtualRect.reset();
    m_zoomRequest.reset();
    m_overviewExit.reset();
    m_overviewFocus.reset();
    m_lastFocusedWindow.reset();
    m_zoomFrameTimes.clear();
    m_applicationNames.clear();
    m_hiddenApplications.clear();
    m_onscreenWindows.reset();
    m_overviewWindowOrders.clear();
    m_overviewTrace = {};
    m_savedWindowLayouts.clear();
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

bool WindowManager::isIgnoredDisplay(int64_t displayId) const {
    NSScreen* screen = screenForDisplay(displayId);
    return screen && isIgnoredDisplayName(screen.localizedName,
        ConfigManager::instance().snapshot().ignoredDisplays);
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

std::shared_ptr<ClientWindow> WindowManager::findWindow(AXUIElementRef element) const {
    for (auto& display : m_displays) {
        if (auto window = display->windowPool().findWindowByAXRef(element)) return window;
    }
    return nullptr;
}

bool WindowManager::toggleFocusedWindowPin() {
    if (m_focusedWindow && isWindowOnIgnoredDisplay(m_focusedWindow.get())) return false;
    auto window = m_focusedWindow ? findWindow(m_focusedWindow.get()) : nullptr;
    if (!window) window = m_lastFocusedWindow.lock();
    if (!window || !window->virtualCoordinatesInitialized || !findWindow(window->ref())) return false;

    if (window->pinned) {
        window->pinned = false;
        window->pinnedAlwaysOnTop.reset();
        window->layerAttempted = false;
        window->lastRenderedX = std::numeric_limits<float>::quiet_NaN();
        window->lastRenderedY = std::numeric_limits<float>::quiet_NaN();
        if (AXUIElementPerformAction(window->ref(), kAXRaiseAction) != kAXErrorSuccess) {
            std::cerr << "WindowManager: could not raise unpinned window WID=" << window->wid() << std::endl;
        }
        std::cout << "WindowManager: unpinned window WID=" << window->wid() << std::endl;
        return true;
    }

    Display& display = displayForWindow(window->ref());
    const core::Rect physical = display.state().virtualToPhysical(window->virtualRect);
    window->preferNativePosition = core::frameFitsDisplay(physical, display.state().geometry().bounds) &&
        core::canUseNativePosition(physical, display.usableBounds());
    if (!m_renderer.releaseToNative(*window, physical, CACurrentMediaTime()).succeeded()) {
        std::cerr << "WindowManager: could not pin window WID=" << window->wid() << std::endl;
        return false;
    }
    window->pinned = true;
    window->pinnedAlwaysOnTop.reset();
    const auto config = ConfigManager::instance().snapshot();
    if (!m_renderer.setPinnedLayer(*window, config.pinsAlwaysOnTop).succeeded()) {
        window->pinLayerRetryTime = CACurrentMediaTime() + 1.0;
        std::cerr << "WindowManager: could not apply pinned window layer WID=" << window->wid() << std::endl;
    }
    if (AXUIElementPerformAction(window->ref(), kAXRaiseAction) != kAXErrorSuccess) {
        std::cerr << "WindowManager: could not raise pinned window WID=" << window->wid() << std::endl;
    }
    std::cout << "WindowManager: pinned window WID=" << window->wid() << std::endl;
    return true;
}

bool WindowManager::panCamera(Display& display, core::Point delta) {
    return display.state().panCamera(delta);
}

void WindowManager::finishCameraPan(Display& display, bool snap) {
    auto& state = display.state();
    const ConfigSnapshot config = ConfigManager::instance().snapshot();
    if (!snap || state.overviewActive() || !config.snapEnabled) {
        state.cancelCameraPan();
        return;
    }
    std::vector<core::Rect> windows;
    for (const auto& window : display.windowPool().windows()) {
        if (!window || !window->virtualCoordinatesInitialized || window->pinned || window->isHidden ||
            window->applicationSuspended || window->needsGeometryRestore) continue;
        windows.push_back(window->virtualRect);
    }
    if (state.finishCameraPan(windows, config.snapThreshold / state.scale(),
                              config.snapHorizontalTuning, config.snapVerticalTuning) &&
        std::getenv("MINFWM_TRACE_WINDOW_INPUT")) {
        std::cout << "CAMERA_SNAP display=" << display.id() << " animated" << std::endl;
    }
}

void WindowManager::removeWindow(AXUIElementRef element) {
    if (auto window = findWindow(element)) (void)m_yabaiBackend.resetTransform(window->wid());
    for (auto& display : m_displays) display->windowPool().removeWindow(element);
}

void WindowManager::removeWindowsForPid(pid_t pid) {
    m_applicationNames.erase(pid);
    m_hiddenApplications.erase(pid);
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
    // Newly created windows have native sizes even while the camera is zoomed.
    const auto origin = display.state().physicalToVirtual(core::Point{window->virtualRect.x, window->virtualRect.y});
    window->virtualRect.x = origin.x;
    window->virtualRect.y = origin.y;
    if (window->pid() > 0 && window->wid() != 0) {
        const auto key = std::make_tuple(display.id(), window->pid(), window->wid());
        if (const auto saved = m_savedWindowLayouts.find(key); saved != m_savedWindowLayouts.end()) {
            window->virtualRect = saved->second.rect;
            m_savedWindowLayouts.erase(saved);
        }
    }
    window->virtualCoordinatesInitialized = true;
    if (window->centerOnAdoption) {
        if (!window->isAuxiliaryWindow) centerWindow(window);
        window->centerOnAdoption = false;
    }
}

void WindowManager::setApplicationState(pid_t pid, std::string name, bool hidden) {
    m_applicationNames[pid] = std::move(name);
    if (hidden) m_hiddenApplications.insert(pid);
    else m_hiddenApplications.erase(pid);
}

void WindowManager::reconcileApplicationWindows(pid_t pid, const std::vector<AXUIElementRef>& liveWindows) {
    for (auto& display : m_displays) {
        for (const auto& window : display->windowPool().removeUnlistedWindows(pid, liveWindows)) {
            (void)m_yabaiBackend.resetTransform(window->wid());
            std::erase(m_nativeCandidates, window);
            if (m_focusedWindow && CFEqual(m_focusedWindow.get(), window->ref())) m_focusedWindow.reset();
            std::cout << "WindowManager: removed closed AX window WID=" << window->wid() << std::endl;
        }
    }
}

bool WindowManager::isWhitelisted(const ClientWindow& window) const {
    const auto name = m_applicationNames.find(window.pid());
    if (name == m_applicationNames.end()) return false;
    for (const std::string& allowed : ConfigManager::instance().snapshot().whitelist) {
        if (allowed == name->second) return true;
    }
    return false;
}

void WindowManager::refreshWindowSnapshot(double now) {
    m_windowRefreshTime = now + 0.25;
    if (auto visible = readOnscreenWindowIds()) m_onscreenWindows = std::move(visible);
    const auto liveIds = readSessionWindowIds();
    if (!liveIds) return; // A failed query is never evidence of destruction.
    for (auto& display : m_displays) {
        for (const auto& window : display->windowPool().removeMissingWindows(*liveIds)) {
            (void)m_yabaiBackend.resetTransform(window->wid());
            std::erase(m_nativeCandidates, window);
            if (m_focusedWindow && CFEqual(m_focusedWindow.get(), window->ref())) m_focusedWindow.reset();
            std::cout << "WindowManager: removed missing window WID=" << window->wid() << std::endl;
        }
    }
}

void WindowManager::updateWindows(int64_t displayId) {
    if (!m_initialized || m_displays.empty()) return;
    const double now = CACurrentMediaTime();
    // Native dragging owns the frame until the client has handled mouse-up.
    // Do not turn its first AX notification into another programmatic move.
    if (m_nativePointerHeld || (m_nativeCommitPending && now < m_nativeCommitTime)) return;
    if (m_nativeCommitPending) commitNativeInteraction();
    const auto* zoomDisplay = m_zoomRequest ? displayById(m_zoomRequest->displayId) : nullptr;
    const bool enteringOverview = zoomDisplay && !zoomDisplay->state().overviewActive();
    if (enteringOverview) {
        // Freeze the initial stacking order: parking removes originals from the
        // on-screen list, but must not reorder their cached thumbnails.
        auto& order = m_overviewWindowOrders[zoomDisplay->id()];
        order.clear();
        auto windows = CFRef<CFArrayRef>::adopt(
            CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
        for (CFIndex index = 0; windows && index < CFArrayGetCount(windows.get()); ++index) {
            auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows.get(), index));
            if (!info || CFGetTypeID(info) != CFDictionaryGetTypeID()) continue;
            auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(info, kCGWindowNumber));
            uint32_t wid = 0;
            if (number && CFGetTypeID(number) == CFNumberGetTypeID() &&
                CFNumberGetValue(number, kCGWindowIDCFNumberType, &wid) && wid) {
                order.push_back(wid);
            }
        }
    }
    if (now >= m_windowRefreshTime || enteringOverview) refreshWindowSnapshot(now);
    if (m_zoomRequest) {
        if (auto* display = displayById(m_zoomRequest->displayId)) {
            display->state().requestZoom(m_zoomRequest->delta, m_zoomRequest->anchor);
            if (std::getenv("MINFWM_TRACE_WINDOW_INPUT")) {
                std::cout << "ZOOM display=" << display->id() << " delta=" << m_zoomRequest->delta
                          << " active=" << display->state().overviewActive() << std::endl;
            }
        }
        m_zoomRequest.reset();
    }
    if (m_overviewExit) applyOverviewExit();
    // Focus queries cross into another process; they must not run on every
    // presentation frame (especially on high-refresh-rate displays).
    bool focusChanged = false;
    if (now >= m_focusRefreshTime) {
        m_focusRefreshTime = now + 0.25;
        CFRef<AXUIElementRef> previousFocus = m_focusedWindow
            ? CFRef<AXUIElementRef>::retain(m_focusedWindow.get())
            : CFRef<AXUIElementRef>{};
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
            if (!overviewActive()) {
                if (auto focused = findWindow(m_focusedWindow.get()); focused && focused->virtualCoordinatesInitialized && focused->wid()) {
                    m_lastFocusedWindow = focused;
                }
            }
        }
        if (previousFocus && m_focusedWindow) {
            focusChanged = !CFEqual(previousFocus.get(), m_focusedWindow.get());
        } else {
            focusChanged = static_cast<bool>(previousFocus) != static_cast<bool>(m_focusedWindow);
        }
    }

    const ConfigSnapshot config = ConfigManager::instance().snapshot();
    const core::VisibilityPolicy visibility(config.overscanBufferPx);
    const bool traceOverview = std::getenv("MINFWM_TRACE_OVERVIEW") != nullptr;
    std::size_t liveOverviewUpdates = 0;
    std::size_t previewFrames = 0;
    bool renderedOverview = false;

    core::Rect desktopBounds = m_displays.front()->state().geometry().bounds;
    for (const auto& display : m_displays) {
        const core::Rect bounds = display->state().geometry().bounds;
        const float left = std::min(desktopBounds.x, bounds.x);
        const float top = std::min(desktopBounds.y, bounds.y);
        const float right = std::max(desktopBounds.right(), bounds.right());
        const float bottom = std::max(desktopBounds.bottom(), bounds.bottom());
        desktopBounds = {left, top, right - left, bottom - top};
    }
    // Yabai moves a transformed window in global desktop coordinates. Park
    // windows beyond the complete desktop so a culled window cannot appear
    // on a neighbouring monitor whose physical coordinates overlap its canvas.
    const core::Point parkingPosition{desktopBounds.right() + 64.0f, desktopBounds.bottom() + 64.0f};

    for (auto& display : m_displays) {
        if (displayId && display->id() != displayId) continue;
        if (isIgnoredDisplay(display->id())) {
            (void)m_overviewPreviews.beginDisplay(display->id(), display->state().geometry().bounds,
                1, false, config.rewindOnFocus, now, m_overviewWindowOrders[display->id()]);
            m_overviewPreviews.endDisplay(display->id());
            // A reload can make an already managed display native. Release
            // every visible window before this canvas stops rendering it.
            const auto windows = display->windowPool().windows();
            const core::Rect usable = display->usableBounds();
            for (const auto& window : windows) {
                if (!window || !window->virtualCoordinatesInitialized ||
                    m_hiddenApplications.contains(window->pid())) continue;
                core::Rect physical = display->state().virtualToPhysical(window->virtualRect);
                physical.x = std::clamp(physical.x, usable.x, std::max(usable.x, usable.right() - physical.w));
                physical.y = std::clamp(physical.y, usable.y, std::max(usable.y, usable.bottom() - physical.h));
                (void)releaseWindowToIgnoredDisplay(window, physical);
            }
            continue;
        }
        double& previousFrame = m_zoomFrameTimes[display->id()];
        display->state().advanceZoom(previousFrame ? now - previousFrame : 0,
                                     config.animationSpeed, config.animationsEnabled);
        previousFrame = now;
        const core::DisplayState& state = display->state();
        const bool previewMode = m_overviewPreviews.beginDisplay(display->id(), state.geometry().bounds,
            state.scale(), config.overviewPreviews && screenForDisplay(display->id()),
            config.rewindOnFocus, now, m_overviewWindowOrders[display->id()]);
        renderedOverview = renderedOverview || state.overviewActive();
        bool overviewFailed = false;
        for (const auto& window : display->windowPool().windows()) {
            if (!window || !window->ref()) continue;
            if (window->pinned) {
                if ((focusChanged || !window->pinnedAlwaysOnTop ||
                     *window->pinnedAlwaysOnTop != config.pinsAlwaysOnTop) &&
                    now >= window->pinLayerRetryTime) {
                    if (!m_renderer.setPinnedLayer(*window, config.pinsAlwaysOnTop).succeeded()) {
                        window->pinLayerRetryTime = now + 1.0;
                    }
                }
                continue;
            }
            if (m_hiddenApplications.contains(window->pid())) {
                if (!window->applicationSuspended) (void)m_renderer.suspend(*window, now);
                continue;
            }
            adoptWindow(*display, window);
            if (!window->virtualCoordinatesInitialized) continue;
            advanceWindowAnimation(*window, now, config.animationSpeed, config.animationsEnabled);
            const core::Rect physical = state.virtualToPhysical(window->virtualRect);
            const core::Rect displayBounds = state.geometry().bounds;
            const bool fullyOutsideDisplay = physical.right() <= displayBounds.x ||
                physical.x >= displayBounds.right() || physical.bottom() <= displayBounds.y ||
                physical.y >= displayBounds.bottom();
            const bool beingDragged = window == m_draggedWindow;
            if (fullyOutsideDisplay && !beingDragged) {
                (void)m_renderer.hide(*window, physical, displayBounds, now, parkingPosition);
                continue;
            }
            if (window->isAuxiliaryWindow && !window->isHidden && m_onscreenWindows &&
                !m_onscreenWindows->contains(window->wid())) {
                if (!window->applicationSuspended) (void)m_renderer.suspend(*window, now);
                continue;
            }
            if (!window->nativePresentationChecked && m_yabaiBackend.usesTransforms() && window->wid() &&
                m_onscreenWindows && m_onscreenWindows->contains(window->wid())) {
                window->nativePresentationChecked = true;
                if (!m_yabaiBackend.hasTransform(window->wid())) {
                    const auto native = readNativeWindowPresentation(window->wid());
                    if (native && needsNativePresentationRecovery(*native)) {
                        const bool recovered = m_yabaiBackend.recoverNativePresentation(window->wid(), native->frame).succeeded();
                        std::cout << "WindowManager: native presentation recovery WID=" << window->wid()
                                  << " result=" << (recovered ? "ok" : "failed") << std::endl;
                    }
                }
            }
            if (state.overviewActive()) {
                if (!window->wid()) continue;
                const bool focused = m_focusedWindow && CFEqual(window->ref(), m_focusedWindow.get());
                const bool previewEligible = previewMode && m_focusedWindow && window != m_overviewFocus &&
                    core::overviewPreviewEligible({focused, isWhitelisted(*window), window->pinned,
                                                   beingDragged, window->isAuxiliaryWindow});
                if (previewEligible && m_overviewPreviews.ready(window, now) &&
                    m_renderer.parkForPreview(*window, parkingPosition, now).succeeded()) {
                    m_overviewPreviews.show(display->id(), window, physical);
                    ++previewFrames;
                    continue;
                }
                const float renderedScale = std::round(state.scale() * 1000) / 1000;
                if (window->isHidden || window->needsGeometryRestore ||
                    window->lastRenderedX != std::round(physical.x) ||
                    window->lastRenderedY != std::round(physical.y) ||
                    window->lastRenderedScale != renderedScale) ++liveOverviewUpdates;
                const auto overview = m_renderer.renderOverview(*window, physical, state.scale(), now);
                if (!overview.succeeded()) {
                    std::cerr << "WindowManager: overview failed WID=" << window->wid()
                              << " PID=" << window->pid() << " scale=" << state.scale()
                              << " code=" << static_cast<int>(overview.code) << std::endl;
                    overviewFailed = true;
                    break;
                }
                continue;
            }
            const bool focused = m_focusedWindow && CFEqual(window->ref(), m_focusedWindow.get());
            window->preferNativePosition = !beingDragged && core::shouldPreferNativePosition(
                physical, displayBounds, display->usableBounds());
            const bool protectedWindow = focused || isWhitelisted(*window);
            const bool shouldRender = beingDragged || protectedWindow ||
                visibility.shouldRender(window->virtualRect, state.viewport(), focused);

            if (!shouldRender) {
                (void)m_renderer.hide(*window, physical, displayBounds, now, parkingPosition);
                continue;
            }
            (void)m_renderer.render(*window, physical, now);
        }
        if (overviewFailed) {
            std::cerr << "WindowManager: overview unavailable for a window; returning to native scale" << std::endl;
            display->state().resetZoom({state.geometry().bounds.x + state.geometry().bounds.w / 2,
                                        state.geometry().bounds.y + state.geometry().bounds.h / 2});
            (void)m_overviewPreviews.beginDisplay(display->id(), state.geometry().bounds, 1,
                false, config.rewindOnFocus, now, m_overviewWindowOrders[display->id()]);
            // Restore every already-scaled window in the same frame. The
            // ordinary renderer retains the transform/AX failure fallback.
            for (const auto& window : display->windowPool().windows()) {
                if (!window || !window->ref() || !window->virtualCoordinatesInitialized) continue;
                if (window->pinned) continue;
                if (window->applicationSuspended) continue;
                const auto physical = state.virtualToPhysical(window->virtualRect);
                const auto bounds = state.geometry().bounds;
                if (physical.right() <= bounds.x || physical.x >= bounds.right() ||
                    physical.bottom() <= bounds.y || physical.y >= bounds.bottom()) {
                    (void)m_renderer.hide(*window, physical, bounds, now, parkingPosition);
                    continue;
                }
                window->preferNativePosition = core::shouldPreferNativePosition(
                    physical, bounds, display->usableBounds());
                (void)m_renderer.render(*window, physical, now);
            }
        }
        m_overviewPreviews.finishDisplay(display->id());
    }
    if (m_overviewFocus && !overviewActive()) {
        const auto selected = std::exchange(m_overviewFocus, {});
        // Focus only after all presentation transforms have returned to 100%.
        NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:selected->pid()];
        [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        if (AXUIElementPerformAction(selected->ref(), kAXRaiseAction) != kAXErrorSuccess) {
            std::cerr << "WindowManager: failed to raise overview selection" << std::endl;
        }
    }
    if (traceOverview && renderedOverview) {
        auto& trace = m_overviewTrace;
        if (!trace.since) trace.since = now;
        const double seconds = CACurrentMediaTime() - now;
        trace.totalSeconds += seconds;
        trace.maxSeconds = std::max(trace.maxSeconds, seconds);
        trace.liveUpdates += liveOverviewUpdates;
        trace.previewFrames += previewFrames;
        ++trace.frames;
        if (now - trace.since >= 1) {
            const auto stats = m_overviewPreviews.stats();
            std::cout << "OVERVIEW frames=" << trace.frames
                      << " update-avg-ms=" << 1000 * trace.totalSeconds / trace.frames
                      << " update-max-ms=" << 1000 * trace.maxSeconds
                      << " live-updates=" << trace.liveUpdates
                      << " preview-draws=" << trace.previewFrames
                      << " images=" << stats.imageCount << " image-bytes=" << stats.imageBytes
                      << " captures=" << stats.captureCount << " capture-failures=" << stats.captureFailures
                      << std::endl;
            trace = {};
        }
    } else if (!renderedOverview) {
        m_overviewTrace = {};
    }
}

void WindowManager::centerWindow(std::shared_ptr<ClientWindow> window) {
    if (!window || !window->virtualCoordinatesInitialized) return;
    Display& display = displayForWindow(window->ref());
    const core::Rect bounds = display.state().geometry().bounds;
    window->positionAnimation = ClientWindow::PositionAnimation{
        {window->virtualRect.x, window->virtualRect.y},
        {display.camera().x() + bounds.w / display.state().scale() / 2.0f - window->virtualRect.w / 2.0f,
         display.camera().y() + bounds.h / display.state().scale() / 2.0f - window->virtualRect.h / 2.0f},
        CACurrentMediaTime()};
}

void WindowManager::advanceWindowAnimation(ClientWindow& window, double now, float speed, bool enabled) {
    if (!window.positionAnimation) return;
    auto& transition = *window.positionAnimation;
    if (!enabled) {
        window.virtualRect.x = transition.target.x;
        window.virtualRect.y = transition.target.y;
        window.lastProgrammaticMoveTime = now;
        window.positionAnimation.reset();
        return;
    }
    const double duration = 0.36 / std::clamp(static_cast<double>(speed), 0.1, 10.0);
    const double t = std::clamp((now - transition.startTime) / duration, 0.0, 1.0);
    const double progress = t * t * t * (10 + t * (-15 + t * 6));
    window.virtualRect.x = static_cast<float>(
        transition.from.x + (transition.target.x - transition.from.x) * progress);
    window.virtualRect.y = static_cast<float>(
        transition.from.y + (transition.target.y - transition.from.y) * progress);
    window.lastProgrammaticMoveTime = now;
    if (t == 1) {
        window.virtualRect.x = transition.target.x;
        window.virtualRect.y = transition.target.y;
        window.positionAnimation.reset();
    }
}

void WindowManager::centerCameraOnWindow(AXUIElementRef element) {
    m_focusedWindow = CFRef<AXUIElementRef>::retain(element);
    const auto window = findWindow(element);
    if (!overviewActive() && window && window->virtualCoordinatesInitialized && window->wid()) m_lastFocusedWindow = window;
    if (overviewActive() || m_nativePointerHeld || m_nativeCommitPending || m_isPanning || CACurrentMediaTime() < m_nativeCommitTime + 0.25) return;
    if (!window || !window->virtualCoordinatesInitialized) return;
    for (auto& display : m_displays) {
        if (!display->windowPool().findWindowByAXRef(element)) continue;
        const core::Rect bounds = display->state().geometry().bounds;
        display->state().animateCameraTo(
            core::Point{
                window->virtualRect.x - bounds.w / 2.0f + window->virtualRect.w / 2.0f,
                window->virtualRect.y - bounds.h / 2.0f + window->virtualRect.h / 2.0f});
        return;
    }
}

void WindowManager::centerCameraToFocusedWindow() {
    if (m_focusedWindow && isWindowOnIgnoredDisplay(m_focusedWindow.get())) return;
    auto focused = m_focusedWindow ? findWindow(m_focusedWindow.get()) : nullptr;
    if (!focused) focused = m_lastFocusedWindow.lock();
    if (focused) centerCameraOnWindow(focused->ref());
}

void WindowManager::centerFocusedWindowToCamera() {
    if (m_nativePointerHeld || m_nativeCommitPending || m_isPanning || overviewActive()) return;
    if (m_focusedWindow && isWindowOnIgnoredDisplay(m_focusedWindow.get())) return;
    auto window = m_focusedWindow ? findWindow(m_focusedWindow.get()) : nullptr;
    if (!window) window = m_lastFocusedWindow.lock();
    if (!window || !window->virtualCoordinatesInitialized || !findWindow(window->ref())) return;
    Display& display = displayForWindow(window->ref());
    centerWindow(window);
    updateWindows(display.id());
}

bool WindowManager::moveWindowToDisplay(const std::shared_ptr<ClientWindow>& window, Display& target,
                                        core::Rect physical) {
    if (!window || !window->ref()) return false;
    Display* source = nullptr;
    for (auto& display : m_displays) {
        if (display->windowPool().findWindowByAXRef(window->ref()) == window) {
            source = display.get();
            break;
        }
    }
    if (!source) return false;
    if (source == &target) return m_renderer.acceptNativeGeometry(*window, physical, target.state());
    if (target.windowPool().findWindowByAXRef(window->ref()) ||
        (window->wid() != 0 && target.windowPool().findWindowByWID(window->wid()))) return false;
    if (!target.windowPool().addExistingWindow(window)) return false;
    if (!m_renderer.acceptNativeGeometry(*window, physical, target.state())) {
        target.windowPool().removeWindow(window->ref());
        return false;
    }
    source->windowPool().removeWindow(window->ref());
    std::cout << "WindowManager: moved window WID=" << window->wid()
              << " to display " << target.id() << std::endl;
    return true;
}

bool WindowManager::releaseWindowToIgnoredDisplay(const std::shared_ptr<ClientWindow>& window,
                                                   core::Rect physical) {
    if (!window || !window->ref()) return false;
    Display* source = nullptr;
    for (auto& display : m_displays) {
        if (display->windowPool().findWindowByAXRef(window->ref()) == window) {
            source = display.get();
            break;
        }
    }
    if (!source) return false;
    if (!m_renderer.releaseToNative(*window, physical, CACurrentMediaTime()).succeeded()) {
        window->lastRenderedX = std::numeric_limits<float>::quiet_NaN();
        window->lastRenderedY = std::numeric_limits<float>::quiet_NaN();
        return false;
    }
    source->windowPool().removeWindow(window->ref());
    std::cout << "WindowManager: released window WID=" << window->wid()
              << " to ignored display" << std::endl;
    return true;
}

void WindowManager::syncPhysicalToVirtual(AXUIElementRef element) {
    if (overviewActive()) return; // Presentation scaling is never a native model resize.
    const auto window = findWindow(element);
    if (m_nativePointerHeld || m_nativeCommitPending) {
        if (window) addNativeCandidate(window);
        return;
    }
    if (isWindowOnIgnoredDisplay(element) && !window) return;
    if (!window || window->isHidden || window->needsGeometryRestore || window->positionNeedsVerification ||
        window->rejectedPosition || m_isPanning || window->positionAnimation) return;
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
        (void)m_renderer.acceptApplicationGeometry(*window, physical, display->state(),
                                                   m_yabaiBackend.hasTransform(window->wid()));
        return;
    }
}

void WindowManager::addNativeCandidate(const std::shared_ptr<ClientWindow>& window) {
    if (window) window->positionAnimation.reset();
    if (std::find(m_nativeCandidates.begin(), m_nativeCandidates.end(), window) == m_nativeCandidates.end()) {
        m_nativeCandidates.push_back(window);
    }
}

bool WindowManager::requestOverviewZoom(core::Point pointer, float delta) {
    if (!m_initialized || !m_yabaiBackend.supportsOverview() || m_nativePointerHeld || overviewReturning() ||
        !std::isfinite(delta) || !std::isfinite(pointer.x) || !std::isfinite(pointer.y) ||
        isIgnoredDisplayAtPoint(pointer)) return false;
    if (ConfigManager::instance().snapshot().invertZoomScrollDirection) delta = -delta;
    const auto id = displayForPoint(pointer).id();
    if (m_zoomRequest && m_zoomRequest->displayId == id) delta += m_zoomRequest->delta;
    m_zoomRequest = ZoomRequest{id, pointer, std::clamp(delta, -1000.0f, 1000.0f)};
    flushNativeInteractionForPan();
    return true;
}

bool WindowManager::overviewActive() const {
    if (m_zoomRequest || m_overviewExit) return true;
    for (const auto& display : m_displays) {
        if (display->state().overviewActive()) return true;
        for (const auto& window : display->windowPool().windows()) {
            if (window && window->overviewPresented) return true;
        }
    }
    return false;
}

bool WindowManager::overviewReturning() const {
    for (const auto& display : m_displays) if (display->state().returning()) return true;
    return false;
}

void WindowManager::exitOverview(core::Point pointer, bool selectWindow) {
    if (overviewActive() && !overviewReturning()) m_overviewExit = OverviewExit{pointer, selectWindow};
}

std::shared_ptr<ClientWindow> WindowManager::windowAtPoint(core::Point pointer) const {
    auto windows = CFRef<CFArrayRef>::adopt(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (CFIndex i = 0; windows && i < CFArrayGetCount(windows.get()); ++i) {
        auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows.get(), i));
        if (!info || CFGetTypeID(info) != CFDictionaryGetTypeID()) continue;
        auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(info, kCGWindowNumber));
        auto bounds = static_cast<CFDictionaryRef>(CFDictionaryGetValue(info, kCGWindowBounds));
        uint32_t wid = 0;
        CGRect frame{};
        if (!number || CFGetTypeID(number) != CFNumberGetTypeID() ||
            !CFNumberGetValue(number, kCGWindowIDCFNumberType, &wid) || !bounds ||
            CFGetTypeID(bounds) != CFDictionaryGetTypeID() || !CGRectMakeWithDictionaryRepresentation(bounds, &frame) ||
            !CGRectContainsPoint(frame, CGPointMake(pointer.x, pointer.y))) continue;
        if (m_overviewPreviews.ownsCanvasWindow(wid)) {
            if (auto preview = m_overviewPreviews.hitTest(pointer); preview &&
                !m_hiddenApplications.contains(preview->pid()) && findWindow(preview->ref()) == preview) return preview;
            continue;
        }
        for (const auto& display : m_displays) {
            if (auto window = display->windowPool().findWindowByWID(wid)) return window;
        }
    }
    return {};
}

void WindowManager::applyOverviewExit() {
    const auto request = *std::exchange(m_overviewExit, {});
    const auto mode = ConfigManager::instance().snapshot().zoomedEscCenter;
    m_overviewFocus = request.selectWindow ? windowAtPoint(request.pointer) : nullptr;
    if (!request.selectWindow && mode == "focus") {
        if (auto focused = m_lastFocusedWindow.lock(); focused && focused->virtualCoordinatesInitialized &&
            !focused->applicationSuspended && !m_hiddenApplications.contains(focused->pid()) && findWindow(focused->ref())) {
            m_overviewFocus = focused;
        }
    }
    m_zoomRequest.reset();
    for (auto& display : m_displays) {
        const auto bounds = display->state().geometry().bounds;
        std::optional<core::Point> target;
        std::optional<core::Point> anchor;
        if (m_overviewFocus && display->windowPool().findWindowByWID(m_overviewFocus->wid())) {
            const auto frame = m_overviewFocus->virtualRect;
            target = core::Point{frame.x + frame.w / 2 - bounds.w / 2, frame.y + frame.h / 2 - bounds.h / 2};
        }
        if (!request.selectWindow && mode == "mouse" && displayForPoint(request.pointer).id() == display->id()) anchor = request.pointer;
        if ((display->state().overviewActive() || target) && !display->state().beginReturn(target, anchor)) {
            display->state().resetZoom({bounds.x + bounds.w / 2, bounds.y + bounds.h / 2});
        }
    }
}

void WindowManager::beginNativeInteraction(core::Point pointer) {
    if (!m_nativeCommitPending) {
        m_nativeCameras.clear();
        m_nativeCandidates.clear();
        m_nativeStartFrames.clear();
        m_nativeWindowDragged = false;
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
                m_nativeStartFrames[window.get()] = core::Rect{
                    static_cast<float>(frame.origin.x), static_cast<float>(frame.origin.y),
                    static_cast<float>(frame.size.width), static_cast<float>(frame.size.height)};
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

void WindowManager::noteNativeDrag() {
    if (m_nativePointerHeld && !m_nativeStartFrames.empty()) m_nativeWindowDragged = true;
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
    m_nativeWindowDragged = false;
    m_nativeStartFrames.clear();
    m_nativeCandidates.clear();
}

bool WindowManager::beginDragEverywhere(core::Point pointer) {
    if (!m_initialized || overviewReturning() || isIgnoredDisplayAtPoint(pointer)) return false;
    auto window = windowAtPoint(pointer);
    const bool previewHit = window && m_overviewPreviews.hitTest(pointer) == window;
    if (!window || !window->virtualCoordinatesInitialized || window->pinned || (window->isHidden && !previewHit) ||
        window->applicationSuspended || window->needsGeometryRestore) return false;
    m_draggedWindow = std::move(window);
    m_draggedWindowDisplayId = displayForWindow(m_draggedWindow->ref()).id();
    m_dragEverywhereMoved = false;
    m_dragStartVirtualRect = m_draggedWindow->virtualRect;
    const core::Rect physical = displayForWindow(m_draggedWindow->ref()).state().virtualToPhysical(m_draggedWindow->virtualRect);
    CGPoint visualOrigin{physical.x, physical.y};
    // A preview's original is parked off-screen; its visible origin comes from
    // the model, never from the original's current WindowServer coordinates.
    if (!previewHit) (void)readWindowPosition(m_draggedWindow->ref(), m_draggedWindow->wid(), visualOrigin);
    m_dragPointerOffset = {pointer.x - static_cast<float>(visualOrigin.x),
                           pointer.y - static_cast<float>(visualOrigin.y)};
    m_draggedWindow->positionAnimation.reset();
    return true;
}

void WindowManager::dragWindowTo(core::Point pointer) {
    if (!m_draggedWindow || !std::isfinite(pointer.x) || !std::isfinite(pointer.y)) return;
    Display* display = displayById(m_draggedWindowDisplayId);
    if (!display) return;
    const auto virtualPoint = display->state().physicalToVirtual(
        core::Point{pointer.x - m_dragPointerOffset.x, pointer.y - m_dragPointerOffset.y});
    if (!std::isfinite(virtualPoint.x) || !std::isfinite(virtualPoint.y)) return;
    if (virtualPoint.x != m_draggedWindow->virtualRect.x ||
        virtualPoint.y != m_draggedWindow->virtualRect.y) m_dragEverywhereMoved = true;
    m_draggedWindow->virtualRect.x = virtualPoint.x;
    m_draggedWindow->virtualRect.y = virtualPoint.y;
}

void WindowManager::endDragEverywhere(core::Point pointer) {
    if (m_draggedWindow && m_dragEverywhereMoved) {
        if (Display* source = displayById(m_draggedWindowDisplayId)) {
            const core::Rect physical = source->state().virtualToPhysical(m_draggedWindow->virtualRect);
            const core::Point center{physical.x + physical.w / 2.0f,
                                     physical.y + physical.h / 2.0f};
            bool transferred = false;
            bool requestedTransfer = false;
            if (isIgnoredDisplayAtPoint(center)) {
                requestedTransfer = true;
                transferred = releaseWindowToIgnoredDisplay(m_draggedWindow, physical);
            } else {
                Display& target = displayForPoint(pointer);
                requestedTransfer = &target != source;
                transferred = requestedTransfer && moveWindowToDisplay(m_draggedWindow, target, physical);
            }
            if (transferred) {
                // Drag-everywhere updates virtual geometry before the native
                // frame is guaranteed to reach its final position.
                m_draggedWindow->lastRenderedX = std::numeric_limits<float>::quiet_NaN();
                m_draggedWindow->lastRenderedY = std::numeric_limits<float>::quiet_NaN();
            } else if (requestedTransfer && m_dragStartVirtualRect) {
                // The native handoff failed; keep the managed model on its
                // original canvas instead of parking it beyond the desktop.
                m_draggedWindow->virtualRect = *m_dragStartVirtualRect;
            }
        }
    }
    m_draggedWindow.reset();
    m_draggedWindowDisplayId = 0;
    m_dragEverywhereMoved = false;
    m_dragStartVirtualRect.reset();
}

void WindowManager::cancelDragEverywhere() {
    if (m_draggedWindow && m_dragStartVirtualRect) {
        m_draggedWindow->virtualRect = *m_dragStartVirtualRect;
    }
    m_draggedWindow.reset();
    m_draggedWindowDisplayId = 0;
    m_dragEverywhereMoved = false;
    m_dragStartVirtualRect.reset();
}

void WindowManager::commitNativeInteraction() {
    for (const auto& window : m_nativeCandidates) {
        if (!window || !window->ref() || !window->virtualCoordinatesInitialized || window->isHidden ||
            window->needsGeometryRestore) continue;
        Display& source = displayForWindow(window->ref());
        core::DisplayState observationState = source.state();
        if (const auto camera = m_nativeCameras.find(source.id()); camera != m_nativeCameras.end()) {
            observationState.camera().setPosition(camera->second.x, camera->second.y);
        }
        CGPoint position{};
        if (!readWindowPosition(window->ref(), m_yabaiBackend.usesTransforms() ? window->wid() : 0, position)) continue;
        core::Rect physical{static_cast<float>(position.x), static_cast<float>(position.y),
                            window->virtualRect.w, window->virtualRect.h};
        CGSize size{};
        if (readAXSize(window->ref(), size) && std::isfinite(size.width) &&
            std::isfinite(size.height) && size.width > 0 && size.height > 0) {
            physical.w = static_cast<float>(size.width);
            physical.h = static_cast<float>(size.height);
        }
        const core::Point center{physical.x + physical.w / 2.0f,
                                 physical.y + physical.h / 2.0f};
        const bool targetIgnored = isIgnoredDisplayAtPoint(center);
        const auto start = m_nativeStartFrames.find(window.get());
        const auto cameraAtStart = m_nativeCameras.find(source.id());
        const bool cameraUnchanged = cameraAtStart != m_nativeCameras.end() &&
            std::abs(source.camera().x() - cameraAtStart->second.x) <= 0.01f &&
            std::abs(source.camera().y() - cameraAtStart->second.y) <= 0.01f;
        bool accepted = false;
        if (targetIgnored) {
            if (start != m_nativeStartFrames.end() &&
                core::shouldReleaseToIgnoredDisplay(m_nativeWindowDragged, cameraUnchanged,
                                                    start->second, physical, true)) {
                accepted = releaseWindowToIgnoredDisplay(window, physical);
            }
        } else {
            Display& target = displayForPoint(center);
            const bool transfer = start != m_nativeStartFrames.end() &&
                core::shouldTransferWindow(m_nativeWindowDragged, cameraUnchanged, start->second,
                                           physical, source.id(), target.id());
            accepted = transfer
                ? moveWindowToDisplay(window, target, physical)
                : m_renderer.acceptNativeGeometry(*window, physical, observationState);
        }
        if (std::getenv("MINFWM_TRACE_WINDOW_INPUT")) {
            std::cout << "INPUT drop WID=" << window->wid() << " physical=" << physical.x << ',' << physical.y
                      << " camera=" << observationState.camera().x() << ',' << observationState.camera().y()
                      << " virtual=" << window->virtualRect.x << ',' << window->virtualRect.y
                      << " accepted=" << accepted << std::endl;
        }
    }
    m_nativeCommitPending = false;
    m_nativeWindowDragged = false;
    m_nativeCameras.clear();
    m_nativeCandidates.clear();
    m_nativeStartFrames.clear();
}

} // namespace minfwm
