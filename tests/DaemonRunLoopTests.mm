#import <Foundation/Foundation.h>
#include "DaemonRunLoop.hpp"
#include "WindowManager.hpp"
#include <cmath>
#include <iostream>

int main() {
    @autoreleasepool {
        minfwm::ClientWindow window(nullptr, 42);
        const minfwm::core::Rect original{-300, 120, 640, 480};
        const minfwm::core::Rect target{0, 25, 1920, 1055};
        window.virtualRect = original;
        window.frameAnimation = minfwm::ClientWindow::FrameAnimation{original, target, 10};
        auto& manager = minfwm::WindowManager::instance();
        manager.advanceWindowAnimation(window, 10);
        if (window.virtualRect.x != original.x || window.virtualRect.w != original.w) return 1;
        manager.advanceWindowAnimation(window, 10.18);
        if (std::abs(window.virtualRect.x - (original.x + target.x) / 2) > 0.01 ||
            std::abs(window.virtualRect.h - (original.h + target.h) / 2) > 0.01 ||
            !window.needsGeometryRestore) {
            std::cerr << "frame animation must interpolate position and size together\n";
            return 1;
        }
        // Navigation may interrupt expansion; restoration starts at the current frame.
        window.frameAnimation = minfwm::ClientWindow::FrameAnimation{window.virtualRect, original, 10.18};
        manager.advanceWindowAnimation(window, 10.55);
        if (window.frameAnimation || window.virtualRect.x != original.x || window.virtualRect.w != original.w) return 1;
        window.frameAnimation = minfwm::ClientWindow::FrameAnimation{original, target, 11};
        manager.advanceWindowAnimation(window, 11, 1, false);
        if (window.frameAnimation || window.virtualRect.y != target.y || window.virtualRect.h != target.h) return 1;

        window.virtualRect = target;
        window.frameAnimation = minfwm::ClientWindow::FrameAnimation{target, original, 12, true};
        manager.advanceWindowAnimation(window, 12.09);
        if (std::abs(window.virtualRect.x - (original.x + target.x) / 2) > 0.01 ||
            window.virtualRect.y != target.y || window.virtualRect.h != target.h) {
            std::cerr << "first restore phase must move only left/right edges\n";
            return 1;
        }
        manager.advanceWindowAnimation(window, 12.27);
        if (window.virtualRect.x != original.x || window.virtualRect.w != original.w ||
            std::abs(window.virtualRect.h - (original.h + target.h) / 2) > 0.01) {
            std::cerr << "second restore phase must retain width and move top/bottom edges\n";
            return 1;
        }
        manager.advanceWindowAnimation(window, 12.37);
        if (window.frameAnimation || window.virtualRect.y != original.y || window.virtualRect.h != original.h) return 1;

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
