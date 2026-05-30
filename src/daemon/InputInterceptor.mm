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

    CGEventMask eventMask = (1 << kCGEventMouseMoved) | (1 << kCGEventLeftMouseDragged) | (1 << kCGEventFlagsChanged) | (1 << kCGEventKeyDown);
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
    auto* self = static_cast<InputInterceptor*>(refcon);
    auto& wm = WindowManager::instance();

    if (type == kCGEventKeyDown) {
        CGEventFlags flags = CGEventGetFlags(event);
        bool cmd = flags & kCGEventFlagMaskCommand;
        bool shift = flags & kCGEventFlagMaskShift;
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

        // Map keycodes for 1-9
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
                std::cout << "InputInterceptor: Saved bookmark " << index << std::endl;
            } else {
                wm.mainDisplay().loadBookmark(index);
                wm.updateWindows();
                std::cout << "InputInterceptor: Loaded bookmark " << index << std::endl;
            }
            return NULL; // Consume event
        }
    }

    if (type == kCGEventLeftMouseDragged || type == kCGEventMouseMoved) {
        CGEventFlags flags = CGEventGetFlags(event);
        bool cmd = flags & kCGEventFlagMaskCommand;
        bool opt = flags & kCGEventFlagMaskAlternate;

        if (cmd && opt) {
            // Panning logic
            int64_t dx = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
            int64_t dy = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);

            if (dx != 0 || dy != 0) {
                std::cout << "InputInterceptor: Panning delta " << dx << ", " << dy << std::endl;
                wm.mainDisplay().camera().move(-dx, -dy);
                wm.updateWindows();
            }
            
            // Consume event if it's a drag to prevent window moving/focusing
            if (type == kCGEventLeftMouseDragged) {
                return NULL;
            }
        }
    }

    return event;
}

} // namespace minfwm
