#import <Foundation/Foundation.h>
#include "DaemonRunLoop.hpp"
#include <iostream>

int main() {
    @autoreleasepool {
        __block bool stopped = false;
        [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer* timer) {
            stopped = true;
            [timer invalidate];
            CFRunLoopStop(CFRunLoopGetMain());
        }];
        minfwm::runDaemonRunLoop();
        if (!stopped) {
            std::cerr << "run loop returned without processing shutdown\n";
            return 1;
        }
    }
    return 0;
}
