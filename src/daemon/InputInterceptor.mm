#import "InputInterceptor.hpp"
#import "WindowManager.hpp"
#import "ConfigManager.hpp"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <iostream>
#include <cmath>
#include <algorithm>
#include <dlfcn.h>

namespace {

CGEventFlags flagForModifier(const std::string& modifier) {
    if (modifier == "Cmd") return kCGEventFlagMaskCommand;
    if (modifier == "Alt") return kCGEventFlagMaskAlternate;
    if (modifier == "Shift") return kCGEventFlagMaskShift;
    if (modifier == "Ctrl") return kCGEventFlagMaskControl;
    return 0;
}

bool superHeld(CGEventFlags flags, const std::vector<std::string>& modifiers) {
    return std::all_of(modifiers.begin(), modifiers.end(), [flags](const std::string& modifier) {
        const CGEventFlags requiredFlag = flagForModifier(modifier);
        return requiredFlag != 0 && (flags & requiredFlag) != 0;
    });
}

bool hasUnconfiguredPinModifier(CGEventFlags flags, const std::vector<std::string>& modifiers) {
    return ((flags & kCGEventFlagMaskShift) &&
            std::find(modifiers.begin(), modifiers.end(), "Shift") == modifiers.end()) ||
           ((flags & kCGEventFlagMaskControl) &&
            std::find(modifiers.begin(), modifiers.end(), "Ctrl") == modifiers.end());
}

CGEventFlags flagsForModifiers(const std::vector<std::string>& modifiers,
                               const std::vector<std::string>& superModifiers) {
    CGEventFlags flags = 0;
    for (const std::string& modifier : modifiers) {
        if (modifier == "Super") {
            for (const std::string& superModifier : superModifiers) {
                flags |= flagForModifier(superModifier);
            }
        } else {
            flags |= flagForModifier(modifier);
        }
    }
    return flags;
}

bool matchesModifierChord(CGEventFlags eventFlags, const std::vector<std::string>& modifiers,
                          const std::vector<std::string>& superModifiers) {
    constexpr CGEventFlags kModifierMask = kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate |
        kCGEventFlagMaskShift | kCGEventFlagMaskControl;
    return (eventFlags & kModifierMask) == flagsForModifiers(modifiers, superModifiers);
}

int64_t keyCodeForShortcut(const std::vector<std::string>& shortcut) {
    if (shortcut.size() != 2 || shortcut[0] != "Super" || shortcut[1].size() != 1 ||
        shortcut[1][0] < 'A' || shortcut[1][0] > 'Z') return -1;
    static constexpr int64_t keyCodes[] = {
        0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
        45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,
    };
    return keyCodes[shortcut[1][0] - 'A'];
}

bool setCursorHidingInBackground(bool enabled) {
    using ConnectionId = int32_t;
    using MainConnectionIdFunction = ConnectionId (*)();
    using SetConnectionPropertyFunction = int32_t (*)(ConnectionId, ConnectionId, CFStringRef, CFTypeRef);

    auto mainConnection = reinterpret_cast<MainConnectionIdFunction>(dlsym(RTLD_DEFAULT, "CGSMainConnectionID"));
    auto setProperty = reinterpret_cast<SetConnectionPropertyFunction>(
        dlsym(RTLD_DEFAULT, "CGSSetConnectionProperty"));
    if (!mainConnection || !setProperty) return false;

    const ConnectionId connection = mainConnection();
    return setProperty(connection, connection, CFSTR("SetsCursorInBackground"),
                       enabled ? kCFBooleanTrue : kCFBooleanFalse) == 0;
}

} // namespace

