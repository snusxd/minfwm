// Explicit live macOS check; deliberately excluded from CTest and default builds.
#import <AppKit/AppKit.h>

#include "AXBackend.hpp"
#include "CFRAII.hpp"
#include "UniqueFd.hpp"
#include "WindowRenderer.hpp"
#include "YabaiSA.hpp"
#include "WindowManager.hpp"

#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <poll.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <cstring>
#include <dlfcn.h>

@interface FixtureInputTarget : NSObject <NSTextFieldDelegate>
- (void)click:(id)sender;
@end
@implementation FixtureInputTarget
- (void)click:(id)sender { std::cout << "INPUT click PASS" << std::endl; }
- (void)controlTextDidChange:(NSNotification*)notification {
    std::cout << "INPUT text=" << [[[notification object] stringValue] UTF8String] << std::endl;
}
@end

// Diagnostic control only: foreign applications cannot be given this override
// by the window manager. The default fixture remains an ordinary NSWindow.
@interface UnconstrainedFixtureWindow : NSWindow
@end
@implementation UnconstrainedFixtureWindow
- (NSRect)constrainFrameRect:(NSRect)frame toScreen:(NSScreen*)screen {
    return frame;
}
@end

namespace {

volatile sig_atomic_t nativeFrameChangeRequested = 0;
void requestNativeFrameChange(int) { nativeFrameChangeRequested = 1; }

int showFixture(int readyFd, bool unconstrained, bool reportFrame) {
    signal(SIGUSR1, requestNativeFrameChange);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];
    NSWindow* window = [[unconstrained ? [UnconstrainedFixtureWindow class] : [NSWindow class] alloc]
        initWithContentRect:NSMakeRect(120, 200, 640, 400)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"minfwm: manual movement check"];
    NSTextField* label = [NSTextField labelWithString:@"Temporary test window — checking movement above the menu bar"];
    [label setFrame:NSMakeRect(20, 170, 600, 30)];
    [[window contentView] addSubview:label];
    FixtureInputTarget* inputTarget = [[FixtureInputTarget alloc] init];
    NSButton* button = [NSButton buttonWithTitle:@"Click test" target:inputTarget action:@selector(click:)];
    [button setFrame:NSMakeRect(20, 100, 160, 30)];
    [[window contentView] addSubview:button];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 400, 30)];
    [field setPlaceholderString:@"Type minfwm-input-test here"];
    [field setDelegate:inputTarget];
    [[window contentView] addSubview:field];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    const uint32_t wid = static_cast<uint32_t>([window windowNumber]);
    const bool sent = ::write(readyFd, &wid, sizeof(wid)) == sizeof(wid);
    ::close(readyFd);
    if (!sent) return 1;
    // Avoid leaving a fixture behind if the driver is interrupted or crashes.
    [NSTimer scheduledTimerWithTimeInterval:90 repeats:NO block:^(NSTimer*) { [NSApp terminate:nil]; }];
    if (reportFrame) {
        [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer*) {
            if (nativeFrameChangeRequested) {
                nativeFrameChangeRequested = 0;
                const NSRect current = window.frame;
                [window setFrameOrigin:NSMakePoint(current.origin.x + 80, current.origin.y + 40)];
                std::cout << "NATIVE FRAME CHANGE requested by fixture" << std::endl;
            }
            const NSRect frame = [window frame];
            std::cout << "AppKit frame=" << frame.origin.x << ',' << frame.origin.y << std::endl;
        }];
    }
    [NSApp run];
    return 0;
}

struct FixtureProcess {
    pid_t pid;
    ~FixtureProcess() {
        ::kill(pid, SIGTERM);
        while (::waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {}
    }
};

minfwm::CFRef<AXUIElementRef> fixtureAXWindow(pid_t pid) {
    if (!AXIsProcessTrusted()) return {};
    auto app = minfwm::CFRef<AXUIElementRef>::adopt(AXUIElementCreateApplication(pid));
    minfwm::CFRef<CFTypeRef> value;
    if (!app || AXUIElementCopyAttributeValue(app.get(), kAXWindowsAttribute, value.put()) != kAXErrorSuccess ||
        !value || CFGetTypeID(value.get()) != CFArrayGetTypeID()) return {};
    const auto windows = static_cast<CFArrayRef>(value.get());
    if (CFArrayGetCount(windows) != 1) return {};
    const auto window = static_cast<AXUIElementRef>(CFArrayGetValueAtIndex(windows, 0));
    if (!window || CFGetTypeID(window) != AXUIElementGetTypeID()) return {};
    return minfwm::CFRef<AXUIElementRef>::retain(window);
}

bool readBounds(uint32_t wid, CGRect& frame) {
    auto windows = minfwm::CFRef<CFArrayRef>::adopt(
        CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, wid));
    if (!windows || CFArrayGetCount(windows.get()) != 1) {
        std::cerr << "WindowServer query count=" << (windows ? CFArrayGetCount(windows.get()) : -1) << std::endl;
        return false;
    }
    const auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows.get(), 0));
    const auto bounds = static_cast<CFDictionaryRef>(CFDictionaryGetValue(info, kCGWindowBounds));
    if (!bounds || !CGRectMakeWithDictionaryRepresentation(bounds, &frame)) {
        CFShow(info);
        return false;
    }
    return true;
}

