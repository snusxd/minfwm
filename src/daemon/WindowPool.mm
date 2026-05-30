#include "WindowPool.hpp"
#import <AppKit/AppKit.h>
#include <iostream>
#include <algorithm>

namespace minfwm {

ClientWindow::ClientWindow(AXUIElementRef windowRef) : m_windowRef(windowRef), m_wid(0) {
    CFRetain(m_windowRef);
    _AXUIElementGetWindow(m_windowRef, &m_wid);
    
    CGPoint pos = {0, 0};
    m_lastPositionValue = NULL;
    if (AXUIElementCopyAttributeValue(m_windowRef, kAXPositionAttribute, (CFTypeRef*)&m_lastPositionValue) == kAXErrorSuccess) {
        AXValueGetValue((AXValueRef)m_lastPositionValue, kAXValueTypeCGPoint, &pos);
    }
    
    CGSize size = {0, 0};
    m_lastSizeValue = NULL;
    if (AXUIElementCopyAttributeValue(m_windowRef, kAXSizeAttribute, (CFTypeRef*)&m_lastSizeValue) == kAXErrorSuccess) {
        AXValueGetValue((AXValueRef)m_lastSizeValue, kAXValueTypeCGSize, &size);
    }

    virtualRect = { (float)pos.x, (float)pos.y, (float)size.width, (float)size.height };
    
    pid_t pid;
    AXUIElementGetPid(m_windowRef, &pid);
    NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    std::string appName = app ? [app.localizedName UTF8String] : "Unknown";
    
    std::cout << "WindowPool: Added window WID:" << m_wid << " [" << appName << "] at " << pos.x << "," << pos.y << std::endl;
}

ClientWindow::~ClientWindow() {
    if (m_lastPositionValue) CFRelease(m_lastPositionValue);
    if (m_lastSizeValue) CFRelease(m_lastSizeValue);
    if (m_windowRef) CFRelease(m_windowRef);
}

std::shared_ptr<ClientWindow> WindowPool::addWindow(AXUIElementRef windowRef) {
    auto window = std::make_shared<ClientWindow>(windowRef);
    m_windows.push_back(window);
    return window;
}

void WindowPool::removeWindow(AXUIElementRef windowRef) {
    m_windows.erase(
        std::remove_if(m_windows.begin(), m_windows.end(),
            [&](const std::shared_ptr<ClientWindow>& w) {
                return CFEqual(w->ref(), windowRef);
            }),
        m_windows.end());
}

} // namespace minfwm