namespace minfwm {

InputInterceptor::InputInterceptor() : m_eventTap(NULL), m_runLoopSource(NULL) {}

InputInterceptor::~InputInterceptor() {
    stop();
}

bool InputInterceptor::start() {
    if (m_eventTap) return true;
    std::cout << "InputInterceptor: Starting..." << std::endl;
    NSApplication* application = [NSApplication sharedApplication];
    [application setActivationPolicy:NSApplicationActivationPolicyAccessory];

    // We now listen to Down, Up, and Drag to fully own the gesture
    CGEventMask eventMask = (1 << kCGEventMouseMoved) |
                            (1 << kCGEventLeftMouseDown) |
                            (1 << kCGEventLeftMouseUp) |
                            (1 << kCGEventLeftMouseDragged) |
                            (1 << kCGEventFlagsChanged) |
                            (1 << kCGEventKeyDown) |
                            (1 << kCGEventKeyUp) |
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
    // Mouse utilities can consume wheel events at HID and replace them with
    // gestures before the session tap. Capture only scrolling ahead of them;
    // ordinary scrolling still passes unchanged to the user's mouse utility.
    m_scrollEventTap = CFRef<CFMachPortRef>::adopt(CGEventTapCreate(kCGHIDEventTap,
        kCGHeadInsertEventTap, kCGEventTapOptionDefault, CGEventMaskBit(kCGEventScrollWheel), scrollTapCallback, this));
    if (!m_scrollEventTap) {
        m_scrollEventTap = CFRef<CFMachPortRef>::adopt(CGEventTapCreate(kCGAnnotatedSessionEventTap,
            kCGHeadInsertEventTap, kCGEventTapOptionDefault, CGEventMaskBit(kCGEventScrollWheel), scrollTapCallback, this));
    }
    if (m_scrollEventTap) {
        m_scrollRunLoopSource = CFRef<CFRunLoopSourceRef>::adopt(CFMachPortCreateRunLoopSource(kCFAllocatorDefault, m_scrollEventTap.get(), 0));
        if (m_scrollRunLoopSource) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), m_scrollRunLoopSource.get(), kCFRunLoopCommonModes);
            CGEventTapEnable(m_scrollEventTap.get(), true);
        } else {
            m_scrollEventTap.reset();
        }
    }
    if (!m_scrollEventTap) std::cerr << "InputInterceptor: scroll interception unavailable" << std::endl;

    m_trackpadCallbackEnabled = std::make_shared<std::atomic_bool>(true);
    const auto callbackEnabled = m_trackpadCallbackEnabled;
    m_trackpadInput.start([this, callbackEnabled](bool active, core::Point delta, float zoomDelta) {
        m_trackpadTouchActive.store(active, std::memory_order_release);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!callbackEnabled->load(std::memory_order_acquire)) return;
            handleTrackpadPan(active, delta, zoomDelta);
        });
    });
    return true;
}

void InputInterceptor::stop() {
    if (m_trackpadCallbackEnabled) {
        m_trackpadCallbackEnabled->store(false, std::memory_order_release);
        m_trackpadCallbackEnabled.reset();
    }
    m_trackpadInput.stop();
    m_trackpadTouchActive.store(false, std::memory_order_release);
    m_trackpadScrollCaptured = false;
    m_trackpadPanDisplayId.reset();
    m_trackpadGestureActive = false;
    m_trackpadZoomGestureActive = false;
    m_trackpadPanVelocity = {};
    if (m_trackpadMomentumTimer) {
        [m_trackpadMomentumTimer invalidate];
        [m_trackpadMomentumTimer release];
        m_trackpadMomentumTimer = nil;
    }
    m_panGesture.reset();
    updateCursor(false, false, CGPointZero);
    if (m_cursorOverlay) {
        [m_cursorOverlay close];
        [m_cursorOverlay release];
        m_cursorOverlay = nil;
        m_cursorImageView = nil;
    }
    m_overviewButtons = 0;
    m_overviewKeys.reset();
    m_zoomScrollCaptured = false;
    WindowManager::instance().setPanning(false);
    if (m_scrollEventTap) {
        CGEventTapEnable(m_scrollEventTap.get(), false);
        if (m_scrollRunLoopSource) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), m_scrollRunLoopSource.get(), kCFRunLoopCommonModes);
            m_scrollRunLoopSource.reset();
        }
        m_scrollEventTap.reset();
    }
    if (m_eventTap) {
        CGEventTapEnable(m_eventTap.get(), false);
        if (m_runLoopSource) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), m_runLoopSource.get(), kCFRunLoopCommonModes);
            m_runLoopSource.reset();
        }
        m_eventTap.reset();
    }
}

