#import "InputInterceptor.hpp"
#import "WindowManager.hpp"
#import <iostream>
#include <cmath>

namespace minfwm {

InputInterceptor::InputInterceptor() : m_eventTap(NULL), m_runLoopSource(NULL) {}

InputInterceptor::~InputInterceptor() {
    stop();
}

bool InputInterceptor::start() {
    if (m_eventTap) return true;
    std::cout << "InputInterceptor: Starting..." << std::endl;

    // We now listen to Down, Up, and Drag to fully own the gesture
    CGEventMask eventMask = (1 << kCGEventLeftMouseDown) | 
                            (1 << kCGEventLeftMouseUp) | 
                            (1 << kCGEventLeftMouseDragged) | 
                            (1 << kCGEventFlagsChanged) | 
                            (1 << kCGEventKeyDown) |
                            (1 << kCGEventKeyUp) |
                            (1 << kCGEventScrollWheel) |
                            (1 << kCGEventRightMouseDown) | (1 << kCGEventRightMouseUp) |
                            (1 << kCGEventRightMouseDragged) |
                            (1 << kCGEventOtherMouseDown) | (1 << kCGEventOtherMouseUp) |
                            (1 << kCGEventOtherMouseDragged);
                            
    m_eventTap = CFRef<CFMachPortRef>::adopt(CGEventTapCreate(
        kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, eventMask, eventTapCallback, this));

    if (!m_eventTap) {
        std::cerr << "InputInterceptor: Failed to create event tap" << std::endl;
        return false;
    }

    m_runLoopSource = CFRef<CFRunLoopSourceRef>::adopt(
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, m_eventTap.get(), 0));
    if (!m_runLoopSource) {
        std::cerr << "InputInterceptor: Failed to create event tap run-loop source" << std::endl;
        m_eventTap.reset();
        return false;
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), m_runLoopSource.get(), kCFRunLoopCommonModes);
    CGEventTapEnable(m_eventTap.get(), true);
    return true;
}

void InputInterceptor::stop() {
    m_panGesture.reset();
    m_overviewButtons = 0;
    m_overviewKeys.reset();
    m_zoomScrollCaptured = false;
    WindowManager::instance().setPanning(false);
    if (m_eventTap) {
        CGEventTapEnable(m_eventTap.get(), false);
        if (m_runLoopSource) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), m_runLoopSource.get(), kCFRunLoopCommonModes);
            m_runLoopSource.reset();
        }
        m_eventTap.reset();
    }
}

