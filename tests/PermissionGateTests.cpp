#include "AccessibilityPermission.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* message) {
    if (condition) return;
    std::cerr << "FAILED: " << message << '\n';
    std::exit(1);
}

} // namespace

int main() {
    int checks = 0;
    int waits = 0;
    const bool granted = minfwm::waitUntilAccessibilityPermissionGranted(
        [&] { return ++checks >= 3; },
        [&] { ++waits; },
        [] { return false; });

    expect(granted, "permission grant after startup is detected");
    expect(checks == 3, "permission is refreshed on each retry");
    expect(waits == 2, "the wait callback runs between checks");

    checks = 0;
    waits = 0;
    const bool stopped = minfwm::waitUntilAccessibilityPermissionGranted(
        [&] { ++checks; return false; },
        [&] { ++waits; },
        [&] { return waits == 2; });

    expect(!stopped, "the wait ends when shutdown is requested");
    expect(checks == 2, "permission checks stop after shutdown");
    expect(waits == 2, "shutdown is observed after the pending wait");
}