void InputInterceptor::handleTrackpadPan(bool active, core::Point delta, float zoomDelta) {
    auto& wm = WindowManager::instance();
    if (!active) {
        if (m_trackpadZoomGestureActive) {
            m_trackpadZoomGestureActive = false;
            return;
        }
        if (!m_trackpadGestureActive) return;
        m_trackpadGestureActive = false;
        const double now = CACurrentMediaTime();
        const double idle = std::max(0.0, now - m_trackpadLastMovementTime);
        constexpr double kDeceleration = 5.0;
        const float idleDecay = static_cast<float>(std::exp(-kDeceleration * idle));
        m_trackpadPanVelocity.x *= idleDecay;
        m_trackpadPanVelocity.y *= idleDecay;
        if (std::hypot(m_trackpadPanVelocity.x, m_trackpadPanVelocity.y) < 12.0f) {
            finishTrackpadPan();
            return;
        }
        m_trackpadMomentumLastTick = now;
        m_trackpadMomentumTimer = [[NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer*) {
            advanceTrackpadMomentum();
        }] retain];
        [[NSRunLoop mainRunLoop] addTimer:m_trackpadMomentumTimer forMode:NSRunLoopCommonModes];
        return;
    }

    if (zoomDelta != 0.0f) {
        if (!m_trackpadZoomGestureActive) finishTrackpadPan();
        m_trackpadZoomGestureActive = true;
        CGEventRef pointerEvent = CGEventCreate(nullptr);
        const CGPoint location = pointerEvent ? CGEventGetLocation(pointerEvent) : CGPointZero;
        if (pointerEvent) CFRelease(pointerEvent);
        const bool invert = ConfigManager::instance().snapshot().trackInvertZoomDirection;
        (void)wm.requestOverviewZoom({static_cast<float>(location.x), static_cast<float>(location.y)},
                                     invert ? -zoomDelta : zoomDelta);
        return;
    }
    if (m_trackpadZoomGestureActive) return;
    if (delta.x == 0.0f && delta.y == 0.0f) return;

    if (!m_trackpadGestureActive) {
        if (m_trackpadMomentumTimer) {
            [m_trackpadMomentumTimer invalidate];
            [m_trackpadMomentumTimer release];
            m_trackpadMomentumTimer = nil;
        }
        m_trackpadPanDisplayId.reset();
        m_trackpadPanVelocity = {};
        m_trackpadGestureActive = true;
        m_trackpadLastEventTime = CACurrentMediaTime();
        m_trackpadLastMovementTime = m_trackpadLastEventTime;
    }

    if (!m_trackpadPanDisplayId) {
        CGEventRef pointerEvent = CGEventCreate(nullptr);
        const CGPoint pointer = pointerEvent ? CGEventGetLocation(pointerEvent) : CGPointZero;
        if (pointerEvent) CFRelease(pointerEvent);
        if (wm.isIgnoredDisplayAtPoint({static_cast<float>(pointer.x), static_cast<float>(pointer.y)})) return;
        m_trackpadPanDisplayId = wm.displayForPoint(
            {static_cast<float>(pointer.x), static_cast<float>(pointer.y)}).id();
        wm.setPanning(true);
    }

    const double now = CACurrentMediaTime();
    const double elapsed = now - m_trackpadLastEventTime;
    m_trackpadLastEventTime = now;
    if (delta.x == 0.0f && delta.y == 0.0f) return;
    if (elapsed > 0.001 && elapsed < 0.1) {
        const float instantX = static_cast<float>(delta.x / elapsed);
        const float instantY = static_cast<float>(delta.y / elapsed);
        m_trackpadPanVelocity.x = instantX * 0.35f + m_trackpadPanVelocity.x * 0.65f;
        m_trackpadPanVelocity.y = instantY * 0.35f + m_trackpadPanVelocity.y * 0.65f;
    }
    m_trackpadLastMovementTime = now;
    applyTrackpadPanDelta(delta);
}

