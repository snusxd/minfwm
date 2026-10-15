#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <iostream>
#include <signal.h>
#include "WindowManager.hpp"
#include "AXObserver.hpp"
#include "InputInterceptor.hpp"
#include "IPCServer.hpp"
#include "DaemonRunLoop.hpp"
#include "DisplayFrameClock.hpp"
#include "CFRAII.hpp"
#include "AccessibilityPermission.hpp"

namespace {
volatile sig_atomic_t g_stopRequested = 0;

void requestStop(int) {
    g_stopRequested = 1;
}
}

int runDaemon() {
    @autoreleasepool {
        std::cout << "minfwm: Starting macOS Infinite Window Manager daemon..." << std::endl;
        
        // Prevent crash on socket errors
        signal(SIGPIPE, SIG_IGN);
        signal(SIGINT, requestStop);
        signal(SIGTERM, requestStop);

        // Prompt once, then keep rechecking because TCC permission changes are
        // not delivered to an already-running process. This mirrors the app
        // activation refresh used in Keyboard GUI without requiring a daemon
        // restart after the user enables Accessibility in System Settings.
        NSDictionary *options = @{(id)kAXTrustedCheckOptionPrompt: @YES};
        if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
            std::cerr << "minfwm daemon: waiting for Accessibility permission; enable it in System Settings"
                      << std::endl;
            const bool granted = minfwm::waitUntilAccessibilityPermissionGranted(
                [] { return AXIsProcessTrusted(); },
                [] { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true); },
                [] { return g_stopRequested != 0; });
            if (!granted) {
                std::cout << "minfwm daemon: stopped while waiting for Accessibility permission" << std::endl;
                return 0;
            }
            std::cout << "minfwm daemon: Accessibility permission is active" << std::endl;
        }
        auto systemWide = minfwm::CFRef<AXUIElementRef>::adopt(AXUIElementCreateSystemWide());
        if (!systemWide || AXUIElementSetMessagingTimeout(systemWide.get(), 0.1f) != kAXErrorSuccess) {
            std::cerr << "minfwm daemon: failed to bound Accessibility messaging timeout" << std::endl;
            return 1;
        }

        minfwm::IPCServer server;
        if (!server.start()) {
            std::cerr << "minfwm daemon: failed to start IPC server: " << server.lastError() << std::endl;
            return 1;
        }

        auto& wm = minfwm::WindowManager::instance();
        if (!wm.initialize()) {
            std::cerr << "minfwm daemon: required Yabai Scripting Addition is unavailable; see the installation guide" << std::endl;
            server.stop();
            return 0;
        }

        minfwm::AXObserver observer;
        if (!observer.start()) {
            std::cerr << "minfwm daemon: AX observer started with registration errors" << std::endl;
        }

        minfwm::InputInterceptor interceptor;
        if (!interceptor.start()) {
            std::cerr << "minfwm daemon: event tap unavailable; continuing without global input" << std::endl;
        }

        minfwm::DisplayFrameClock frameClock;
        const bool displayLinked = frameClock.start([&wm](int64_t displayId) {
            if (!g_stopRequested) wm.updateWindows(displayId);
        }, [&wm, &observer] {
            if (g_stopRequested) return;
            wm.refreshDisplays();
            observer.screenConfigurationChanged();
        });
        if (!displayLinked) std::cerr << "minfwm daemon: display link unavailable; using 60 Hz fallback" << std::endl;

        // A separate timer handles signals even when no frames are presented.
        minfwm::IPCServer* serverPtr = &server;
        minfwm::InputInterceptor* interceptorPtr = &interceptor;
        minfwm::AXObserver* observerPtr = &observer;
        minfwm::DisplayFrameClock* clockPtr = &frameClock;
        AXUIElementRef systemWideRef = systemWide.get();
        __block bool shutdownComplete = false;
        [NSTimer scheduledTimerWithTimeInterval:displayLinked ? 0.05 : 1.0/60.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            if (g_stopRequested && !shutdownComplete) {
                [timer invalidate];
                std::cout << "minfwm daemon: stopping input, observers and frame updates" << std::endl;
                clockPtr->stop();
                // Stop producers before restoring window geometry.
                serverPtr->stop();
                interceptorPtr->stop();
                observerPtr->stop();
                if (AXUIElementSetMessagingTimeout(systemWideRef, 0.05f) != kAXErrorSuccess) {
                    std::cerr << "minfwm daemon: failed to set shutdown AX timeout" << std::endl;
                }
                std::cout << "minfwm daemon: restoring windows" << std::endl;
                wm.shutdown();
                std::cout << "minfwm daemon: shutdown complete" << std::endl;
                shutdownComplete = true;
                CFRunLoopStop(CFRunLoopGetMain());
                return;
            }
            if (!g_stopRequested) observerPtr->reconcileWindows();
            if (!displayLinked) wm.updateWindows();
        }];

        server.markReady();
        std::cout << "minfwm daemon: Daemon is running." << std::endl;
        minfwm::runDaemonRunLoop();
    }
    return 0;
}
