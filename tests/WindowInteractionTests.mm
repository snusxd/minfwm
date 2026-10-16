// Production event callback and coordinator, driven by synthetic events and
// injected native observations. No tap, posted events, AX calls or live SA.
#include "WindowManager.hpp"
#include "InputInterceptor.hpp"
#include "WindowTrace.hpp"
#include <iostream>

namespace minfwm {
struct WindowInteractionTestAccess {
    static int run() {
        int failures = 0;
        auto expect = [&](bool value, const char* why) { if (!value) { std::cerr << "FAIL: " << why << '\n'; ++failures; } };
        auto& manager = WindowManager::instance();
        manager.m_displays.push_back(std::make_unique<Display>(1, core::Rect{0, 0, 1920, 1080}));
        auto& display = *manager.m_displays.front();
        display.camera().setPosition(500, -200);
        auto window = std::make_shared<ClientWindow>(nullptr, 42);
        window->virtualRect = display.state().physicalToVirtual({-100, 100, 640, 480});
        window->virtualCoordinatesInitialized = true;
        auto& pool = display.windowPool();
        pool.m_windows.push_back(window); pool.m_windowsByWID.emplace(42, window);
        manager.m_windowHitTestSnapshot.push_back({42, CGRectMake(-100, 100, 640, 480)});
        auto native = CGRectMake(200, 100, 640, 480);
        core::Rect presented{-100, 100, 640, 480};
        bool readOK = true;
        int reads = 0;
        manager.m_readNativePresentation = [&](uint32_t) -> std::optional<NativeWindowPresentation> {
            ++reads;
            if (!readOK) return {};
            return NativeWindowPresentation{native, CGAffineTransformMakeTranslation(-std::round(presented.x), -std::round(presented.y))};
        };
        InputInterceptor input;
        auto send = [&](CGEventType type, core::Point pointer, CGEventFlags flags = 0) {
            auto event = CFRef<CGEventRef>::adopt(CGEventCreateMouseEvent(nullptr, type, CGPointMake(pointer.x, pointer.y), kCGMouseButtonLeft));
            CGEventSetFlags(event.get(), flags);
            CGEventSetIntegerValueField(event.get(), kCGMouseEventClickState, 2);
            const bool delivered = InputInterceptor::eventTapCallback(nullptr, type, event.get(), &input) == event.get();
            expect(CGEventGetLocation(event.get()).x == pointer.x && CGEventGetLocation(event.get()).y == pointer.y &&
                   CGEventGetIntegerValueField(event.get(), kCGMouseEventClickState) == 2,
                   "native input location and click metadata remain unchanged");
            return delivered;
        };
        const auto original = window->virtualRect;
        for (const auto point : {core::Point{200, 110}, core::Point{200, 140}, core::Point{200, 300}, core::Point{538, 300}}) {
            expect(send(kCGEventLeftMouseDown, point), "native titlebar, tall header, content and edge DOWN all reach application");
            expect(manager.m_nativeInteractions.size() == 1 && manager.m_nativePointerHeld,
                   "one observation transaction owns presentation regardless of chrome");
            expect(send(kCGEventLeftMouseUp, point), "native UP reaches the app without replay");
            expect(!manager.m_nativePointerHeld && manager.m_nativeCommitPending, "release waits for final app geometry observation");
        }
        expect(send(kCGEventLeftMouseDown, {200, 140}), "move DOWN stays native");
        expect(send(kCGEventLeftMouseDragged, {240, 170}, kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate),
               "modifier changes cannot replace native input owner mid-gesture");
        native.origin = CGPointMake(800, 500); presented = {-60, 130, 640, 480};
        expect(manager.updateNativeInteraction(window, 1) && window->virtualRect.x == original.x + 40 && window->virtualRect.y == original.y + 30,
               "native coordinate jump is reconciled as pointer delta, not absolute visual adoption");
        send(kCGEventLeftMouseDragged, {300, 180}); presented = {0, 140, 640, 480};
        manager.updateNativeInteraction(window, 1.1);
        expect(window->virtualRect.x == original.x + 100 && window->virtualRect.y == original.y + 40,
               "latched move follows pointer after native frame stops at physical boundary");
        send(kCGEventLeftMouseUp, {310, 180}); presented = {10, 140, 640, 480};
        manager.updateNativeInteraction(window, 1.2);
        expect(window->virtualRect.x == original.x + 110, "final UP pointer participates in delayed reconciliation");
        const auto accepted = window->virtualRect;
        readOK = false; manager.updateNativeInteraction(window, 1.3);
        expect(window->virtualRect.x == accepted.x, "read failure cannot overwrite the canvas model or release presentation ownership");
        readOK = true;
        send(kCGEventLeftMouseDown, {200, 160});
        send(kCGEventLeftMouseDragged, {220, 180});
        native.origin = CGPointMake(815, 515); presented = {30, 160, 640, 480};
        manager.updateNativeInteraction(window, 1.4);
        expect(window->virtualRect.x == accepted.x + 20 && window->virtualRect.y == accepted.y + 20,
               "rapid new DOWN rebases pending completion without applying absolute geometry twice");
        send(kCGEventLeftMouseUp, {220, 180});
        manager.m_nativeInteractions.clear(); manager.m_nativeCandidates.clear(); 
        manager.m_nativeWindow.reset();
        // Content drag with unchanged native frame is never interpreted as a window move.
        window->virtualRect = original; presented = {-100, 100, 640, 480}; native = CGRectMake(200, 100, 640, 480);
        send(kCGEventLeftMouseDown, {200, 300}); send(kCGEventLeftMouseDragged, {400, 500});
        manager.updateNativeInteraction(window, 2);
        expect(window->virtualRect.x == original.x && window->virtualRect.y == original.y,
               "arbitrary control/scrollbar drag preserves canvas position without AX role exclusions");
        send(kCGEventLeftMouseUp, {400, 500});
        send(kCGEventLeftMouseDown, {538, 105}); send(kCGEventLeftMouseDragged, {600, 80});
        native = CGRectMake(500, 46, 700, 500); presented = {-100, 80, 700, 500};
        manager.updateNativeInteraction(window, 3);
        expect(window->virtualRect.w == 700 && window->virtualRect.h == 500 && window->virtualRect.y == original.y - 20,
               "actual native resize anchors opposite canvas edge without accepting clamp origin");
        InputInterceptor::eventTapCallback(nullptr, kCGEventTapDisabledByTimeout, nullptr, &input);
        expect(!manager.m_nativePointerHeld && manager.m_nativeCommitPending, "tap interruption finishes observation without AX rollback");
        manager.m_nativeInteractions.clear(); manager.m_nativeCandidates.clear();
        manager.beginNativeInteraction({200, 140}, 999);
        expect(manager.m_nativeInteractions.empty(), "OS event target on unmanaged surface cannot select underlying managed window");
        manager.beginNativeInteraction({1900, 1000}, 42);
        expect(manager.m_nativeInteractions.size() == 1, "OS event target selects window independently of cached rectangle and chrome");
        manager.endNativeInteraction();
        // A pending UP owns its own final pointer even after another window's DOWN.
        auto second = std::make_shared<ClientWindow>(nullptr, 43);
        second->virtualRect = original; second->virtualCoordinatesInitialized = true;
        pool.m_windows.push_back(second); pool.m_windowsByWID.emplace(43, second);
        manager.retireNativeInteraction(window);
        window->virtualRect = original; native = CGRectMake(200, 100, 640, 480); presented = {-100, 100, 640, 480};
        manager.beginNativeInteraction({200, 140}, 42);
        manager.noteNativeDrag({230, 150}); manager.endNativeInteraction(core::Point{240, 160});
        manager.beginNativeInteraction({300, 300}, 43);
        manager.noteNativeDrag({900, 800});
        native.origin = CGPointMake(500, 300); presented = {-60, 120, 640, 480};
        manager.updateNativeInteraction(window, 4);
        expect(window->virtualRect.x == original.x + 40 && window->virtualRect.y == original.y + 20,
               "pending first window uses its final UP pointer, independent of second active window");
        expect(manager.m_nativeInteractions.size() == 2, "different windows retain independent transaction baselines");
        manager.retireNativeInteraction(window);
        const auto handedOff = window->virtualRect;
        window->virtualRect.x += 70;
        expect(!manager.updateNativeInteraction(window, 4.1) && window->virtualRect.x == handedOff.x + 70,
               "explicit Drag Everywhere handoff retires pending native writer before new owner updates model");
        expect(manager.m_nativePointerHeld && manager.m_nativeInteractions.size() == 1,
               "retiring old window cannot end another window's active native gesture");
        manager.endNativeInteraction();
        manager.m_nativeInteractions.at(second.get()).completeAt = 0;
        readOK = false;
        manager.commitNativeInteraction();
        expect(manager.m_nativeInteractions.empty() && !manager.m_nativeCommitPending,
               "expired failed final observation releases transaction without fabricating geometry");
        readOK = true;
        manager.beginNativeInteraction({1900, 1000}, 42);
        pool.m_windows.clear(); pool.m_windowsByWID.clear();
        const int before = reads;
        manager.updateNativeInteraction(window, 3.1);
        expect(reads == before, "removed window cannot be queried or reconciled by a stale transaction");
        manager.endNativeInteraction();
        manager.m_nativeInteractions.at(window.get()).completeAt = 0;
        manager.commitNativeInteraction();
        expect(manager.m_nativeInteractions.empty() && !manager.m_nativeCommitPending,
               "destroyed candidate finalization clears stale transaction ownership");
        manager.m_nativePointerHeld = false; manager.m_nativeCommitPending = false;
        manager.m_nativeCandidates.clear();  manager.m_nativeInteractions.clear(); 
        manager.m_windowHitTestSnapshot.clear(); manager.m_displays.clear();
        manager.m_readNativePresentation = readNativeWindowPresentation;
        return failures;
    }
};
}
int main() {
    @autoreleasepool {
        const char* configured = std::getenv("MINFWM_TRACE_WINDOW_INPUT");
        const std::string previous = configured ? configured : "";
        const bool wasSet = configured != nullptr;
        unsetenv("MINFWM_TRACE_WINDOW_INPUT");
        bool writerCalled = false;
        minfwm::traceWindow("test.disabled", 42, [&](auto&) { writerCalled = true; });
        int failures = writerCalled ? 1 : 0;
        failures += minfwm::WindowInteractionTestAccess::run();
        setenv("MINFWM_TRACE_WINDOW_INPUT", "1", 1);
        std::ostringstream captured;
        auto* original = std::cerr.rdbuf(captured.rdbuf());
        failures += minfwm::WindowInteractionTestAccess::run();
        std::cerr.rdbuf(original);
        const auto log = captured.str();
        for (const auto* stage : {"stage=input.received", "stage=native.begin", "stage=native.reconcile", "stage=native.present"}) {
            if (log.find(stage) == std::string::npos) { std::cerr << "missing trace " << stage << '\n'; ++failures; }
        }
        uint64_t previousSequence = 0;
        std::istringstream lines(log); std::string line;
        while (std::getline(lines, line)) {
            if (!line.starts_with("WINDOW_TRACE ")) continue;
            const auto sequence = std::stoull(line.substr(line.find("seq=") + 4));
            if (sequence <= previousSequence || line.find("mono_ms=") == std::string::npos || line.find("gesture=") == std::string::npos) ++failures;
            previousSequence = sequence;
        }
        if (!previousSequence || log.find("replay-post") != std::string::npos || log.find(" transform=") == std::string::npos) ++failures;
        if (wasSet) setenv("MINFWM_TRACE_WINDOW_INPUT", previous.c_str(), 1); else unsetenv("MINFWM_TRACE_WINDOW_INPUT");
        return failures ? 1 : 0;
    }
}
