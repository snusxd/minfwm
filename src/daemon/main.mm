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

        // Verify accessibility permissions
        NSDictionary *options = @{(id)kAXTrustedCheckOptionPrompt: @YES};
        if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
            std::cerr << "minfwm daemon: Accessibility permission is not active. Grant it in System Settings, then run `minfwm restart`."
                      << std::endl;
            // Exit successfully so launchd's KeepAlive policy doesn't relaunch
            // the daemon and show the same permission prompt forever.
            return 0;
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

        std::cout << "minfwm daemon: Daemon is running." << std::endl;
        minfwm::runDaemonRunLoop();
    }
    return 0;
}
