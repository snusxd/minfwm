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

        minfwm::WindowPool processPool;
        const auto applicationWindow = processPool.addWindow(secondRef);
        processPool.addWindow(firstRef);
        expect(applicationWindow->pid() == getpid(), "window captures its application owner");
        processPool.removeWindowsForPid(getpid());
        expect(processPool.findWindowByAXRef(secondRef) == nullptr,
               "application termination removes its windows from the AX index");
        expect(processPool.windows().size() == 1,
               "application termination preserves other owners");
        processPool.removeWindowsForPid(getpid());
        expect(processPool.windows().size() == 1, "application termination is idempotent");
        processPool.removeWindowsForPid(0);
        expect(processPool.windows().size() == 1, "unknown owner is not an application termination");

        minfwm::WindowPool ownedWidPool(&fixedWindowId);
        ownedWidPool.addWindow(secondRef);
        ownedWidPool.removeWindowsForPid(getpid());
        expect(ownedWidPool.windows().empty() && !ownedWidPool.findWindowByWID(42),
               "application termination also erases the WID index");

        minfwm::WindowPool reconciledPool(&fixedWindowId);
        const auto stale = reconciledPool.addWindow(secondRef);
        expect(reconciledPool.removeMissingWindows({42}).empty(), "session reconciliation preserves existing windows");
        const auto removed = reconciledPool.removeMissingWindows({99});
        expect(removed.size() == 1 && removed.front() == stale && reconciledPool.windows().empty() &&
               !reconciledPool.findWindowByWID(42) && !reconciledPool.findWindowByAXRef(secondRef),
               "missing destruction notifications cannot leave stale records in either index");
        expect(reconciledPool.removeMissingWindows({99}).empty(), "session reconciliation is idempotent");
        expect(reconciledPool.addWindow(secondRef) != stale, "a reopened window gets a fresh model");
        expect(refOnlyPool.addWindow(firstRef) && refOnlyPool.removeMissingWindows({}).empty() &&
               refOnlyPool.windows().size() == 1, "WindowServer reconciliation preserves public AX-only records");

        CFRelease(firstRef);
        CFRelease(secondRef);
    }

    return failures == 0 ? 0 : 1;
}
