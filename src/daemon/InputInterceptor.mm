#import "InputInterceptor.hpp"
#import "WindowManager.hpp"
#import <iostream>

namespace minfwm {

InputInterceptor::InputInterceptor() : m_eventTap(NULL), m_runLoopSource(NULL) {}

InputInterceptor::~InputInterceptor() {
    stop();
}

void InputInterceptor::start() {
    std::cout << "InputInterceptor: Starting..." << std::endl;

    // We now listen to Down, Up, and Drag to fully own the gesture
    CGEventMask eventMask = (1 << kCGEventLeftMouseDown) | 
                            (1 << kCGEventLeftMouseUp) | 
                            (1 << kCGEventLeftMouseDragged) | 
                            (1 << kCGEventFlagsChanged) | 
                            (1 << kCGEventKeyDown);
                            
    m_eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, eventMask, eventTapCallback, this);

    if (!m_eventTap) {
        std::cerr << "InputInterceptor: Failed to create event tap" << std::endl;
        return;
    }

    m_runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, m_eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), m_runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(m_eventTap, true);
}

void InputInterceptor::stop() {
    if (m_eventTap) {
        CGEventTapEnable(m_eventTap, false);
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), m_runLoopSource, kCFRunLoopCommonModes);
        CFRelease(m_runLoopSource);
        CFRelease(m_eventTap);
        m_eventTap = NULL;
        m_runLoopSource = NULL;
    }
}

CGEventRef InputInterceptor::eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon) {
    auto& wm = WindowManager::instance();

    // Check modifiers for any mouse event in our mask
    if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp || type == kCGEventLeftMouseDragged) {
        CGEventFlags flags = CGEventGetFlags(event);
        bool cmd = flags & kCGEventFlagMaskCommand;
        bool opt = flags & kCGEventFlagMaskAlternate;

        if (cmd && opt) {
            if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseDragged) {
                wm.setPanning(true);
            }
            if (type == kCGEventLeftMouseUp) {
                wm.setPanning(false);
            }

            if (type == kCGEventLeftMouseDragged) {
                int64_t dx = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
                int64_t dy = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);

                if (dx != 0 || dy != 0) {
                    wm.mainDisplay().camera().move(-dx, -dy);
                }
            }
            
            // CONSUME ALL PART OF THE GESTURE (Down, Drag, Up) 
            // if Cmd+Opt are held. This prevents macOS from seeing the click 
            // on the wallpaper or windows.
            return NULL; 
        }
    }

    if (type == kCGEventKeyDown) {
        CGEventFlags flags = CGEventGetFlags(event);
        bool cmd = flags & kCGEventFlagMaskCommand;
        bool shift = flags & kCGEventFlagMaskShift;
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

        int index = -1;
        if (keycode >= 18 && keycode <= 21) index = keycode - 17; // 1-4
        else if (keycode == 23) index = 5;
        else if (keycode == 22) index = 6;
        else if (keycode == 26) index = 7;
        else if (keycode == 28) index = 8;
        else if (keycode == 25) index = 9;

        if (index != -1 && cmd) {
            if (shift) {
                wm.mainDisplay().saveBookmark(index);
            } else {
                wm.mainDisplay().loadBookmark(index);
            }
            return NULL;
        }
    }

    if (type == kCGEventFlagsChanged) {
        CGEventFlags flags = CGEventGetFlags(event);
        bool cmd = flags & kCGEventFlagMaskCommand;
        bool opt = flags & kCGEventFlagMaskAlternate;
        if (!cmd || !opt) {
            wm.setPanning(false);
        }
    }

    return event;
}

} // namespace minfwm
