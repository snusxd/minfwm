#include "WindowManager.hpp"
#include "YabaiSA.hpp"
#include "ConfigManager.hpp"
#import <AppKit/AppKit.h>
#include <iostream>

namespace minfwm {

void WindowManager::initialize() {
    std::cout << "WindowManager: Initializing..." << std::endl;
    ConfigManager::instance().load();
    for (NSScreen* screen in [NSScreen screens]) {
        NSDictionary* description = [screen deviceDescription];
        NSNumber* displayID = [description objectForKey:@"NSScreenNumber"];
        m_displays.push_back(std::make_unique<Display>([displayID longLongValue]));
        std::cout << "WindowManager: Display " << [displayID longLongValue] 
                  << " [" << screen.frame.size.width << "x" << screen.frame.size.height << "]" << std::endl;
    }
}

Display& WindowManager::displayForWindow(AXUIElementRef window) {
    CGPoint pos;
    CFTypeRef posValue = NULL;
    if (AXUIElementCopyAttributeValue(window, kAXPositionAttribute, (CFTypeRef*)&posValue) == kAXErrorSuccess) {
        AXValueGetValue((AXValueRef)posValue, kAXValueTypeCGPoint, &pos);
        CFRelease(posValue);
        for (auto& display : m_displays) {
            for (NSScreen* screen in [NSScreen screens]) {
                if ([[[screen deviceDescription] objectForKey:@"NSScreenNumber"] longLongValue] == display->id()) {
                    if (NSPointInRect(pos, [screen frame])) return *display;
                }
            }
        }
    }
    return *m_displays[0];
}

std::shared_ptr<ClientWindow> WindowManager::findWindow(AXUIElementRef element) {
    for (auto& display : m_displays) {
        for (auto& window : display->windowPool().windows()) {
            if (CFEqual(window->ref(), element)) return window;
        }
    }
    return nullptr;
}

void WindowManager::removeWindow(AXUIElementRef element) {
    for (auto& display : m_displays) display->windowPool().removeWindow(element);
}

void WindowManager::updateWindows() {
    AXUIElementRef focusedWindow = NULL;
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute, (CFTypeRef*)&focusedWindow);
    CFRelease(systemWide);

    for (auto& display : m_displays) {
        float cx = display->camera().x();
        float cy = display->camera().y();
        
        NSScreen* targetScreen = nil;
        for (NSScreen* screen in [NSScreen screens]) {
            if ([[[screen deviceDescription] objectForKey:@"NSScreenNumber"] longLongValue] == display->id()) {
                targetScreen = screen; break;
            }
        }
        if (!targetScreen) continue;

        float sw = targetScreen.frame.size.width;
        float sh = targetScreen.frame.size.height;
        float sx = targetScreen.frame.origin.x;
        float primaryScreenHeight = (float)[[NSScreen screens][0] frame].size.height;
        float sy = primaryScreenHeight - targetScreen.frame.origin.y - sh;
        float buffer = ConfigManager::instance().overscanBufferPx;

        for (auto& window : display->windowPool().windows()) {
            float px = window->virtualRect.x - cx;
            float py = window->virtualRect.y - cy;
            bool is_focused = (focusedWindow && CFEqual(window->ref(), focusedWindow));
            bool in_viewport = (px + window->virtualRect.w > -buffer && px < sw + buffer &&
                                py + window->virtualRect.h > -buffer && py < sh + buffer);
            
            if (in_viewport || is_focused) {
                float targetX = px + sx;
                float targetY = py + sy;

                if (window->lastRenderedX != targetX || window->lastRenderedY != targetY) {
                    // 1. Native AXAPI (Robust)
                    CGPoint targetPos = CGPointMake(targetX, targetY);
                    AXValueRef axPos = AXValueCreate(kAXValueTypeCGPoint, &targetPos);
                    AXUIElementSetAttributeValue(window->ref(), kAXPositionAttribute, axPos);
                    CFRelease(axPos);

                    // 2. Yabai SA (Menu bar bypass)
                    if (window->wid() != 0) {
                        YabaiSA::moveWindow(window->wid(), (int)targetX, (int)targetY);
                    }

                    window->lastRenderedX = targetX;
                    window->lastRenderedY = targetY;
                }
            } else {
                if (window->lastRenderedX != -25000) {
                    CGPoint hidePos = CGPointMake(-25000, -25000);
                    AXValueRef axPos = AXValueCreate(kAXValueTypeCGPoint, &hidePos);
                    AXUIElementSetAttributeValue(window->ref(), kAXPositionAttribute, axPos);
                    CFRelease(axPos);

                    if (window->wid() != 0) {
                        YabaiSA::moveWindow(window->wid(), -25000, -25000);
                    }
                    
                    window->lastRenderedX = -25000;
                    window->lastRenderedY = -25000;
                }
            }
        }
    }
    if (focusedWindow) CFRelease(focusedWindow);
}

