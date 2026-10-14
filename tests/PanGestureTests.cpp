#include "PanGesture.hpp"
#include "Geometry.hpp"

#include <array>
#include <iostream>
#include <limits>

namespace {
int failures = 0;

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}
}

int main() {
    using namespace minfwm::core;

    const std::array displays{
        DisplayGeometry{2, {-1920, -300, 1920, 1080}},
        DisplayGeometry{1, {0, 0, 1920, 1080}},
    };
    expect(nearestDisplay(displays, {-100, -100}) == 2,
           "pointer on a display with negative origin selects that display");
    expect(nearestDisplay(displays, {0, 100}) == 1,
           "shared display edge belongs to the display containing the pointer");
    expect(nearestDisplay(displays, {-2000, 100}) == 2,
           "pointer outside displays selects the nearest display");
    expect(!nearestDisplay({}, {0, 0}), "empty display layout has no target");
    const float nan = std::numeric_limits<float>::quiet_NaN();
    expect(!nearestDisplay(displays, {nan, 0}), "non-finite pointer has no target");
    const std::array invalidDisplays{
        DisplayGeometry{3, {nan, 0, 1920, 1080}}, DisplayGeometry{4, {0, 0, -1, 1080}},
    };
    expect(!nearestDisplay(invalidDisplays, {0, 0}), "invalid display geometry is ignored");

    PanGesture gesture;
    expect(!gesture.handle(PanEvent::mouseDown, false, 1).consume,
           "ordinary click passes through");
    expect(!gesture.handle(PanEvent::mouseDragged, true, 1, {10, 20}).consume,
           "pressing modifiers during an ordinary drag does not steal the gesture");
    expect(!gesture.handle(PanEvent::mouseUp, true, 1).consume,
           "ordinary gesture retains its mouse-up");

    expect(gesture.handle(PanEvent::mouseDown, true, 2).consume,
           "Super mouse-down captures the gesture");
    expect(gesture.isPanning(), "captured gesture enters panning");
    const auto drag = gesture.handle(PanEvent::mouseDragged, true, 1, {10, -20});
    expect(drag.consume && drag.displayId == 2,
           "crossing displays retains the display chosen on mouse-down");
    expect(drag.delta.x == -10 && drag.delta.y == 20,
           "drag moves the camera opposite to the pointer");

    gesture.handle(PanEvent::modifiersChanged, false, 1);
    expect(!gesture.isPanning(), "releasing a modifier ends panning");
    const auto cancelledDrag = gesture.handle(PanEvent::mouseDragged, true, 1, {10, 20});
    expect(cancelledDrag.consume && cancelledDrag.delta.x == 0 && cancelledDrag.delta.y == 0,
           "cancelled drag stays consumed and does not restart on modifier re-press");
    expect(gesture.handle(PanEvent::mouseUp, false, 1).consume,
           "captured mouse-up is consumed even after modifiers are released");
    expect(!gesture.handle(PanEvent::mouseUp, true, 1).consume,
           "mouse-up resets capture idempotently");

    gesture.handle(PanEvent::mouseDown, true, 2);
    gesture.reset();
    gesture.reset();
    expect(!gesture.isPanning(), "tap reset and stop clear panning idempotently");
    expect(!gesture.handle(PanEvent::mouseDragged, true, 2, {1, 1}).consume,
           "tap reset cannot resume an interrupted drag");

    gesture.handle(PanEvent::mouseDown, true, 2);
    const auto releaseDuringDrag = gesture.handle(PanEvent::mouseDragged, false, 2, {1, 1});
    expect(releaseDuringDrag.consume && !gesture.isPanning() && releaseDuringDrag.delta.x == 0,
           "drag detects modifier release even without a flags-changed event");

    return failures == 0 ? 0 : 1;
}
