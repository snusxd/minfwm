#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <iostream>

namespace {
NSArray* selectedEntries;
NSArray* allEntries;
int failures = 0;

CFArrayRef fakeWindowInfo(CGWindowListOption option, CGWindowID) {
    NSArray* entries = option == kCGWindowListOptionAll ? allEntries : selectedEntries;
    return entries ? static_cast<CFArrayRef>(CFRetain((CFArrayRef)entries)) : nullptr;
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
        auto snapshot = minfwm::readOnscreenWindowSnapshot();
        expect(snapshot && snapshot->size() == 1 && snapshot->front().wid == 42 &&
               snapshot->front().frame.origin.x == 100 && snapshot->front().frame.origin.y == 200,
               "onscreen hit-test snapshot keeps window bounds and front-to-back order");
        selectedEntries = @[window(77, 10, 20), window(42, 100, 200),
                            @{(id)kCGWindowNumber: @88, (id)kCGWindowBounds: @"malformed"}];
        snapshot = minfwm::readOnscreenWindowSnapshot();
        expect(snapshot && snapshot->size() == 2 && snapshot->at(0).wid == 77 && snapshot->at(1).wid == 42,
               "onscreen hit-test snapshot preserves stacking order and skips malformed bounds");
        selectedEntries = @[];
        visible = minfwm::readOnscreenWindowIds();
        expect(visible && visible->empty(), "empty onscreen list is a valid absence of presented windows");
        allEntries = @[window(42, -100, -200), window(99, 0, 0), window(0, 0, 0)];
        const auto session = minfwm::readSessionWindowIds();
        expect(session && session->size() == 2 && session->contains(42) && session->contains(99),
               "full-session reconciliation includes offscreen and hidden windows");
        allEntries = nil;
        expect(!minfwm::readSessionWindowIds(), "failed full-session query cannot be treated as an empty session");
        minfwm::NativeWindowPresentation presentation{CGRectMake(100, 200, 640, 480), CGAffineTransformIdentity};
        expect(minfwm::needsNativePresentationRecovery(presentation), "system zero-origin presentation needs normalization");
        presentation.transform = CGAffineTransformMakeTranslation(-100, -200);
        expect(!minfwm::needsNativePresentationRecovery(presentation), "normal native baseline needs no recovery");
        presentation.transform = CGAffineTransformMakeTranslation(-50, -75);
        expect(!minfwm::needsNativePresentationRecovery(presentation), "foreign nonzero translation is preserved");
        presentation.transform = CGAffineTransformMakeScale(2, 2);
        expect(!minfwm::needsNativePresentationRecovery(presentation), "foreign scaling is preserved");
        presentation.transform = CGAffineTransformIdentity;
        presentation.frame.origin = CGPointZero;
        expect(!minfwm::needsNativePresentationRecovery(presentation), "identity at native origin is already normalized");
        const minfwm::core::Rect projected{-100.4f, -300.6f, 320, 240};
        presentation.transform = CGAffineTransformMake(2, 0, 0, 2, 200, 602);
        expect(minfwm::nativePresentationMatches(presentation, projected, .5f),
               "presentation matcher uses inverse scale and rounded negative origin");
        presentation.transform.tx = 202;
        expect(!minfwm::nativePresentationMatches(presentation, projected, .5f),
               "actual transform drift is detected independently of the renderer cache");
        presentation.transform.a = NAN;
        expect(!minfwm::nativePresentationMatches(presentation, projected, .5f) &&
               !minfwm::nativePresentationMatches(presentation, projected, 0),
               "invalid transform and scale cannot masquerade as matching presentation");
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
