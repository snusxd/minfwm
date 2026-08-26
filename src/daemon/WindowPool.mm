#include "WindowPool.hpp"
#import <AppKit/AppKit.h>
#include <algorithm>
#include <dlfcn.h>
#include <iostream>
#include <string>

namespace minfwm {

namespace {

using PrivateWindowIdResolver = AXError (*)(AXUIElementRef, std::uint32_t*);

std::uint32_t resolveOptionalWindowId(AXUIElementRef windowRef) noexcept {
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
        CGPoint pos = { 0.0, 0.0 };
        readPoint(m_windowRef.get(), kAXPositionAttribute, pos);

        CGSize size = { 0.0, 0.0 };
        readSize(m_windowRef.get(), kAXSizeAttribute, size);

        virtualRect = { static_cast<float>(pos.x), static_cast<float>(pos.y),
                        static_cast<float>(size.width), static_cast<float>(size.height) };

        pid_t pid = 0;
        std::string appName = "Unknown";
        if (AXUIElementGetPid(m_windowRef.get(), &pid) == kAXErrorSuccess && pid > 0) {
            NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            NSString* localizedName = app.localizedName;
            const char* utf8Name = [localizedName UTF8String];
            if (utf8Name) appName = utf8Name;
        }

        std::cout << "WindowPool: Added window WID:" << m_wid << " [" << appName
                  << "] at " << pos.x << "," << pos.y << std::endl;
    } catch (...) {
        m_windowRef.reset();
        throw;
    }
}

ClientWindow::~ClientWindow() noexcept = default;

WindowPool::WindowPool(WindowIdResolver windowIdResolver)
    : m_windowIdResolver(windowIdResolver ? windowIdResolver : &WindowPool::defaultWindowIdResolver) {}

WindowPool::WindowIdResolver WindowPool::optionalWindowIdResolver() noexcept {
    return &resolveOptionalWindowId;
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
