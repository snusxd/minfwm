#include "WindowManager.hpp"
#include "YabaiSA.hpp"
#include "ConfigManager.hpp"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <iostream>

namespace minfwm {

void WindowManager::initialize() {
    std::cout << "WindowManager: Initializing (with Hide-in-Corner)..." << std::endl;
    ConfigManager::instance().load();
    for (NSScreen* screen in [NSScreen screens]) {
        NSDictionary* description = [screen deviceDescription];
        NSNumber* displayID = [description objectForKey:@"NSScreenNumber"];
        m_displays.push_back(std::make_unique<Display>([displayID longLongValue]));
        std::cout << "WindowManager: Found Display ID " << [displayID longLongValue] 
                  << " [" << screen.frame.size.width << "x" << screen.frame.size.height << "]" << std::endl;
    }
}

Display& WindowManager::displayForWindow(AXUIElementRef window) {
    CGPoint pos; CFTypeRef posValue = NULL;
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

    double now = CACurrentMediaTime();

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

        NSRect screenFrame = [targetScreen frame];
        float sw = screenFrame.size.width;
        float sh = screenFrame.size.height;
        float sx = screenFrame.origin.x;
        float primaryScreenHeight = (float)[[NSScreen screens][0] frame].size.height;
        float sy = primaryScreenHeight - screenFrame.origin.y - sh;
        float buffer = ConfigManager::instance().overscanBufferPx;

        for (auto& window : display->windowPool().windows()) {
            float px = window->virtualRect.x - cx;
            float py = window->virtualRect.y - cy;
            bool is_focused = (focusedWindow && CFEqual(window->ref(), focusedWindow));
            
            // Intersection math with camera viewport
            bool in_viewport = (px + window->virtualRect.w > -buffer && px < sw + buffer &&
                                py + window->virtualRect.h > -buffer && py < sh + buffer);
            
            if (in_viewport || is_focused) {
                float targetX = px + sx;
                float targetY = py + sy;

                if (window->isHidden || window->lastRenderedX != targetX || window->lastRenderedY != targetY) {
                    window->lastProgrammaticMoveTime = now;
                    
                    // 1. Move to physical position
                    CGPoint targetPos = CGPointMake(targetX, targetY);
                    AXValueRef axPos = AXValueCreate(kAXValueTypeCGPoint, &targetPos);
                    AXUIElementSetAttributeValue(window->ref(), kAXPositionAttribute, axPos);
                    CFRelease(axPos);

                    // 2. Restore size if it was hidden
                    if (window->isHidden) {
                        CGSize targetSize = CGSizeMake(window->virtualRect.w, window->virtualRect.h);
                        AXValueRef axSize = AXValueCreate(kAXValueTypeCGSize, &targetSize);
                        AXUIElementSetAttributeValue(window->ref(), kAXSizeAttribute, axSize);
                        CFRelease(axSize);
                        window->isHidden = false;
                    }

                    // 3. Yabai SA for smooth overflow
                    if (window->wid() != 0) {
                        YabaiSA::moveWindow(window->wid(), (int)targetX, (int)targetY);
                    }

                    window->lastRenderedX = targetX;
                    window->lastRenderedY = targetY;
                }
            } else {
                // HIDE IN CORNER logic (inspired by AeroSpace)
                if (!window->isHidden) {
                    window->lastProgrammaticMoveTime = now;
                    
                    // 1. Shrink to 1x1
                    CGSize hideSize = CGSizeMake(1, 1);
                    AXValueRef axSize = AXValueCreate(kAXValueTypeCGSize, &hideSize);
                    AXUIElementSetAttributeValue(window->ref(), kAXSizeAttribute, axSize);
                    CFRelease(axSize);

                    // 2. Move to corner (bottom-right of current screen)
                    CGPoint hidePos = CGPointMake(sx + sw - 1, sy + sh - 1);
                    AXValueRef axPos = AXValueCreate(kAXValueTypeCGPoint, &hidePos);
                    AXUIElementSetAttributeValue(window->ref(), kAXPositionAttribute, axPos);
                    CFRelease(axPos);

                    if (window->wid() != 0) {
                        YabaiSA::moveWindow(window->wid(), -30000, -30000);
                    }
                    
                    window->isHidden = true;
                    window->lastRenderedX = -30000;
                    window->lastRenderedY = -30000;
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
    window->lastProgrammaticMoveTime = CACurrentMediaTime();
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
    if (!window || window->isHidden) return;
    if (m_isPanning) return;
    if (CACurrentMediaTime() - window->lastProgrammaticMoveTime < 0.25) return;

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
