#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <iostream>
#include <signal.h>
#include "WindowManager.hpp"
#include "AXObserver.hpp"
#include "InputInterceptor.hpp"
#include "IPCServer.hpp"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        std::cout << "minfwmd: Starting macOS Infinite Window Manager daemon..." << std::endl;
        
        // Prevent crash on socket errors
        signal(SIGPIPE, SIG_IGN);

        // Verify accessibility permissions
        NSDictionary *options = @{(id)kAXTrustedCheckOptionPrompt: @YES};
        if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
            std::cerr << "minfwmd: Error - Accessibility permissions not granted." << std::endl;
            return 1;
        }

        auto& wm = minfwm::WindowManager::instance();
        wm.initialize();

        minfwm::AXObserver observer;
        observer.start();

        minfwm::InputInterceptor interceptor;
        interceptor.start();

        minfwm::IPCServer server;
        server.start();

        // High-frequency timer for window updates (60Hz)
        [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            minfwm::WindowManager::instance().updateWindows();
        }];

        std::cout << "minfwmd: Daemon is running." << std::endl;
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
