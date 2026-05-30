#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#include <iostream>
#include "WindowManager.hpp"

// Global to access eventTap inside the callback when disabled
CFMachPortRef g_eventTap = nullptr;

// Function to check and request macOS Accessibility permissions
bool CheckAccessibilityPermissions()
{
    // Create CFDictionary for AXIsProcessTrustedWithOptions
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    bool isTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    
    return isTrusted;
}

// Global callback for CGEventTap
CGEventRef MouseEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput)
    {
        std::cerr << "Warning: Event tap disabled by system. Re-enabling..." << std::endl;
        if (g_eventTap) {
            CGEventTapEnable(g_eventTap, true);
        }
        return event;
    }

    // Uncomment for extreme debugging
    // if (type != kCGEventMouseMoved && type != kCGEventLeftMouseDragged)
    //    std::cout << "Event type: " << type << std::endl;

    CGEventFlags flags = CGEventGetFlags(event);
    bool hasMod = (flags & kCGEventFlagMaskCommand) && (flags & kCGEventFlagMaskAlternate);

    if (type == kCGEventScrollWheel)
    {
        if (hasMod)
        {
            // Use FixedPtDelta for higher precision (trackpads, magic mouse)
            double delta = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
            CGPoint mousePos = CGEventGetLocation(event);
            
            if (std::abs(delta) > 0.001) {
                WindowManager::GetInstance().Zoom(delta, mousePos.x, mousePos.y);
            }
            
            return nullptr; // Consume scroll event
        }
        else if (WindowManager::GetInstance().IsZooming())
        {
             WindowManager::GetInstance().ForceUpdate();
        }
    }
    else if (type == kCGEventLeftMouseDown)
    {
        if (hasMod)
        {
            WindowManager::GetInstance().Pan(0, 0); // This will set m_isPanning = true
            std::cout << "--- PAN START ---" << std::endl;
            return nullptr; // Consume the event so it doesn't click on windows
        }
    }
    else if (type == kCGEventLeftMouseDragged)
    {
        if (WindowManager::GetInstance().IsPanning())
        {
            double dx = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
            double dy = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);

            WindowManager::GetInstance().Pan(dx, dy);

            return nullptr; // Consume event
        }
    }
    else if (type == kCGEventLeftMouseUp)
    {
        if (WindowManager::GetInstance().IsPanning())
        {
            std::cout << "--- PAN STOP ---" << std::endl;
            // Force one last update on release to ensure positions stick synchronously
            WindowManager::GetInstance().ForceUpdate();
            return nullptr; // Consume event
        }
    }
    
    return event;
}

int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        if (!CheckAccessibilityPermissions())
        {
            std::cerr << "Accessibility permissions not granted. Please grant them in System Settings -> Privacy & Security -> Accessibility, then restart." << std::endl;
            return 1;
        }

        std::cout << "Accessibility permissions granted." << std::endl;

        // Initialize our Window Manager state
        WindowManager::GetInstance().Initialize();

        // Create the event tap using kCGHIDEventTap and kCGEventMaskForAllEvents for maximum visibility
        g_eventTap = CGEventTapCreate(
            kCGHIDEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
            kCGEventMaskForAllEvents,
            MouseEventCallback,
            nullptr
        );

        if (!g_eventTap)
        {
            std::cerr << "Failed to create event tap. Note: Event taps might require running as sudo for the first time or restarting your terminal." << std::endl;
            return 1;
        }

        // Create a run loop source for the event tap
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, g_eventTap, 0);

        // Add the source to the current main CFRunLoop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);

        // Enable the tap
        CGEventTapEnable(g_eventTap, true);

        std::cout << "Starting CFRunLoop. WM is now active!" << std::endl;

        // Start the main run loop. This blocks indefinitely.
        CFRunLoopRun();

        // --- Memory Management ---
        CFRelease(runLoopSource);
        if (g_eventTap) CFRelease(g_eventTap);
    }
    
    return 0;
}