// Diagnostic use of Yabai 2.x's existing PIP toggle. Supplying four times the
// width yields a scale of 1, leaving only translation. This is a toggle, not an
// absolute transform setter suitable for continuous camera updates.
bool toggleFixtureTransform(uint32_t wid, CGRect original, float targetY) {
    const char* user = std::getenv("USER");
    if (!user || !*user) return false;
    const std::string path = std::string("/tmp/yabai-sa_") + user + ".socket";
    sockaddr_un address{};
    if (path.size() >= sizeof(address.sun_path)) return false;
    address.sun_family = AF_UNIX;
    std::strncpy(address.sun_path, path.c_str(), sizeof(address.sun_path) - 1);
    minfwm::UniqueFd fd(::socket(AF_UNIX, SOCK_STREAM, 0));
    if (!fd || ::connect(fd.get(), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) return false;
    uint8_t packet[23] = {21, 0, 0x0d};
    std::memcpy(packet + 3, &wid, sizeof(wid));
    const float width = static_cast<float>(original.size.width);
    const float fields[] = {static_cast<float>(original.origin.x) - width * 3, targetY,
        width * 4, static_cast<float>(original.size.height)};
    std::memcpy(packet + 7, fields, sizeof(fields));
    if (::send(fd.get(), packet, sizeof(packet), MSG_NOSIGNAL) != sizeof(packet)) return false;
    pollfd response{fd.get(), POLLIN, 0};
    if (::poll(&response, 1, 500) <= 0) return false;
    uint8_t ack = 0;
    return ::recv(fd.get(), &ack, 1, 0) == 0;
}

int checkTransform(uint32_t wid, CGRect original) {
    minfwm::YabaiSA sa;
    if (!sa.handshake()) return 1; // Check socket ownership, permissions and protocol first.
    const bool sent = toggleFixtureTransform(wid, original, -120);
    std::this_thread::sleep_for(std::chrono::milliseconds(1200));
    CGRect actual{};
    const bool stayed = readBounds(wid, actual) &&
        minfwm::windowPositionMatches(actual.origin, static_cast<int>(original.origin.x), -120);
    std::cout << "transformed WindowServer bounds=" << actual.origin.x << ',' << actual.origin.y << std::endl;
    const bool reset = sent && toggleFixtureTransform(wid, original, -120);
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    const bool returned = readBounds(wid, actual) && CGPointEqualToPoint(original.origin, actual.origin);
    std::cout << "restored WindowServer bounds=" << actual.origin.x << ',' << actual.origin.y << std::endl;
    std::cout << "stable=" << stayed << " restored=" << (reset && returned) << std::endl;
    return sent && stayed && reset && returned ? 0 : 1;
}

int checkAbsolute(uint32_t wid, CGRect original, pid_t fixturePid, const char* executable) {
    minfwm::YabaiSABackend sa;
    if (!sa.initialize() || !sa.usesTransforms()) {
        std::cerr << "Absolute-transform extension unavailable" << std::endl;
        return 77;
    }
    minfwm::AXBackend ax;
    minfwm::WindowRenderer renderer(ax, sa);
    minfwm::ClientWindow window(nullptr, wid);
    minfwm::core::Rect frame{static_cast<float>(original.origin.x), static_cast<float>(original.origin.y),
        static_cast<float>(original.size.width), static_cast<float>(original.size.height)};
    window.originalPhysicalRect = frame;
    window.layerAttempted = true;
    const auto started = std::chrono::steady_clock::now();
    const auto elapsed = [&] {
        return std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    };
    bool good = true;
    for (int tick = 0; tick < 120; ++tick) {
        auto target = frame;
        target.x += tick % 60;
        target.y = -120 - tick % 60;
        good = renderer.render(window, target, elapsed()).succeeded() && good;
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
        CGRect actual{};
        good = readBounds(wid, actual) && minfwm::windowPositionMatches(actual.origin, target.x, target.y) && good;
    }
    std::cout << "PAN 120 frames=" << (good ? "PASS" : "FAIL") << std::endl;
    const CGRect display = CGDisplayBounds(CGMainDisplayID());
    const minfwm::core::Rect displayBounds{static_cast<float>(display.origin.x), static_cast<float>(display.origin.y),
        static_cast<float>(display.size.width), static_cast<float>(display.size.height)};
    auto target = frame; target.y = -120;
    bool culled = true;
    for (int cycle = 0; cycle < 20; ++cycle) {
        auto outside = frame;
        outside.x = cycle % 2 ? displayBounds.right() + 100 : displayBounds.x - frame.w - 100;
        outside.y = displayBounds.y - frame.h - 100;
        culled = renderer.hide(window, outside, displayBounds, elapsed()).succeeded() && culled;
        CGRect actual{};
        culled = readBounds(wid, actual) && minfwm::windowPositionMatches(actual.origin, outside.x, outside.y) &&
            actual.size.width == original.size.width && actual.size.height == original.size.height && culled;
        culled = renderer.render(window, target, elapsed()).succeeded() && culled;
        culled = readBounds(wid, actual) && minfwm::windowPositionMatches(actual.origin, target.x, target.y) && culled;
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }
    good = culled && good;
    std::cout << "OFFSCREEN 20 round trips=" << (culled ? "PASS" : "FAIL") << std::endl;
    std::cout << "INPUT READY: test button and field for 45 seconds" << std::endl;
    for (int tick = 1; tick <= 450; ++tick) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        good = renderer.render(window, target, elapsed()).succeeded() && good;
    }
    // Ask only the disposable fixture to move its own native AppKit frame.
    // This tests cleanup against frame changes without requiring AX permission.
    using NativeBounds = CGError (*)(int, uint32_t, CGRect*);
    using ConnectionId = int (*)();
    void* sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    auto nativeBounds = sky ? reinterpret_cast<NativeBounds>(dlsym(sky, "SLSGetWindowBounds")) : nullptr;
    auto connectionId = sky ? reinterpret_cast<ConnectionId>(dlsym(sky, "SLSMainConnectionID")) : nullptr;
    CGRect changedNative{};
    bool nativeChanged = nativeBounds && connectionId && kill(fixturePid, SIGUSR1) == 0;
    if (nativeChanged) {
        nativeChanged = false;
        for (int tick = 0; tick < 20; ++tick) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            if (nativeBounds(connectionId(), wid, &changedNative) == kCGErrorSuccess &&
                !CGPointEqualToPoint(changedNative.origin, original.origin)) {
                nativeChanged = true;
                break;
            }
        }
    }
    good = sa.resetTransform(wid).succeeded() && good;
    CGRect actual{};
    const bool normalized = nativeChanged && readBounds(wid, actual) && CGPointEqualToPoint(actual.origin, changedNative.origin);
    good = normalized && good;
    std::cout << "RESET AFTER NATIVE FRAME CHANGE=" << (normalized ? "PASS" : "FAIL")
              << " visual=" << actual.origin.x << ',' << actual.origin.y
              << " native=" << changedNative.origin.x << ',' << changedNative.origin.y << std::endl;
    if (sky) dlclose(sky);
    if (!normalized) return 1;
    original = changedNative;
    frame.x = original.origin.x;
    frame.y = original.origin.y;
    // A worker exits without destructors; the Dock-side watchdog must recover.
    const std::string workerWid = std::to_string(wid), workerX = std::to_string(static_cast<int>(frame.x));
    const pid_t worker = fork();
    if (worker == 0) {
        // Do not reuse a forked CoreGraphics connection in the worker.
        execl(executable, executable, "--crash-owner", workerWid.c_str(), workerX.c_str(), nullptr);
        _exit(1);
    }
    int status = 0;
    const bool exited = worker > 0 && waitpid(worker, &status, 0) == worker && WIFEXITED(status) && WEXITSTATUS(status) == 0;
    std::this_thread::sleep_for(std::chrono::milliseconds(800));
    const bool recovered = exited && readBounds(wid, actual) && CGPointEqualToPoint(actual.origin, original.origin);
    std::cout << "crash worker status=" << status << " actual=" << actual.origin.x << ',' << actual.origin.y
              << " expected=" << original.origin.x << ',' << original.origin.y << std::endl;
    std::cout << "CRASH RECOVERY=" << (recovered ? "PASS" : "FAIL") << std::endl;
    return good && recovered ? 0 : 1;
}

