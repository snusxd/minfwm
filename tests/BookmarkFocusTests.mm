#import <ApplicationServices/ApplicationServices.h>

#include "../src/daemon/BookmarkFocus.hpp"
#include "../src/daemon/WindowManager.hpp"

#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(bool condition, const char* message) {
    if (condition) return;
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
}

AXUIElementRef expectedWindow = nullptr;
AXUIElementRef expectedApplication = nullptr;
bool focusedAttributeSupported = true;
std::vector<std::string> calls;

AXError recordAction(AXUIElementRef element, CFStringRef action) {
    expect(element == expectedWindow, "bookmark raises the saved window");
    expect(CFEqual(action, kAXRaiseAction), "bookmark requests the raise action");
    calls.emplace_back("raise");
    return kAXErrorSuccess;
}

AXError recordAttribute(AXUIElementRef element, CFStringRef attribute, CFTypeRef value) {
    if (CFEqual(attribute, kAXFocusedAttribute)) {
        expect(element == expectedWindow, "keyboard focus is requested on the saved window");
        expect(value == kCFBooleanTrue, "bookmark requests keyboard focus");
        calls.emplace_back("focused");
        return focusedAttributeSupported ? kAXErrorSuccess : kAXErrorAttributeUnsupported;
    }
    expect(CFEqual(attribute, kAXFocusedWindowAttribute), "fallback targets the app focused-window attribute");
    expect(element == expectedApplication, "fallback uses the saved window's application");
    expect(value == expectedWindow, "fallback selects the saved window");
    calls.emplace_back("application-focused-window");
    return kAXErrorSuccess;
}

void testAXFocusRequest() {
    expectedWindow = reinterpret_cast<AXUIElementRef>(static_cast<uintptr_t>(1));
    expectedApplication = reinterpret_cast<AXUIElementRef>(static_cast<uintptr_t>(2));
    focusedAttributeSupported = true;
    calls.clear();
    expect(minfwm::focusBookmarkWindow(expectedApplication, expectedWindow, recordAction, recordAttribute),
           "AXFocused success restores bookmark focus");
    expect(calls == std::vector<std::string>({"raise", "focused"}),
           "bookmark focuses after raising the saved window");

    focusedAttributeSupported = false;
    calls.clear();
    expect(minfwm::focusBookmarkWindow(expectedApplication, expectedWindow, recordAction, recordAttribute),
           "application focused-window fallback restores bookmark focus");
    expect(calls == std::vector<std::string>({"raise", "focused", "application-focused-window"}),
           "application fallback runs only after direct AX focus is unsupported");

    calls.clear();
    expect(!minfwm::focusBookmarkWindow(nullptr, nullptr, recordAction, recordAttribute),
           "missing bookmark window cannot be focused");
    expect(calls.empty(), "missing bookmark window performs no AX actions");
}

void testBookmarkFocusWaitsForPresentation() {
    using minfwm::BookmarkFocusReadiness;
    expect(minfwm::bookmarkFocusReadiness(true, false, true, false, false) ==
               BookmarkFocusReadiness::waitForPresentation,
           "an offscreen bookmark window waits for its next presentation instead of being discarded");
    expect(minfwm::bookmarkFocusReadiness(true, false, false, false, false) ==
               BookmarkFocusReadiness::ready,
           "a presented bookmark window can receive its focus request");
    expect(minfwm::bookmarkFocusReadiness(true, true, false, false, false) ==
               BookmarkFocusReadiness::unavailable,
           "a bookmark window from an explicitly hidden app is not focused");
    expect(minfwm::bookmarkFocusReadiness(false, false, true, false, false) ==
               BookmarkFocusReadiness::unavailable,
           "a bookmark window that left the managed pool is not focused");
}

void testDisplayBookmarkFocusStorage() {
    minfwm::Display display(4, {0, 0, 1440, 900});
    auto first = std::make_shared<minfwm::ClientWindow>(nullptr, 12435);
    auto second = std::make_shared<minfwm::ClientWindow>(nullptr, 12459);

    display.saveBookmark(2, first, true);
    expect(display.loadBookmark(2) == first,
           "bookmark returns the same live window saved with it");

    display.saveBookmark(2, second, true);
    expect(display.loadBookmark(2) == second,
           "overwriting a bookmark replaces its saved focus window");

    display.saveBookmark(2, first, false);
    expect(!display.loadBookmark(2),
           "disabled focus saving clears focus from an overwritten bookmark");

    display.saveBookmark(3, first, true);
    first.reset();
    expect(!display.loadBookmark(3),
           "bookmark does not retain a destroyed window through a stale weak reference");
}

} // namespace

int main() {
    @autoreleasepool {
        testAXFocusRequest();
        testBookmarkFocusWaitsForPresentation();
        testDisplayBookmarkFocusStorage();
    }
    return failures == 0 ? 0 : 1;
}
