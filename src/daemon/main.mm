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

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc > 1) {
            std::cerr << "minfwmd: does not accept arguments" << std::endl;
            return 2;
        }
        std::cout << "minfwmd: Starting macOS Infinite Window Manager daemon..." << std::endl;
        
        // Prevent crash on socket errors
        signal(SIGPIPE, SIG_IGN);
        signal(SIGINT, requestStop);
        signal(SIGTERM, requestStop);

        // Verify accessibility permissions
        NSDictionary *options = @{(id)kAXTrustedCheckOptionPrompt: @YES};
        if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
            std::cerr << "minfwmd: Error - Accessibility permissions not granted." << std::endl;
            return 1;
        }
        auto systemWide = minfwm::CFRef<AXUIElementRef>::adopt(AXUIElementCreateSystemWide());
        if (!systemWide || AXUIElementSetMessagingTimeout(systemWide.get(), 0.1f) != kAXErrorSuccess) {
            std::cerr << "minfwmd: failed to bound Accessibility messaging timeout" << std::endl;
            return 1;
        }

        minfwm::IPCServer server;
        if (!server.start()) {
            std::cerr << "minfwmd: failed to start IPC server: " << server.lastError() << std::endl;
            return 1;
        }

        auto& wm = minfwm::WindowManager::instance();
        if (!wm.initialize()) {
            std::cerr << "minfwmd: required Yabai Scripting Addition is unavailable; see the installation guide" << std::endl;
            server.stop();
            return 1;
        }

        minfwm::AXObserver observer;
        if (!observer.start()) {
            std::cerr << "minfwmd: AX observer started with registration errors" << std::endl;
        }

        minfwm::InputInterceptor interceptor;
        if (!interceptor.start()) {
            std::cerr << "minfwmd: event tap unavailable; continuing without global input" << std::endl;
        }

        minfwm::DisplayFrameClock frameClock;
        const bool displayLinked = frameClock.start([&wm](int64_t displayId) {
            if (!g_stopRequested) wm.updateWindows(displayId);
        });
        if (!displayLinked) std::cerr << "minfwmd: display link unavailable; using 60 Hz fallback" << std::endl;

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
                std::cout << "minfwmd: stopping input, observers and frame updates" << std::endl;
                clockPtr->stop();
                // Stop producers before restoring window geometry.
                serverPtr->stop();
                interceptorPtr->stop();
                observerPtr->stop();
                if (AXUIElementSetMessagingTimeout(systemWideRef, 0.05f) != kAXErrorSuccess) {
                    std::cerr << "minfwmd: failed to set shutdown AX timeout" << std::endl;
                }
                std::cout << "minfwmd: restoring windows" << std::endl;
                wm.shutdown();
                std::cout << "minfwmd: shutdown complete" << std::endl;
                shutdownComplete = true;
                CFRunLoopStop(CFRunLoopGetMain());
                return;
            }
            if (!g_stopRequested) observerPtr->reconcileWindows();
            if (!displayLinked) wm.updateWindows();
        }];

        std::cout << "minfwmd: Daemon is running." << std::endl;
        minfwm::runDaemonRunLoop();
    }
    return 0;
}