bool checkMove(minfwm::WindowRenderer& renderer, minfwm::ClientWindow& window,
               minfwm::core::Rect target, const char* label, double time) {
    bool succeeded = renderer.render(window, target, time).succeeded();
    for (int tick = 1; tick <= 12; ++tick) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        succeeded = renderer.render(window, target, time + tick * 0.05).succeeded() && succeeded;
    }
    CGRect actual{};
    const bool measured = readBounds(window.wid(), actual);
    const bool matched = measured && minfwm::windowPositionMatches(actual.origin,
        static_cast<int>(std::round(target.x)), static_cast<int>(std::round(target.y)));
    std::cout << label << ": requested=" << target.x << ',' << target.y;
    if (measured) std::cout << " actual=" << actual.origin.x << ',' << actual.origin.y;
    std::cout << " result=" << (succeeded && matched ? "PASS" : "FAIL") << std::endl;
    return succeeded && matched;
}

int checkNativeDrop(uint32_t wid, pid_t fixturePid) {
    auto element = fixtureAXWindow(fixturePid);
    if (!element) return 77;
    auto& wm = minfwm::WindowManager::instance();
    if (!wm.initialize()) return 1;
    struct Cleanup { minfwm::WindowManager& wm; ~Cleanup() { wm.shutdown(); } } cleanup{wm};
    auto& display = wm.mainDisplay();
    auto window = display.windowPool().addWindow(element.get());
    wm.adoptWindow(display, window);
    display.camera().setPosition(100, 100);
    wm.updateWindows();
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    bool good = true;
    for (int cycle = 0; cycle < 2; ++cycle) {
        CGRect before{}, dropped{}, actual{};
        if (!readBounds(wid, before)) return 1;
        wm.beginNativeInteraction({static_cast<float>(before.origin.x + 100), static_cast<float>(before.origin.y + 40)});
        window->positionNeedsVerification = true; // Model a recent pan's stale verification guard.
        if (kill(fixturePid, SIGUSR1) != 0) return 1;
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        if (!readBounds(wid, dropped)) return 1;
        wm.endNativeInteraction();
        const auto cameraBefore = display.camera().position();
        const auto expectedVirtual = display.state().physicalToVirtual(minfwm::core::Point{
            static_cast<float>(dropped.origin.x), static_cast<float>(dropped.origin.y)});
        if (cycle == 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
            wm.updateWindows();
        } else {
            wm.flushNativeInteractionForPan();
            display.camera().move({80, 60});
            wm.updateWindows();
        }
        const bool stored = std::abs(window->virtualRect.x - expectedVirtual.x) <= 0.5 &&
            std::abs(window->virtualRect.y - expectedVirtual.y) <= 0.5;
        if (cycle == 0) { display.camera().move({80, 60}); wm.updateWindows(); }
        const bool panned = readBounds(wid, actual) && minfwm::windowPositionMatches(actual.origin,
            std::round(dropped.origin.x - 80), std::round(dropped.origin.y - 60));
        display.camera().setPosition(cameraBefore.x, cameraBefore.y);
        wm.updateWindows();
        const bool returned = readBounds(wid, actual) && CGPointEqualToPoint(actual.origin, dropped.origin);
        good = stored && panned && returned && good;
        std::cout << "NATIVE DROP cycle=" << cycle << " stored=" << stored << " nextPan=" << panned
                  << " returned=" << returned << " dropped=" << dropped.origin.x << ',' << dropped.origin.y << std::endl;
    }
    std::cout << "NATIVE DROP RESULT=" << (good ? "PASS" : "FAIL") << std::endl;
    return good ? 0 : 1;
}

