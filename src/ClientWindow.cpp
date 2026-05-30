#include "ClientWindow.hpp"
#include "WindowManager.hpp"
#include <iostream>
#include <string>

extern "C" AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *out);

std::string GetWindowTitle(AXUIElementRef windowRef)
{
    CFTypeRef titleRef = nullptr;
    if (AXUIElementCopyAttributeValue(windowRef, kAXTitleAttribute, &titleRef) == kAXErrorSuccess && titleRef)
    {
        char buffer[256];
        if (CFStringGetCString((CFStringRef)titleRef, buffer, sizeof(buffer), kCFStringEncodingUTF8))
        {
            CFRelease(titleRef);
            return std::string(buffer);
        }
        CFRelease(titleRef);
    }
    return "Unknown";
}

ClientWindow::ClientWindow(AXUIElementRef windowRef)
{
    // CFRetain is necessary because we are storing the reference
    m_windowRef = (AXUIElementRef)CFRetain(windowRef);

    // Get the window ID for SkyLight transforms
    if (_AXUIElementGetWindow(m_windowRef, &wid) != kAXErrorSuccess) {
        wid = 0;
    }

    CGSize size = {1200, 800}; // Sane default
    CFTypeRef sizeRef = nullptr;
    if (AXUIElementCopyAttributeValue(m_windowRef, kAXSizeAttribute, &sizeRef) == kAXErrorSuccess)
    {
        if (AXValueGetValue((AXValueRef)sizeRef, (AXValueType)kAXValueCGSizeType, &size))
        {
            double scale = WindowManager::GetInstance().GetCamera().GetScale();
            width = size.width / scale;
            height = size.height / scale;
        }
        CFRelease(sizeRef);
    }
    else {
        width = 1200;
        height = 800;
    }

    CGPoint position = {0, 0};
    CFTypeRef positionRef = nullptr;
    if (AXUIElementCopyAttributeValue(m_windowRef, kAXPositionAttribute, &positionRef) == kAXErrorSuccess)
    {
        if (AXValueGetValue((AXValueRef)positionRef, (AXValueType)kAXValueCGPointType, &position))
        {
            double scale = WindowManager::GetInstance().GetCamera().GetScale();
            absolute_x = position.x / scale + WindowManager::GetInstance().GetCamera().GetX();
            absolute_y = position.y / scale + WindowManager::GetInstance().GetCamera().GetY();
        }
        CFRelease(positionRef);
    }
    else {
        // If we can't get position, we might be in trouble, but let's at least not use (0,0)
        // which might overlap with other windows being tiled.
        // Actually, if we are at (0,0), it's probably better than some random place.
        absolute_x = WindowManager::GetInstance().GetCamera().GetX();
        absolute_y = WindowManager::GetInstance().GetCamera().GetY();
    }

    // Determine if the window should float (e.g. popups, dialogs, non-standard windows)
    CFTypeRef subroleRef = nullptr;
    if (AXUIElementCopyAttributeValue(m_windowRef, kAXSubroleAttribute, &subroleRef) == kAXErrorSuccess)
    {
        if (subroleRef)
        {
            if (CFStringCompare((CFStringRef)subroleRef, kAXStandardWindowSubrole, 0) != kCFCompareEqualTo)
            {
                is_floating = true;
            }
            CFRelease(subroleRef);
        }
    }

    std::string title = GetWindowTitle(m_windowRef);
    std::cout << "Tracked Window [" << title << "] at absolute (" << absolute_x << ", " << absolute_y << ")" << (is_floating ? " [FLOATING]" : "") << std::endl;
}

ClientWindow::~ClientWindow()
{
    if (m_windowRef)
    {
        // Release the stored CoreFoundation object to prevent memory leaks
        CFRelease(m_windowRef);
        m_windowRef = nullptr;
    }
}
