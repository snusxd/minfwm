#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

#include "WindowPool.hpp"

#include <iostream>
#include <unistd.h>

namespace {

int failures = 0;

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

std::uint32_t fixedWindowId(AXUIElementRef) {
    return 42;
}

std::uint32_t noWindowId(AXUIElementRef) {
    return 0;
}

} // namespace

int main() {
    @autoreleasepool {
        AXUIElementRef firstRef = AXUIElementCreateSystemWide();
        AXUIElementRef secondRef = AXUIElementCreateApplication(getpid());
        expect(firstRef != nullptr && secondRef != nullptr, "test AX references are created");
        if (!firstRef || !secondRef) {
            if (firstRef) CFRelease(firstRef);
            if (secondRef) CFRelease(secondRef);
            return 1;
        }

        minfwm::WindowPool pool(&fixedWindowId);
        const auto first = pool.addWindow(firstRef);
        const auto sameByAXRef = pool.addWindow(firstRef);
        const auto sameByWID = pool.addWindow(secondRef);

        expect(first != nullptr, "first window is added");
        expect(first == sameByAXRef, "same AX ref is idempotent");
        expect(first == sameByWID, "same WID is idempotent");
        expect(pool.windows().size() == 1, "indexes prevent duplicate records");
        expect(pool.findWindowByWID(42) == first, "WID index returns canonical record");
        expect(pool.findWindowByAXRef(firstRef) == first, "AX ref index returns canonical record");

        pool.removeWindow(secondRef);
        expect(pool.windows().empty(), "remove erases the canonical record");
        expect(pool.findWindowByWID(42) == nullptr, "remove erases WID index");
        expect(pool.findWindowByAXRef(firstRef) == nullptr, "remove erases AX ref index");

        minfwm::WindowPool refOnlyPool(&noWindowId);
        const auto refOnly = refOnlyPool.addWindow(firstRef);
        expect(refOnlyPool.addWindow(firstRef) == refOnly, "AX ref remains fallback identity when WID is unavailable");
        expect(refOnlyPool.windows().size() == 1, "zero WID does not create a shared index entry");
        refOnlyPool.removeWindow(firstRef);
        expect(refOnlyPool.windows().empty(), "zero-WID record is removable by AX ref");

        minfwm::WindowPool publicAXPool;
        const auto publicAXWindow = publicAXPool.addWindow(firstRef);
        expect(publicAXWindow && publicAXWindow->wid() == 0,
               "default AX pool does not require the optional WID resolver");

        expect(pool.addWindow(nullptr) == nullptr, "null AX ref is rejected");

        CFRelease(firstRef);
        CFRelease(secondRef);
    }

    return failures == 0 ? 0 : 1;
}
