#include "DaemonRunLoop.hpp"
#import <Foundation/Foundation.h>

namespace minfwm {
void runDaemonRunLoop() {
    // NSRunLoop.run re-enters the loop after CFRunLoopStop. Run exactly one
    // invocation so the shutdown timer can return control to main.
    CFRunLoopRun();
}
}
