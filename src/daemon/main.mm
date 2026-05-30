#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <iostream>
#include "WindowManager.hpp"
#include "AXObserver.hpp"
#include "InputInterceptor.hpp"
#include "IPCServer.hpp"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        std::cout << "minfwmd: Starting macOS Infinite Window Manager daemon..." << std::endl;

        // Verify accessibility permissions
        NSDictionary *options = @{(id)kAXTrustedCheckOptionPrompt: @YES};
        if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
            std::cerr << "minfwmd: Error - Accessibility permissions not granted." << std::endl;
            return 1;
        }

        // Initialize components
        auto& wm = minfwm::WindowManager::instance();
        wm.initialize();

        minfwm::AXObserver observer;
        observer.start();

        minfwm::InputInterceptor interceptor;
        interceptor.start();

        minfwm::IPCServer server;
        server.start();

        std::cout << "minfwmd: Daemon is running." << std::endl;

        // Start run loop
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
