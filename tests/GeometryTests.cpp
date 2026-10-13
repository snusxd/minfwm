#include "Camera.hpp"
#include "DisplayState.hpp"
#include "Visibility.hpp"

#include <cmath>
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

void expectNear(float actual, float expected, const char* message) {
    expect(std::fabs(actual - expected) < 0.0001f, message);
}

} // namespace

int main() {
    using minfwm::core::canUseNativePosition;
    using minfwm::core::Camera;
    using minfwm::core::DisplayGeometry;
    using minfwm::core::DisplayState;
    using minfwm::core::Point;
    using minfwm::core::Rect;
    using minfwm::core::VisibilityPolicy;

    Camera camera;
    camera.move(-125.0f, 80.0f);
    expectNear(camera.x(), -125.0f, "camera keeps negative x movement");
    expectNear(camera.y(), 80.0f, "camera keeps y movement");
    camera.setPosition(400.0f, -900.0f);
    expectNear(camera.position().y, -900.0f, "camera supports negative virtual y");

    const float maximum = std::numeric_limits<float>::max();
    camera.setPosition(maximum, 10);
    camera.move(maximum, 20);
    expect(camera.x() == maximum && camera.y() == 10,
           "overflowing camera movement keeps both coordinates unchanged");
    camera.setPosition(std::numeric_limits<float>::quiet_NaN(), 20);
    expect(camera.x() == maximum && camera.y() == 10,
           "non-finite camera position cannot corrupt the active viewport");
    expect(!camera.move(maximum, 0), "overflowing camera movement reports rejection");
    expect(camera.move(-maximum, -10) && camera.x() == 0 && camera.y() == 0,
           "valid camera movement recovers from a large finite position");

    DisplayState display({ 7, { -1920.0f, -300.0f, 1920.0f, 1080.0f } });
    display.camera().setPosition(-500.0f, 200.0f);
    const Point physicalOrigin = display.virtualToPhysical(Point{ -500.0f, 200.0f });
    expectNear(physicalOrigin.x, -1920.0f, "negative display origin is preserved on x");
    expectNear(physicalOrigin.y, -300.0f, "negative display origin is preserved on y");

    const Rect virtualRect = { -350.0f, 300.0f, 640.0f, 480.0f };
    const Rect physicalRect = display.virtualToPhysical(virtualRect);
    const Rect roundTrip = display.physicalToVirtual(physicalRect);
    expectNear(roundTrip.x, virtualRect.x, "virtual/physical x transform round-trips");
    expectNear(roundTrip.y, virtualRect.y, "virtual/physical y transform round-trips");
    expectNear(roundTrip.w, virtualRect.w, "virtual/physical width is preserved");
    expectNear(roundTrip.h, virtualRect.h, "virtual/physical height is preserved");

    const Rect viewport = display.viewport();
    VisibilityPolicy policy(100.0f);
    expect(policy.shouldRender({ -600.0f, 200.0f, 100.0f, 100.0f }, viewport, false),
           "window inside overscan buffer is rendered");
    expect(!policy.shouldRender({ 1700.0f, 200.0f, 100.0f, 100.0f }, viewport, false),
           "window outside overscan buffer is not rendered");
    expect(policy.shouldRender({ 1700.0f, 200.0f, 100.0f, 100.0f }, viewport, true),
           "focused window bypasses visibility culling");

    display.saveBookmark(3);
    display.camera().setPosition(0.0f, 0.0f);
    expect(display.loadBookmark(3), "existing bookmark loads");
    expectNear(display.camera().x(), -500.0f, "bookmark restores camera x");
    expectNear(display.camera().y(), 200.0f, "bookmark restores camera y");
    expect(!display.loadBookmark(99), "missing bookmark is reported");

    DisplayState zoomed({8, {-1920, -300, 1920, 1080}});
    zoomed.camera().setPosition(-500, 200);
    const Point anchor{-1200, 120};
    const Point anchoredWorld = zoomed.physicalToVirtual(anchor);
    expect(zoomed.setScaleAt(0.5f, anchor), "overview accepts a finite scale");
    expectNear(zoomed.physicalToVirtual(anchor).x, anchoredWorld.x, "zoom preserves the world point under a negative-origin cursor");
    expectNear(zoomed.physicalToVirtual(anchor).y, anchoredWorld.y, "zoom preserves cursor anchor on y");
    expectNear(zoomed.viewport().w, 3840, "zoom out expands the virtual viewport");
    const Rect scaled = zoomed.virtualToPhysical(virtualRect);
    expectNear(scaled.w, 320, "overview scales presentation width without changing model geometry");
    const Rect unscaled = zoomed.physicalToVirtual(scaled);
    expectNear(unscaled.x, virtualRect.x, "scaled rectangle origin round-trips");
    expectNear(unscaled.h, virtualRect.h, "scaled rectangle size round-trips");
    expect(!zoomed.setScaleAt(NAN, anchor) && !zoomed.setScaleAt(0, anchor) &&
           !zoomed.setScaleAt(1.1f, anchor) && zoomed.scale() == 0.5f, "invalid scales leave camera and scale unchanged");
    expect(!zoomed.setScaleAt(0.4f, {INFINITY, 0}) && zoomed.scale() == 0.5f, "invalid anchor is atomic");
    DisplayState sixty({9, {0, 0, 1920, 1080}}), oneTwenty(sixty);
    expect(sixty.requestZoom(-80, {800, 400}) && oneTwenty.requestZoom(-80, {800, 400}), "scroll requests overview");
    for (int i = 0; i < 30; ++i) sixty.advanceZoom(1.0 / 60);
    for (int i = 0; i < 60; ++i) oneTwenty.advanceZoom(1.0 / 120);
    expectNear(sixty.scale(), oneTwenty.scale(), "zoom easing is independent of display refresh rate");
    expect(sixty.overviewActive() && sixty.scale() < 0.5f, "negative scroll zooms out smoothly");
    expect(!sixty.requestZoom(NAN, anchor), "invalid scroll cannot corrupt the target");
    sixty.requestZoom(-10000, {800, 400});
    sixty.advanceZoom(2);
    expectNear(sixty.scale(), 0.2f, "overview scale is bounded at twenty percent");
    sixty.resetZoom({800, 400});
    expect(!sixty.overviewActive() && sixty.scale() == 1, "escape restores exact native scale");
    expectNear(sixty.physicalToVirtual(Point{800, 400}).x, 800, "reset preserves the zoom anchor");

    const Rect usable{0, 31, 1920, 1049};
    expect(canUseNativePosition({100, 100, 640, 480}, usable), "ordinary visible frame prefers native movement");
    expect(canUseNativePosition({-600, 100, 640, 480}, usable), "partially visible window can retain native title-bar input");
    expect(!canUseNativePosition({-601, 100, 640, 480}, usable), "insufficient visible margin keeps translation");
    expect(!canUseNativePosition({100, -120, 640, 480}, usable), "above-menu-bar movement uses translation");
    expect(!canUseNativePosition({100, 1050, 640, 480}, usable), "below-screen frame keeps translation");
    expect(canUseNativePosition({-1800, -200, 640, 480}, {-1920, -269, 1920, 1049}), "native placement accepts negative display origins");
    expect(!canUseNativePosition({NAN, 100, 640, 480}, usable), "invalid native placement is rejected");
    return failures == 0 ? 0 : 1;
}
