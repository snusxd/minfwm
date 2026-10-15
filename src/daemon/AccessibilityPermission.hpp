#pragma once

namespace minfwm {

template <typename IsGranted, typename Wait, typename ShouldStop>
bool waitUntilAccessibilityPermissionGranted(IsGranted isGranted,
                                             Wait wait,
                                             ShouldStop shouldStop) {
    while (!shouldStop()) {
        if (isGranted()) return true;
        wait();
    }
    return false;
}

} // namespace minfwm