void InputInterceptor::applyTrackpadPanDelta(core::Point delta) {
    if (!m_trackpadPanDisplayId || (delta.x == 0.0f && delta.y == 0.0f)) return;
    auto& wm = WindowManager::instance();
    if (wm.overviewReturning()) return;
    if (Display* display = wm.displayById(*m_trackpadPanDisplayId)) {
        display->state().cancelCameraAnimation();
        const ConfigSnapshot config = ConfigManager::instance().snapshot();
        const float deltaX = config.trackpadInvertX ? -delta.x : delta.x;
        const float deltaY = config.trackpadInvertY ? -delta.y : delta.y;
        display->camera().move(deltaX * config.trackpadMovementMultiplier / display->state().scale(),
                               deltaY * config.trackpadMovementMultiplier / display->state().scale());
    }
}

void InputInterceptor::advanceTrackpadMomentum() {
    const double now = CACurrentMediaTime();
    const double elapsed = std::clamp(now - m_trackpadMomentumLastTick, 0.0, 0.05);
    m_trackpadMomentumLastTick = now;
    if (elapsed <= 0.0) return;

    applyTrackpadPanDelta({static_cast<float>(m_trackpadPanVelocity.x * elapsed),
                           static_cast<float>(m_trackpadPanVelocity.y * elapsed)});
    constexpr double kDeceleration = 5.0;
    const float decay = static_cast<float>(std::exp(-kDeceleration * elapsed));
    m_trackpadPanVelocity.x *= decay;
    m_trackpadPanVelocity.y *= decay;
    if (std::hypot(m_trackpadPanVelocity.x, m_trackpadPanVelocity.y) < 12.0f) finishTrackpadPan();
}

void InputInterceptor::finishTrackpadPan() {
    if (m_trackpadMomentumTimer) {
        [m_trackpadMomentumTimer invalidate];
        [m_trackpadMomentumTimer release];
        m_trackpadMomentumTimer = nil;
    }
    m_trackpadGestureActive = false;
    m_trackpadPanDisplayId.reset();
    m_trackpadPanVelocity = {};
    WindowManager::instance().setPanning(false);
}