int runCheck(const char* executable, bool unconstrained, bool transform, bool absolute, bool nativeDrop) {
    int readyPipe[2];
    if (::pipe(readyPipe) != 0) return 1;
    minfwm::UniqueFd readEnd(readyPipe[0]), writeEnd(readyPipe[1]);
    const pid_t pid = ::fork();
    if (pid < 0) return 1;
    if (pid == 0) {
        readEnd.reset();
        const std::string fd = std::to_string(writeEnd.get());
        const char* fixtureExecutable = std::getenv("MINFWM_FIXTURE_EXECUTABLE");
        if (!fixtureExecutable || !*fixtureExecutable) fixtureExecutable = executable;
        ::execl(fixtureExecutable, fixtureExecutable, "--fixture", fd.c_str(),
            transform || absolute || nativeDrop ? "transform" : unconstrained ? "unconstrained" : "normal", nullptr);
        _exit(1);
    }
    FixtureProcess fixture{pid};
    writeEnd.reset();
    pollfd ready{readEnd.get(), POLLIN, 0};
    uint32_t wid = 0;
    if (::poll(&ready, 1, 5000) <= 0 || ::read(readEnd.get(), &wid, sizeof(wid)) != sizeof(wid)) {
        std::cerr << "Fixture did not report a window ID" << std::endl;
        return 1;
    }
    std::cout << "Fixture WID=" << wid << " PID=" << pid << std::endl;
    std::cout << "Fixture type=" << (unconstrained ? "unconstrained control" : "normal NSWindow") << std::endl;
    std::this_thread::sleep_for(std::chrono::milliseconds(500));

    CGRect original{};
    if (!readBounds(wid, original)) {
        std::cerr << "WindowServer did not return fixture bounds" << std::endl;
        return 1;
    }
    if (absolute) return checkAbsolute(wid, original, pid, executable);
    if (nativeDrop) return checkNativeDrop(wid, pid);
    if (transform) return checkTransform(wid, original);
    auto element = fixtureAXWindow(pid);
    minfwm::ClientWindow window(element.get(), wid);
    const minfwm::core::Rect frame{static_cast<float>(original.origin.x), static_cast<float>(original.origin.y),
        static_cast<float>(original.size.width), static_cast<float>(original.size.height)};
    window.originalPhysicalRect = frame;
    window.layerAttempted = true; // Check coordinates without changing window levels.
    minfwm::AXBackend ax;
    minfwm::YabaiSABackend sa({}, [](AXUIElementRef ref, uint32_t id, int x, int y) {
        CGRect actual{};
        if (readBounds(id, actual)) {
            std::cout << "immediate SA readback=" << actual.origin.x << ',' << actual.origin.y << std::endl;
        }
        return minfwm::isWindowAtPosition(ref, id, x, y);
    });
    std::cout << "SA handshake=" << (sa.initialize() ? "ready" : "unavailable")
              << " AX=" << (element ? "ready" : "unavailable") << std::endl;
    minfwm::WindowRenderer renderer(ax, sa);
    auto above = frame;
    above.y = -120;
    const bool movedUp = checkMove(renderer, window, above, "above menu bar", 1);
    const bool returned = checkMove(renderer, window, frame, "return", 2);
    // Exercise reappearance after AX size restoration as well.
    window.needsGeometryRestore = static_cast<bool>(element);
    const bool restoredUp = element && checkMove(renderer, window, above, "resize then move above", 3);
    if (!element) std::cout << "resize then move above: SKIP (Accessibility permission required for this tool)" << std::endl;
    const bool restoredBack = checkMove(renderer, window, frame, "final return", 4);
    if (!movedUp || !returned || !restoredBack) return 1;
    if (!element) return 77;
    return restoredUp ? 0 : 1;
}
} // namespace

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc == 4 && std::string(argv[1]) == "--crash-owner") {
            minfwm::YabaiSA sa;
            const auto wid = static_cast<uint32_t>(std::strtoul(argv[2], nullptr, 10));
            const int x = std::atoi(argv[3]);
            const bool applied = sa.handshake() && sa.transformWindow(wid, x, -200) &&
                minfwm::isWindowAtPosition(nullptr, wid, x, -200);
            _exit(applied ? 0 : 1);
        }
        if (argc == 4 && std::string(argv[1]) == "--fixture") {
            return showFixture(std::atoi(argv[2]), std::string(argv[3]) == "unconstrained",
                std::string(argv[3]) == "transform");
        }
        return runCheck(argv[0], argc == 2 && std::string(argv[1]) == "--unconstrained-fixture",
            argc == 2 && std::string(argv[1]) == "--transform-fixture",
            argc == 2 && std::string(argv[1]) == "--absolute-fixture",
            argc == 2 && std::string(argv[1]) == "--native-drop-fixture");
    }
}