CGEventRef InputInterceptor::eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon) {
    auto* interceptor = static_cast<InputInterceptor*>(refcon);
    if (!interceptor) return event;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        interceptor->m_panGesture.reset();
        WindowManager::instance().setPanning(false);
        WindowManager::instance().endNativeInteraction();
        const CGPoint pointer = event ? CGEventGetLocation(event) : CGPointZero;
        WindowManager::instance().exitOverview({static_cast<float>(pointer.x), static_cast<float>(pointer.y)}, false);
        if (interceptor->m_eventTap) {
            std::cerr << "InputInterceptor: event tap disabled; re-enabling" << std::endl;
            CGEventTapEnable(interceptor->m_eventTap.get(), true);
        }
        return event;
    }
    if (!event) return event;

    auto& wm = WindowManager::instance();
    const CGEventFlags currentFlags = CGEventGetFlags(event);
    const bool zoomModifiers = (currentFlags & kCGEventFlagMaskCommand) && (currentFlags & kCGEventFlagMaskAlternate);
    const CGPoint location = CGEventGetLocation(event);
    const core::Point pointer{static_cast<float>(location.x), static_cast<float>(location.y)};

    if (type == kCGEventScrollWheel) {
        const auto phase = CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
        const auto momentum = CGEventGetIntegerValueField(event, kCGScrollWheelEventMomentumPhase);
        const bool continuous = CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous) != 0;
        const float delta = continuous ? CGEventGetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis1) :
            CGEventGetDoubleValueField(event, kCGScrollWheelEventDeltaAxis1) * 8;
        if (zoomModifiers && wm.requestOverviewZoom(pointer, delta)) {
            interceptor->m_zoomScrollCaptured = phase != 0 || momentum != 0;
            return nullptr;
        }
        // Consume the tail of a trackpad gesture even if modifiers are released
        // before momentum ends; it must not scroll the underlying application.
        if (interceptor->m_zoomScrollCaptured) {
            if (phase == kCGScrollPhaseEnded || phase == kCGScrollPhaseCancelled ||
                momentum == kCGMomentumScrollPhaseEnd || (phase == 0 && momentum == 0)) interceptor->m_zoomScrollCaptured = false;
            return nullptr;
        }
        if (wm.overviewActive()) return nullptr;
    }
    if (type == kCGEventKeyUp || type == kCGEventKeyDown) {
        const auto code = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        if (code >= 0 && code < 256) {
            if (type == kCGEventKeyUp && interceptor->m_overviewKeys.test(code)) {
                interceptor->m_overviewKeys.reset(code);
                return nullptr;
            }
            if (wm.overviewActive()) {
                if (type == kCGEventKeyDown) {
                    interceptor->m_overviewKeys.set(code);
                    if (code == 53) wm.exitOverview(pointer, false);
                }
                return nullptr;
            }
        }
    }
    const bool mouseDown = type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown;
    const bool mouseUp = type == kCGEventLeftMouseUp || type == kCGEventRightMouseUp || type == kCGEventOtherMouseUp;
    const bool mouseDrag = type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged || type == kCGEventOtherMouseDragged;
    if (mouseDown || mouseUp || mouseDrag) {
        const auto button = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
        const uint64_t mask = button >= 0 && button < 64 ? uint64_t{1} << button : 0;
        if (interceptor->m_overviewButtons & mask) {
            if (mouseUp) interceptor->m_overviewButtons &= ~mask;
            return nullptr;
        }
        const bool overviewClick = mouseDown && !(zoomModifiers && type == kCGEventLeftMouseDown);
        const bool secondaryButton = type == kCGEventRightMouseDown || type == kCGEventRightMouseUp ||
            type == kCGEventRightMouseDragged || type == kCGEventOtherMouseDown ||
            type == kCGEventOtherMouseUp || type == kCGEventOtherMouseDragged;
        if (wm.overviewActive() && (overviewClick || secondaryButton)) {
            if (mouseDown) {
                interceptor->m_overviewButtons |= mask;
                if (type == kCGEventLeftMouseDown) wm.exitOverview(pointer, true);
            }
            return nullptr;
        }
    }

    if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp ||
        type == kCGEventLeftMouseDragged || type == kCGEventFlagsChanged) {
        const CGEventFlags flags = CGEventGetFlags(event);
        const bool modifiersHeld = (flags & kCGEventFlagMaskCommand) && (flags & kCGEventFlagMaskAlternate);
        const core::PanEvent panEvent = type == kCGEventLeftMouseDown ? core::PanEvent::mouseDown :
            type == kCGEventLeftMouseUp ? core::PanEvent::mouseUp :
            type == kCGEventLeftMouseDragged ? core::PanEvent::mouseDragged : core::PanEvent::modifiersChanged;
        int64_t displayId = 0;
        if (type == kCGEventLeftMouseDown && modifiersHeld) {
            const CGPoint point = CGEventGetLocation(event);
            displayId = wm.displayForPoint({static_cast<float>(point.x), static_cast<float>(point.y)}).id();
        }
        core::Point delta;
        if (type == kCGEventLeftMouseDragged) {
            delta = {static_cast<float>(CGEventGetIntegerValueField(event, kCGMouseEventDeltaX)),
                     static_cast<float>(CGEventGetIntegerValueField(event, kCGMouseEventDeltaY))};
        }
        const core::PanUpdate update = interceptor->m_panGesture.handle(panEvent, modifiersHeld, displayId, delta);
        if (type == kCGEventLeftMouseDown) {
            if (update.consume) wm.flushNativeInteractionForPan();
            else {
                const CGPoint point = CGEventGetLocation(event);
                wm.beginNativeInteraction({static_cast<float>(point.x), static_cast<float>(point.y)});
            }
        } else if (type == kCGEventLeftMouseUp && !update.consume) {
            wm.endNativeInteraction();
        }
        wm.setPanning(interceptor->m_panGesture.isPanning());
        if (update.displayId && (update.delta.x != 0 || update.delta.y != 0)) {
            if (Display* display = wm.displayById(*update.displayId)) {
                display->camera().move(update.delta.x / display->state().scale(), update.delta.y / display->state().scale());
            }
        }
        if (update.consume || (wm.overviewActive() && type != kCGEventFlagsChanged)) return nullptr;
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
            const CGPoint point = CGEventGetLocation(event);
            Display& display = wm.displayForPoint({static_cast<float>(point.x), static_cast<float>(point.y)});
            if (shift) {
                display.saveBookmark(index);
            } else {
                display.loadBookmark(index);
            }
            return NULL;
        }
    }

    return event;
}

} // namespace minfwm