void InputInterceptor::updateCursor(bool superHeld, bool dragging, CGPoint pointer) {
    const bool ignoredDisplay = superHeld && WindowManager::instance().isIgnoredDisplayAtPoint(
        {static_cast<float>(pointer.x), static_cast<float>(pointer.y)});
    if (!superHeld || ignoredDisplay) {
        if (m_cursorOverlay) [m_cursorOverlay orderOut:nil];
        if (m_systemCursorHidden) {
            CGDisplayShowCursor(kCGDirectMainDisplay);
            m_systemCursorHidden = false;
        }
        if (m_backgroundCursorHidingEnabled) {
            (void)setCursorHidingInBackground(false);
            m_backgroundCursorHidingEnabled = false;
        }
        if (!superHeld) m_cursorUnavailableForHold = false;
        m_closedHandCursorActive = false;
        return;
    }
    if (m_cursorUnavailableForHold) return;

    if (!m_cursorOverlay) {
        m_cursorOverlay = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 32, 32)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        [m_cursorOverlay setOpaque:NO];
        [m_cursorOverlay setBackgroundColor:[NSColor clearColor]];
        [m_cursorOverlay setHasShadow:NO];
        [m_cursorOverlay setIgnoresMouseEvents:YES];
        [m_cursorOverlay setHidesOnDeactivate:NO];
        [m_cursorOverlay setReleasedWhenClosed:NO];
        [m_cursorOverlay setLevel:CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey)];
        [m_cursorOverlay setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary];

        m_cursorImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
        [m_cursorImageView setImageScaling:NSImageScaleNone];
        [m_cursorOverlay setContentView:m_cursorImageView];
        [m_cursorImageView release];

    }

    if (!m_systemCursorHidden) {
        if (!setCursorHidingInBackground(true)) {
            std::cerr << "InputInterceptor: background cursor hiding unavailable; hand cursor overlay disabled" << std::endl;
            m_cursorUnavailableForHold = true;
            return;
        }
        m_backgroundCursorHidingEnabled = true;
        const CGError hideResult = CGDisplayHideCursor(kCGDirectMainDisplay);
        if (hideResult != kCGErrorSuccess) {
            std::cerr << "InputInterceptor: failed to hide system cursor (error " << hideResult << ")" << std::endl;
            (void)setCursorHidingInBackground(false);
            m_backgroundCursorHidingEnabled = false;
            m_cursorUnavailableForHold = true;
            return;
        }
        m_systemCursorHidden = true;
    }

    if (dragging != m_closedHandCursorActive || ![m_cursorImageView image]) {
        NSCursor* cursor = dragging ? [NSCursor closedHandCursor] : [NSCursor openHandCursor];
        NSImage* image = [cursor image];
        [m_cursorImageView setImage:image];
        const NSSize imageSize = [image size];
        if (imageSize.width > 0 && imageSize.height > 0) {
            [m_cursorOverlay setContentSize:imageSize];
            [m_cursorImageView setFrame:NSMakeRect(0, 0, imageSize.width, imageSize.height)];
        }
        m_closedHandCursorActive = dragging;
    }

    NSScreen* mainScreen = nil;
    const CGDirectDisplayID mainDisplay = CGMainDisplayID();
    for (NSScreen* screen in [NSScreen screens]) {
        NSNumber* displayNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
        if (displayNumber && [displayNumber unsignedIntValue] == mainDisplay) {
            mainScreen = screen;
            break;
        }
    }
    if (!mainScreen) mainScreen = [NSScreen mainScreen];

    const CGRect quartzMainBounds = CGDisplayBounds(mainDisplay);
    const NSRect cocoaMainFrame = [mainScreen frame];
    const NSPoint cocoaPointer = NSMakePoint(
        cocoaMainFrame.origin.x + pointer.x - quartzMainBounds.origin.x,
        NSMaxY(cocoaMainFrame) - (pointer.y - quartzMainBounds.origin.y));
    NSCursor* cursor = m_closedHandCursorActive ? [NSCursor closedHandCursor] : [NSCursor openHandCursor];
    const NSPoint hotSpot = [cursor hotSpot];
    const NSSize imageSize = [[cursor image] size];
    [m_cursorOverlay setFrameOrigin:NSMakePoint(
        cocoaPointer.x - hotSpot.x,
        cocoaPointer.y - imageSize.height + hotSpot.y)];
    [m_cursorOverlay orderFrontRegardless];
}

CGEventRef InputInterceptor::scrollTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon) {
    auto* interceptor = static_cast<InputInterceptor*>(refcon);
    if (!interceptor) return event;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        interceptor->m_zoomScrollCaptured = false;
        interceptor->m_trackpadScrollCaptured = false;
        WindowManager::instance().exitOverview({}, false);
        if (interceptor->m_scrollEventTap) CGEventTapEnable(interceptor->m_scrollEventTap.get(), true);
        return event;
    }
    return eventTapCallback(proxy, type, event, refcon);
}

