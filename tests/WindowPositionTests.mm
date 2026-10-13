#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <iostream>

namespace {
NSArray* selectedEntries;
NSArray* allEntries;
int failures = 0;

CFArrayRef fakeWindowInfo(CGWindowListOption option, CGWindowID) {
    return static_cast<CFArrayRef>(CFRetain((CFArrayRef)(option == kCGWindowListOptionAll ? allEntries : selectedEntries)));
}

NSDictionary* window(uint32_t wid, double x, double y) {
    return @{(id)kCGWindowNumber: @(wid), (id)kCGWindowBounds:
        @{ @"X": @(x), @"Y": @(y), @"Width": @640, @"Height": @480 }};
}

void expect(bool condition, const char* message) {
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}
}

// Exercise the adapter's parsing without a live WindowServer or AX calls.
#define CGWindowListCopyWindowInfo fakeWindowInfo
#include "../src/daemon/WindowPosition.mm"
#undef CGWindowListCopyWindowInfo

int main() {
    @autoreleasepool {
        selectedEntries = @[window(42, 100, 200), window(0, 0, 0), @{@"not-a-window": @1}];
        auto visible = minfwm::readOnscreenWindowIds();
        expect(visible && visible->size() == 1 && visible->contains(42), "onscreen snapshot ignores invalid IDs and malformed entries");
        selectedEntries = @[];
        visible = minfwm::readOnscreenWindowIds();
        expect(visible && visible->empty(), "empty onscreen list is a valid absence of presented windows");
        CGPoint position{7, 8};
        selectedEntries = @[];
        allEntries = @[window(99, 999, 999), window(42, 10, -120)];
        expect(minfwm::readWindowPosition(nullptr, 42, position) && position.x == 10 && position.y == -120,
               "empty selected-window query falls back to exact WID in the full session list");
        selectedEntries = @[window(99, 888, 888)];
        expect(minfwm::readWindowPosition(nullptr, 42, position) && position.x == 10 && position.y == -120,
               "a dictionary for another window is never used as successful readback");
        selectedEntries = @[window(42, -200, -300)];
        expect(minfwm::readWindowPosition(nullptr, 42, position) && position.x == -200 && position.y == -300,
               "normal selected-window query retains negative coordinates");
        selectedEntries = @[];
        allEntries = @[window(99, 999, 999)];
        expect(!minfwm::readWindowPosition(nullptr, 42, position) && position.x == -200 && position.y == -300,
               "missing WID fails without inventing a position");
        allEntries = @[@{(id)kCGWindowNumber: @42, (id)kCGWindowBounds: @"malformed"}];
        expect(!minfwm::readWindowPosition(nullptr, 42, position), "malformed bounds fail safely");
    }
    return failures ? 1 : 0;
}
