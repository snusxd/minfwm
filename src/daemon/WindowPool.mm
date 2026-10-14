#include "WindowPool.hpp"
#import <AppKit/AppKit.h>
#include <algorithm>
#include <cmath>
#include <dlfcn.h>
#include <iostream>
#include <string>

namespace minfwm {

namespace {

using PrivateWindowIdResolver = AXError (*)(AXUIElementRef, std::uint32_t*);

std::uint32_t resolveYabaiWindowId(AXUIElementRef windowRef) noexcept {
    if (!windowRef) return 0;

    static const PrivateWindowIdResolver resolver = reinterpret_cast<PrivateWindowIdResolver>(
        dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow"));
    if (!resolver) return 0;

    std::uint32_t wid = 0;
    if (resolver(windowRef, &wid) != kAXErrorSuccess) return 0;
    return wid;
}

bool readPoint(AXUIElementRef windowRef, CFStringRef attribute, CGPoint& point) noexcept {
    CFRef<CFTypeRef> value;
    if (AXUIElementCopyAttributeValue(windowRef, attribute, value.put()) != kAXErrorSuccess || !value) {
        return false;
    }

    const bool read = CFGetTypeID(value.get()) == AXValueGetTypeID() &&
                      AXValueGetType(static_cast<AXValueRef>(value.get())) == kAXValueTypeCGPoint &&
                      AXValueGetValue(static_cast<AXValueRef>(value.get()), kAXValueTypeCGPoint, &point);
    return read;
}

bool readSize(AXUIElementRef windowRef, CFStringRef attribute, CGSize& size) noexcept {
    CFRef<CFTypeRef> value;
    if (AXUIElementCopyAttributeValue(windowRef, attribute, value.put()) != kAXErrorSuccess || !value) {
        return false;
    }

    const bool read = CFGetTypeID(value.get()) == AXValueGetTypeID() &&
                      AXValueGetType(static_cast<AXValueRef>(value.get())) == kAXValueTypeCGSize &&
                      AXValueGetValue(static_cast<AXValueRef>(value.get()), kAXValueTypeCGSize, &size);
    return read;
}

} // namespace

ClientWindow::ClientWindow(AXUIElementRef windowRef)
    : ClientWindow(windowRef, 0) {}

ClientWindow::ClientWindow(AXUIElementRef windowRef, std::uint32_t windowId)
    : m_windowRef(CFRef<AXUIElementRef>::retain(windowRef)), m_wid(windowId) {
    if (!m_windowRef) return;

    try {
        (void)captureInitialGeometry();

        std::string appName = "Unknown";
        if (AXUIElementGetPid(m_windowRef.get(), &m_pid) == kAXErrorSuccess && m_pid > 0) {
            NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:m_pid];
            NSString* localizedName = app.localizedName;
            const char* utf8Name = [localizedName UTF8String];
            if (utf8Name) appName = utf8Name;
        }

        std::cout << "WindowPool: Added window WID:" << m_wid << " [" << appName
                  << "] at " << virtualRect.x << "," << virtualRect.y << std::endl;
    } catch (...) {
        m_windowRef.reset();
        throw;
    }
}

ClientWindow::~ClientWindow() noexcept = default;

bool ClientWindow::captureInitialGeometry() {
    if (originalPhysicalRect) return true;
    if (!m_windowRef) return false;
    CGPoint position{};
    CGSize size{};
    if (!readPoint(m_windowRef.get(), kAXPositionAttribute, position) ||
        !readSize(m_windowRef.get(), kAXSizeAttribute, size)) return false;
    const VirtualRect physical{static_cast<float>(position.x), static_cast<float>(position.y),
                               static_cast<float>(size.width), static_cast<float>(size.height)};
    if (!std::isfinite(physical.x) || !std::isfinite(physical.y) ||
        !std::isfinite(physical.w) || !std::isfinite(physical.h) || physical.w <= 0 || physical.h <= 0) return false;
    virtualRect = physical;
    originalPhysicalRect = physical;
    CFRef<CFTypeRef> subrole;
    if (AXUIElementCopyAttributeValue(m_windowRef.get(), kAXSubroleAttribute, subrole.put()) == kAXErrorSuccess &&
        subrole && CFGetTypeID(subrole.get()) == CFStringGetTypeID()) {
        isAuxiliaryWindow = !CFEqual(subrole.get(), kAXStandardWindowSubrole);
    }
    lastRenderedX = physical.x;
    lastRenderedY = physical.y;
    return true;
}

WindowPool::WindowPool(WindowIdResolver windowIdResolver)
    : m_windowIdResolver(windowIdResolver ? windowIdResolver : &WindowPool::defaultWindowIdResolver) {}

WindowPool::WindowIdResolver WindowPool::yabaiWindowIdResolver() noexcept {
    return &resolveYabaiWindowId;
}

std::shared_ptr<ClientWindow> WindowPool::addWindow(AXUIElementRef windowRef) {
    if (!windowRef) return nullptr;

    if (auto existing = findWindowByAXRef(windowRef)) return existing;

    const std::uint32_t wid = m_windowIdResolver(windowRef);
    if (wid != 0) {
        if (auto existing = findWindowByWID(wid)) return existing;
    }

    auto window = std::make_shared<ClientWindow>(windowRef, wid);
    m_windows.push_back(window);

    try {
        const auto [refEntry, refInserted] = m_windowsByAXRef.emplace(window->ref(), window);
        if (!refInserted) {
            m_windows.pop_back();
            return refEntry->second;
        }

        if (wid != 0) {
            const auto [widEntry, widInserted] = m_windowsByWID.emplace(wid, window);
            if (!widInserted) {
                m_windowsByAXRef.erase(refEntry);
                m_windows.pop_back();
                return widEntry->second;
            }
        }
    } catch (...) {
        if (wid != 0) m_windowsByWID.erase(wid);
        m_windowsByAXRef.erase(window->ref());
        m_windows.pop_back();
        throw;
    }

    return window;
}

void WindowPool::removeWindow(AXUIElementRef windowRef) {
    auto window = findWindowByAXRef(windowRef);
    if (!window && windowRef) {
        const std::uint32_t wid = m_windowIdResolver(windowRef);
        if (wid != 0) window = findWindowByWID(wid);
    }
    if (!window) return;

    m_windowsByAXRef.erase(window->ref());
    if (window->wid() != 0) {
        const auto widEntry = m_windowsByWID.find(window->wid());
        if (widEntry != m_windowsByWID.end() && widEntry->second == window) {
            m_windowsByWID.erase(widEntry);
        }
    }

    const auto windowEntry = std::find_if(
        m_windows.begin(), m_windows.end(),
        [&](const std::shared_ptr<ClientWindow>& candidate) { return candidate == window; });
    if (windowEntry != m_windows.end()) m_windows.erase(windowEntry);
}

void WindowPool::removeWindowsForPid(pid_t pid) {
    if (pid <= 0) return;
    // Copy the matching owners before removeWindow mutates the vector/indexes.
    std::vector<std::shared_ptr<ClientWindow>> removed;
    for (const auto& window : m_windows) {
        if (window->pid() == pid) removed.push_back(window);
    }
    for (const auto& window : removed) removeWindow(window->ref());
}

std::vector<std::shared_ptr<ClientWindow>> WindowPool::removeMissingWindows(const std::unordered_set<uint32_t>& liveIds) {
    std::vector<std::shared_ptr<ClientWindow>> removed;
    for (const auto& window : m_windows) {
        if (window->wid() && !liveIds.contains(window->wid())) removed.push_back(window);
    }
    for (const auto& window : removed) removeWindow(window->ref());
    return removed;
}

std::vector<std::shared_ptr<ClientWindow>> WindowPool::removeUnlistedWindows(pid_t pid, const std::vector<AXUIElementRef>& liveWindows) {
    std::vector<std::shared_ptr<ClientWindow>> removed;
    if (pid <= 0) return removed;
    for (const auto& window : m_windows) {
        if (window->pid() != pid) continue;
        const bool listed = std::any_of(liveWindows.begin(), liveWindows.end(),
            [&](AXUIElementRef ref) { return ref && CFEqual(window->ref(), ref); });
        if (!listed) removed.push_back(window);
    }
    for (const auto& window : removed) removeWindow(window->ref());
    return removed;
}

std::shared_ptr<ClientWindow> WindowPool::findWindowByWID(std::uint32_t wid) const {
    if (wid == 0) return nullptr;

    const auto entry = m_windowsByWID.find(wid);
    return entry == m_windowsByWID.end() ? nullptr : entry->second;
}

std::shared_ptr<ClientWindow> WindowPool::findWindowByAXRef(AXUIElementRef windowRef) const {
    if (!windowRef) return nullptr;

    const auto entry = m_windowsByAXRef.find(windowRef);
    return entry == m_windowsByAXRef.end() ? nullptr : entry->second;
}

std::size_t WindowPool::AXRefHash::operator()(AXUIElementRef ref) const noexcept {
    return ref ? static_cast<std::size_t>(CFHash(ref)) : 0;
}

bool WindowPool::AXRefEqual::operator()(AXUIElementRef lhs, AXUIElementRef rhs) const noexcept {
    return lhs == rhs || (lhs && rhs && CFEqual(lhs, rhs));
}

std::uint32_t WindowPool::defaultWindowIdResolver(AXUIElementRef windowRef) noexcept {
    (void)windowRef;
    return 0;
}

} // namespace minfwm