CGEventRef InputInterceptor::eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon) {
    auto* interceptor = static_cast<InputInterceptor*>(refcon);
    if (!interceptor) return event;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        interceptor->m_panGesture.reset();
        interceptor->updateCursor(false, false, CGPointZero);
        WindowManager::instance().setPanning(false);
        WindowManager::instance().endNativeInteraction();
        WindowManager::instance().cancelDragEverywhere();
        interceptor->m_dragEverywhereActive = false;
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
    const auto dragEverywhereModifiers = ConfigManager::instance().snapshot().dragEverywhereModifiers;
    const bool rewindOnFocus = ConfigManager::instance().snapshot().rewindOnFocus;
    const bool usesSuperKey = type == kCGEventScrollWheel || type == kCGEventLeftMouseDown ||
        type == kCGEventLeftMouseUp || type == kCGEventLeftMouseDragged || type == kCGEventMouseMoved || type == kCGEventFlagsChanged ||
        type == kCGEventKeyDown;
    const std::vector<std::string> superModifiers = usesSuperKey ?
        ConfigManager::instance().snapshot().superModifiers : std::vector<std::string>{};
    const CGEventFlags currentFlags = CGEventGetFlags(event);
    const bool zoomModifiers = usesSuperKey && superHeld(currentFlags, superModifiers);
    const CGPoint location = CGEventGetLocation(event);
    const core::Point pointer{static_cast<float>(location.x), static_cast<float>(location.y)};

    if (type == kCGEventScrollWheel) {
        const auto phase = CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
        const auto momentum = CGEventGetIntegerValueField(event, kCGScrollWheelEventMomentumPhase);
        if (interceptor->m_trackpadTouchActive.load(std::memory_order_acquire)) {
            interceptor->m_trackpadScrollCaptured = true;
            return nullptr;
        }
        if (interceptor->m_trackpadScrollCaptured) {
            if (momentum != 0) {
                if (momentum == kCGMomentumScrollPhaseEnd) interceptor->m_trackpadScrollCaptured = false;
                return nullptr;
            }
            if (phase == kCGScrollPhaseBegan || phase == 0) {
                interceptor->m_trackpadScrollCaptured = false;
            } else {
                return nullptr;
            }
        }
        const bool continuous = CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous) != 0;
        const float delta = continuous ? CGEventGetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis1) :
            CGEventGetDoubleValueField(event, kCGScrollWheelEventDeltaAxis1) * 8;
        const bool requested = zoomModifiers && wm.requestOverviewZoom(pointer, delta);
        if (std::getenv("MINFWM_TRACE_WINDOW_INPUT")) {
            std::cout << "SCROLL delta=" << delta << " continuous=" << continuous << " modifiers=" << zoomModifiers
                      << " requested=" << requested << " phase=" << phase << " momentum=" << momentum << std::endl;
        }
        if (requested) {
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
        if (wm.overviewActive() && rewindOnFocus) return nullptr;
    }
    if (type == kCGEventKeyUp || type == kCGEventKeyDown) {
        const auto code = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        if (code >= 0 && code < 256) {
            if (interceptor->m_overviewKeys.test(code)) {
                if (type == kCGEventKeyUp) interceptor->m_overviewKeys.reset(code);
                return nullptr;
            }
            if (wm.overviewActive() && rewindOnFocus) {
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

    if (type == kCGEventLeftMouseDown && matchesModifierChord(currentFlags, dragEverywhereModifiers,
                                                               superModifiers) &&
        wm.beginDragEverywhere(pointer)) {
        interceptor->m_dragEverywhereActive = true;
        interceptor->updateCursor(zoomModifiers, true, location);
        return nullptr;
    }
    if (interceptor->m_dragEverywhereActive) {
        if (type == kCGEventLeftMouseDragged) {
            if (matchesModifierChord(currentFlags, dragEverywhereModifiers, superModifiers)) {
                wm.dragWindowTo(pointer);
            }
            interceptor->updateCursor(zoomModifiers, zoomModifiers &&
                matchesModifierChord(currentFlags, dragEverywhereModifiers, superModifiers), location);
            return nullptr;
        }
        if (type == kCGEventLeftMouseUp) {
            wm.endDragEverywhere(pointer);
            interceptor->m_dragEverywhereActive = false;
            interceptor->updateCursor(zoomModifiers, false, location);
            return nullptr;
        }
    }

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
        if (wm.overviewActive() && rewindOnFocus && (overviewClick || secondaryButton)) {
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
        const bool modifiersHeld = superHeld(flags, superModifiers);
        const core::PanEvent panEvent = type == kCGEventLeftMouseDown ? core::PanEvent::mouseDown :
            type == kCGEventLeftMouseUp ? core::PanEvent::mouseUp :
            type == kCGEventLeftMouseDragged ? core::PanEvent::mouseDragged : core::PanEvent::modifiersChanged;
        int64_t displayId = 0;
        if (type == kCGEventLeftMouseDown && modifiersHeld) {
            const CGPoint point = CGEventGetLocation(event);
            if (!wm.isIgnoredDisplayAtPoint({static_cast<float>(point.x), static_cast<float>(point.y)})) {
                displayId = wm.displayForPoint({static_cast<float>(point.x), static_cast<float>(point.y)}).id();
            }
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
        } else if (type == kCGEventLeftMouseDragged) {
            if (update.consume) wm.flushNativeInteractionForPan();
            else wm.noteNativeDrag();
        } else if (type == kCGEventLeftMouseUp && !update.consume) {
            wm.endNativeInteraction();
        }
        wm.setPanning(interceptor->m_panGesture.isPanning());
        const bool draggingCursor = type == kCGEventLeftMouseDragged ? interceptor->m_panGesture.isPanning() :
            (type != kCGEventLeftMouseDown && type != kCGEventLeftMouseUp &&
             interceptor->m_closedHandCursorActive && interceptor->m_panGesture.isPanning());
        interceptor->updateCursor(modifiersHeld, draggingCursor, location);
        if (!wm.overviewReturning() && update.displayId && (update.delta.x != 0 || update.delta.y != 0)) {
            if (Display* display = wm.displayById(*update.displayId)) {
                display->state().cancelCameraAnimation();
                const float multiplier = ConfigManager::instance().snapshot().mouseMovementMultiplier;
                display->camera().move(update.delta.x * multiplier / display->state().scale(),
                                       update.delta.y * multiplier / display->state().scale());
            }
        }
        if (update.consume || (wm.overviewActive() && rewindOnFocus && type != kCGEventFlagsChanged)) return nullptr;
    }

    if (type == kCGEventMouseMoved) {
        interceptor->updateCursor(zoomModifiers,
            interceptor->m_closedHandCursorActive && interceptor->m_panGesture.isPanning(), location);
    }

    if (type == kCGEventKeyDown) {
        CGEventFlags flags = CGEventGetFlags(event);
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        const ConfigSnapshot config = ConfigManager::instance().snapshot();
        const bool exactSuperChord = superHeld(flags, superModifiers) &&
            !hasUnconfiguredPinModifier(flags, superModifiers);
        const bool repeating = CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0;

        if (exactSuperChord && !repeating && keycode == keyCodeForShortcut(config.centerCameraToFocus)) {
            wm.centerCameraToFocusedWindow();
            return nullptr;
        }
        if (exactSuperChord && !repeating && keycode == keyCodeForShortcut(config.centerFocusToCamera)) {
            wm.centerFocusedWindowToCamera();
            return nullptr;
        }

        if (keycode == 35 && superHeld(flags, superModifiers) &&
            !hasUnconfiguredPinModifier(flags, superModifiers)) {
            if (!repeating) (void)wm.toggleFocusedWindowPin();
            return nullptr;
        }

        int index = -1;
        if (keycode >= 18 && keycode <= 21) index = keycode - 17; // 1-4
        else if (keycode == 23) index = 5;
        else if (keycode == 22) index = 6;
        else if (keycode == 26) index = 7;
        else if (keycode == 28) index = 8;
        else if (keycode == 25) index = 9;

        if (index != -1 && matchesModifierChord(flags, config.bookmarksAddModifiers, superModifiers)) {
            const CGPoint point = CGEventGetLocation(event);
            if (wm.isIgnoredDisplayAtPoint({static_cast<float>(point.x), static_cast<float>(point.y)})) return event;
            Display& display = wm.displayForPoint({static_cast<float>(point.x), static_cast<float>(point.y)});
            display.saveBookmark(index);
            return nullptr;
        }
        if (index != -1 && matchesModifierChord(flags, config.bookmarksGotoModifiers, superModifiers)) {
            const CGPoint point = CGEventGetLocation(event);
            if (wm.isIgnoredDisplayAtPoint({static_cast<float>(point.x), static_cast<float>(point.y)})) return event;
            Display& display = wm.displayForPoint({static_cast<float>(point.x), static_cast<float>(point.y)});
            display.loadBookmark(index);
            return NULL;
        }
    }

    return event;
}

} // namespace minfwm
