#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <iostream>
#include <signal.h>
#include "WindowManager.hpp"
#include "AXObserver.hpp"
#include "InputInterceptor.hpp"
#include "IPCServer.hpp"

namespace {
volatile sig_atomic_t g_stopRequested = 0;

void requestStop(int) {
    g_stopRequested = 1;
}
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
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

        auto& wm = minfwm::WindowManager::instance();
        if (!wm.initialize()) {
            std::cerr << "minfwmd: failed to initialize display state" << std::endl;
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

        minfwm::IPCServer server;
        if (!server.start()) {
            std::cerr << "minfwmd: failed to start IPC server: " << server.lastError() << std::endl;
            interceptor.stop();
            observer.stop();
            wm.shutdown();
            return 1;
        }

        // High-frequency timer for window updates (60Hz)
        minfwm::IPCServer* serverPtr = &server;
        minfwm::InputInterceptor* interceptorPtr = &interceptor;
        minfwm::AXObserver* observerPtr = &observer;
        __block bool shutdownComplete = false;
        [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            if (g_stopRequested && !shutdownComplete) {
                [timer invalidate];
                // Stop producers before restoring window geometry.
                serverPtr->stop();
                interceptorPtr->stop();
                observerPtr->stop();
                wm.shutdown();
                shutdownComplete = true;
                CFRunLoopStop(CFRunLoopGetMain());
                return;
            }
            minfwm::WindowManager::instance().updateWindows();
        }];

        std::cout << "minfwmd: Daemon is running." << std::endl;
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