void WindowManager::centerWindow(std::shared_ptr<ClientWindow> window) {
    Display& display = displayForWindow(window->ref());
    NSScreen* targetScreen = nil;
    for (NSScreen* screen in [NSScreen screens]) {
        if ([[[screen deviceDescription] objectForKey:@"NSScreenNumber"] longLongValue] == display.id()) {
            targetScreen = screen; break;
        }
    }
    if (!targetScreen) return;
    window->virtualRect.x = display.camera().x() + (targetScreen.frame.size.width / 2.0f) - (window->virtualRect.w / 2.0f);
    window->virtualRect.y = display.camera().y() + (targetScreen.frame.size.height / 2.0f) - (window->virtualRect.h / 2.0f);
}

void WindowManager::centerCameraOnWindow(AXUIElementRef element) {
    auto window = findWindow(element);
    if (!window) return;
    for (auto& display : m_displays) {
        bool found = false;
        for (auto& w : display->windowPool().windows()) if (w == window) { found = true; break; }
        if (!found) continue;
        NSScreen* targetScreen = nil;
        for (NSScreen* screen in [NSScreen screens]) {
            if ([[[screen deviceDescription] objectForKey:@"NSScreenNumber"] longLongValue] == display->id()) {
                targetScreen = screen; break;
            }
        }
        if (!targetScreen) continue;
        display->camera().setPosition(
            window->virtualRect.x - (targetScreen.frame.size.width / 2.0f) + (window->virtualRect.w / 2.0f),
            window->virtualRect.y - (targetScreen.frame.size.height / 2.0f) + (window->virtualRect.h / 2.0f)
        );
        updateWindows();
        break;
    }
}

void WindowManager::syncPhysicalToVirtual(AXUIElementRef element) {
    auto window = findWindow(element);
    if (!window) return;
    for (auto& display : m_displays) {
        bool found = false;
        for (auto& w : display->windowPool().windows()) if (w == window) { found = true; break; }
        if (!found) continue;
        CGPoint pos; CFTypeRef posValue = NULL;
        if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute, (CFTypeRef*)&posValue) == kAXErrorSuccess) {
            AXValueGetValue((AXValueRef)posValue, kAXValueTypeCGPoint, &pos);
            CFRelease(posValue);
            NSScreen* targetScreen = nil;
            for (NSScreen* screen in [NSScreen screens]) {
                if ([[[screen deviceDescription] objectForKey:@"NSScreenNumber"] longLongValue] == display->id()) {
                    targetScreen = screen; break;
                }
            }
            if (!targetScreen) continue;
            float sx = targetScreen.frame.origin.x;
            float sy = (float)[[NSScreen screens][0] frame].size.height - targetScreen.frame.origin.y - targetScreen.frame.size.height;
            window->virtualRect.x = (float)pos.x - sx + display->camera().x();
            window->virtualRect.y = (float)pos.y - sy + display->camera().y();
        }
        CGSize size; CFTypeRef sizeValue = NULL;
        if (AXUIElementCopyAttributeValue(element, kAXSizeAttribute, (CFTypeRef*)&sizeValue) == kAXErrorSuccess) {
            AXValueGetValue((AXValueRef)sizeValue, kAXValueTypeCGSize, &size);
            CFRelease(sizeValue);
            window->virtualRect.w = (float)size.width;
            window->virtualRect.h = (float)size.height;
        }
        break;
    }
}

} // namespace minfwm
