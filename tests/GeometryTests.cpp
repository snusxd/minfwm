#include "Camera.hpp"
#include "DisplayState.hpp"
#include "Visibility.hpp"
#include "WindowOwnership.hpp"
#include "WindowDrag.hpp"

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
    using minfwm::core::shouldTransferWindow;
    using minfwm::core::shouldReleaseToIgnoredDisplay;
    using minfwm::core::shouldPreferNativePosition;
    using minfwm::core::frameFitsDisplay;
    using minfwm::core::nearestDisplay;
    using minfwm::core::snapViewportToNearFullscreenWindow;
    using minfwm::core::SnapTuning;
    using minfwm::core::dragPointerOffset;
    using minfwm::core::draggedVirtualOrigin;

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
    expect(display.updateGeometry({7, {-2560.0f, -300.0f, 2560.0f, 1440.0f}}),
           "screen geometry can update without replacing its display state");
    expectNear(display.camera().x(), -500.0f, "screen geometry updates preserve that display camera");
    expect(!display.updateGeometry({8, {0, 0, 1920, 1080}}), "screen geometry cannot change display identity");
    expect(!display.updateGeometry({7, {0, 0, 0, 1080}}), "invalid screen geometry is rejected");
    expect(display.updateGeometry({7, {-1920.0f, -300.0f, 1920.0f, 1080.0f}}),
           "valid screen geometry can be restored after rejected updates");
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

    const Rect previousViewport{-1975, -340, 1920, 1080};
    const Rect nearWindowViewport{-1925, -300, 1920, 1080};
    const Rect nearFullscreenWindow{-1900, -285, 1880, 1050};
    const Rect snappedViewport = snapViewportToNearFullscreenWindow(
        previousViewport, nearWindowViewport, nearFullscreenWindow, 32);
    expectNear(snappedViewport.x, -1940, "camera viewport snaps its right edge to a near-fullscreen window");
    expectNear(snappedViewport.y, -285, "camera viewport snaps its top edge to a near-fullscreen window");
    const Rect explicitAuto = snapViewportToNearFullscreenWindow(
        previousViewport, nearWindowViewport, nearFullscreenWindow, 32,
        SnapTuning::automatic, SnapTuning::automatic);
    expectNear(explicitAuto.x, snappedViewport.x, "explicit automatic horizontal tuning preserves current snap behavior");
    expectNear(explicitAuto.y, snappedViewport.y, "explicit automatic vertical tuning preserves current snap behavior");
    const Rect topLeft = snapViewportToNearFullscreenWindow(
        previousViewport, nearWindowViewport, nearFullscreenWindow, 32,
        SnapTuning::leading, SnapTuning::leading);
    expectNear(topLeft.x, -1900, "left tuning places the window at the viewport left edge");
    expectNear(topLeft.y, -285, "top tuning places the window at the viewport top edge");
    const Rect bottomRight = snapViewportToNearFullscreenWindow(
        previousViewport, nearWindowViewport, nearFullscreenWindow, 32,
        SnapTuning::trailing, SnapTuning::trailing);
    expectNear(bottomRight.x, -1940, "right tuning places the window at the viewport right edge");
    expectNear(bottomRight.y, -315, "bottom tuning places the window at the viewport bottom edge");
    const Rect centered = snapViewportToNearFullscreenWindow(
        previousViewport, nearWindowViewport, nearFullscreenWindow, 32,
        SnapTuning::center, SnapTuning::center);
    expectNear(centered.x, -1920, "horizontal center tuning centers the window");
    expectNear(centered.y, -300, "vertical center tuning centers the window");
    const Rect verticalOnly = snapViewportToNearFullscreenWindow(
        {-1700, -340, 1920, 1080}, {-1700, -300, 1920, 1080}, nearFullscreenWindow, 32,
        SnapTuning::leading, SnapTuning::automatic);
    expectNear(verticalOnly.x, -1900, "fixed horizontal tuning applies when vertical proximity triggers snap");
    expectNear(verticalOnly.y, -285, "automatic vertical tuning still chooses its nearest edge");
    const Rect horizontalOnly = snapViewportToNearFullscreenWindow(
        {-1975, 0, 1920, 1080}, {-1925, 0, 1920, 1080}, nearFullscreenWindow, 32,
        SnapTuning::automatic, SnapTuning::trailing);
    expectNear(horizontalOnly.x, -1940, "automatic horizontal tuning still chooses its nearest edge");
    expectNear(horizontalOnly.y, -315, "fixed vertical tuning applies when horizontal proximity triggers snap");
    const Rect outOfRange = snapViewportToNearFullscreenWindow(
        {-2100, -500, 1920, 1080}, {-2000, -400, 1920, 1080}, nearFullscreenWindow, 32,
        SnapTuning::leading, SnapTuning::leading);
    expectNear(outOfRange.x, -2000, "fixed tuning does not trigger snap outside the threshold");
    const Rect ordinaryWindow{-1900, -285, 1200, 800};
    const Rect unsnappedViewport = snapViewportToNearFullscreenWindow(
        previousViewport, nearWindowViewport, ordinaryWindow, 32);
    expectNear(unsnappedViewport.x, nearWindowViewport.x, "camera does not snap to ordinary-sized windows");
    const Rect untunedOrdinary = snapViewportToNearFullscreenWindow(
        previousViewport, nearWindowViewport, ordinaryWindow, 32,
        SnapTuning::leading, SnapTuning::leading);
    expectNear(untunedOrdinary.x, nearWindowViewport.x,
               "fixed tuning does not make ordinary windows eligible for snap");
    const Rect screenViewportBefore{0, 50, 1352, 878};
    const Rect screenViewportAfter{0, 70, 1352, 878};
    const Rect smallTerminal{14, 82, 1166, 704};
    const Rect terminalSnap = snapViewportToNearFullscreenWindow(
        screenViewportBefore, screenViewportAfter, smallTerminal, 64);
    expectNear(terminalSnap.y, screenViewportAfter.y,
               "an 86%-wide, 80%-tall terminal is not nearly fullscreen");
    const Rect nearFullscreenApp{0, 74, 1352, 804};
    const Rect appSnap = snapViewportToNearFullscreenWindow(
        {0, 30, 1352, 878}, {0, 60, 1352, 878}, nearFullscreenApp, 64);
    expectNear(appSnap.y, 74,
               "a window covering over 90% of both display dimensions can still snap");
    const Rect movingAway = snapViewportToNearFullscreenWindow(
        nearWindowViewport, {-1970, -300, 1920, 1080}, nearFullscreenWindow, 32);
    expectNear(movingAway.x, -1970, "camera can move away after passing a snap point");
    const Rect widerSnap = snapViewportToNearFullscreenWindow(
        {-2100, -340, 1920, 1080}, {-1990, -300, 1920, 1080}, nearFullscreenWindow, 64);
    expectNear(widerSnap.x, -1940, "a larger threshold attracts a farther viewport");
    const Rect narrowerSnap = snapViewportToNearFullscreenWindow(
        {-2100, -340, 1920, 1080}, {-1990, -300, 1920, 1080}, nearFullscreenWindow, 32);
    expectNear(narrowerSnap.x, -1990, "the default threshold leaves a farther viewport free");

    DisplayState snapDisplay({9, {0, 0, 1920, 1080}});
    expect(snapDisplay.camera().setPosition(-1975, -340), "snap test starts at a negative camera origin");
    expect(snapDisplay.panCamera({50, 40}), "camera accepts a gesture movement");
    expectNear(snapDisplay.camera().x(), -1925, "snap does not interrupt an active gesture");
    expect(snapDisplay.panCamera({3, 2}), "camera accepts a momentum movement");
    expectNear(snapDisplay.camera().x(), -1922, "snap waits for the momentum tail");
    const Rect snapWindow{-1900, -285, 1880, 1050};
    expect(snapDisplay.finishCameraPan(std::span<const Rect>(&snapWindow, 1), 32),
           "gesture end selects a nearby snap target");
    expectNear(snapDisplay.camera().x(), -1922, "snap animation does not jump at gesture end");
    snapDisplay.advanceZoom(0.18);
    expect(snapDisplay.camera().x() < -1922 && snapDisplay.camera().x() > -1940,
           "snap animation advances smoothly toward its target");
    snapDisplay.advanceZoom(0.18);
    expectNear(snapDisplay.camera().x(), -1940, "snap animation reaches its target");
    expectNear(snapDisplay.camera().y(), -285, "snap animation reaches the vertical target");
    expect(!snapDisplay.finishCameraPan(std::span<const Rect>(&snapWindow, 1), 32),
           "a completed pan cannot start another snap without new input");

    expect(snapDisplay.panCamera({-10, 0}), "new gesture can move away from a snap target");
    expect(!snapDisplay.finishCameraPan(std::span<const Rect>(&snapWindow, 1), 32),
           "moving away from a snap target does not pull the camera back");
    expectNear(snapDisplay.camera().x(), -1950, "moving away preserves the free position");

    expect(snapDisplay.panCamera({25, 0}), "new gesture can interrupt a previous snap");
    snapDisplay.cancelCameraPan();
    expectNear(snapDisplay.camera().x(), -1925, "cancelled gesture leaves the camera where it stopped");
    expect(!snapDisplay.finishCameraPan(std::span<const Rect>(&snapWindow, 1), 32),
           "cancelled gesture cannot trigger a delayed snap");

    expect(snapDisplay.panCamera({-5, 0}), "camera can pan back toward a snap point");
    expect(snapDisplay.finishCameraPan(std::span<const Rect>(&snapWindow, 1), 32),
           "a later gesture can select a new snap target");
    snapDisplay.advanceZoom(0.09);
    const float interruptedPosition = snapDisplay.camera().x();
    expect(snapDisplay.panCamera({-5, 0}), "new input interrupts an in-flight snap animation");
    expectNear(snapDisplay.camera().x(), interruptedPosition - 5,
               "new input continues from the current animated position");
    snapDisplay.cancelCameraPan();
    snapDisplay.advanceZoom(1.0);
    expectNear(snapDisplay.camera().x(), interruptedPosition - 5,
               "an interrupted snap cannot resume after the gesture ends");

    expect(snapDisplay.panCamera({-2, 0}), "camera can start a snap with animations disabled");
    expect(snapDisplay.finishCameraPan(std::span<const Rect>(&snapWindow, 1), 32),
           "camera selects a snap target when animations are disabled");
    snapDisplay.advanceZoom(1.0 / 60.0, 1.0f, false);
    expectNear(snapDisplay.camera().x(), -1940,
               "disabled animations settle the snap at its target");

    DisplayState tunedDisplay({10, {0, 0, 1920, 1080}});
    expect(tunedDisplay.camera().setPosition(-1975, -340), "tuned snap test sets its starting camera");
    expect(tunedDisplay.panCamera({50, 40}), "tuned snap test pans toward the window");
    expect(tunedDisplay.finishCameraPan(std::span<const Rect>(&snapWindow, 1), 32,
                                        SnapTuning::center, SnapTuning::trailing),
           "tuned snap starts an animation after the gesture");
    tunedDisplay.advanceZoom(0.36);
    expectNear(tunedDisplay.camera().x(), -1920, "tuned camera animation uses horizontal center");
    expectNear(tunedDisplay.camera().y(), -315, "tuned camera animation uses vertical bottom");

    const Rect viewport = display.viewport();
    VisibilityPolicy policy(100.0f);
    expect(policy.shouldRender({ -600.0f, 200.0f, 100.0f, 100.0f }, viewport, false),
           "window inside overscan buffer is rendered");
    expect(policy.shouldRender({ viewport.right() - 20.0f, viewport.y, 100.0f, 100.0f }, viewport, false),
           "window partially outside its viewport remains rendered at the edge");
    expect(!policy.shouldRender({ 1700.0f, 200.0f, 100.0f, 100.0f }, viewport, false),
           "window outside overscan buffer is not rendered");
    expect(policy.shouldRender({ 1700.0f, 200.0f, 100.0f, 100.0f }, viewport, true),
           "focused window bypasses visibility culling");

    const Rect beforeDrag{1700, 100, 640, 480};
    const Rect afterCrossing{2050, 100, 640, 480};
    expect(!shouldTransferWindow(false, true, beforeDrag, afterCrossing, 1, 2),
           "camera projection crossing another display does not transfer ownership");
    expect(!shouldTransferWindow(true, false, beforeDrag, afterCrossing, 1, 2),
           "camera movement during a mouse drag does not transfer ownership");
    expect(!shouldTransferWindow(true, true, beforeDrag, beforeDrag, 1, 2),
           "a mouse drag without window movement does not transfer ownership");
    expect(shouldTransferWindow(true, true, beforeDrag, afterCrossing, 1, 2),
           "a user drag across the display boundary transfers ownership");
    expect(!shouldReleaseToIgnoredDisplay(false, true, beforeDrag, afterCrossing, true),
           "camera projection onto an ignored display does not release a window");
    expect(!shouldReleaseToIgnoredDisplay(true, false, beforeDrag, afterCrossing, true),
           "a moving camera cannot release a dragged window to an ignored display");
    expect(!shouldReleaseToIgnoredDisplay(true, true, beforeDrag, beforeDrag, true),
           "a click without window movement does not release its canvas");
    expect(!shouldReleaseToIgnoredDisplay(true, true, beforeDrag, afterCrossing, false),
           "a managed destination keeps the managed transfer path");
    expect(shouldReleaseToIgnoredDisplay(true, true, beforeDrag, afterCrossing, true),
           "a user drag into an ignored display releases native ownership");
    DisplayState leftCanvas({1, {0, 0, 1920, 1080}});
    DisplayState rightCanvas({2, {1920, 0, 1920, 1080}});
    const Rect rightBefore = rightCanvas.virtualToPhysical({100, 100, 640, 480});
    leftCanvas.camera().move(300, 0);
    const Rect rightAfter = rightCanvas.virtualToPhysical({100, 100, 640, 480});
    expectNear(rightAfter.x, rightBefore.x,
               "moving one display camera leaves the other display presentation unchanged");
    expect(leftCanvas.virtualToPhysical({100, 100, 640, 480}).x != rightBefore.x,
           "each display maps its own virtual canvas to its physical origin");
    expect(frameFitsDisplay({1280, 100, 640, 480}, {0, 0, 1920, 1080}),
           "a window ending at its owner display edge can use native positioning");
    expect(!frameFitsDisplay({1281, 100, 640, 480}, {0, 0, 1920, 1080}),
           "a window entering the adjacent monitor cannot switch to native positioning");
    expect(!shouldPreferNativePosition({1281, 100, 640, 480}, {0, 0, 1920, 1080},
                                      {0, 0, 1920, 1040}),
           "unfocused windows use presentation transforms when native positioning is unsuitable");
    expect(!shouldPreferNativePosition({100, -15, 640, 480}, {0, -30, 1920, 1080},
                                      {0, 0, 1920, 1040}),
           "focused windows above the menu bar keep their presentation transform");
    expect(shouldPreferNativePosition({100, 100, 640, 480}, {0, -30, 1920, 1080},
                                     {0, 0, 1920, 1040}),
           "focused windows in usable bounds can use native positioning for input hit testing");
    expect(!shouldPreferNativePosition({-1900, -315, 640, 480}, {-1920, -330, 1920, 1080},
                                      {-1920, -300, 1920, 1040}),
           "focused windows on a negative-origin display also respect its menu bar");
    const DisplayGeometry adjacentDisplays[] = {{1, {0, 0, 1920, 1080}}, {2, {1920, 0, 1920, 1080}}};
    const Rect partlyDragged{1500, 100, 640, 480};
    expect(nearestDisplay(adjacentDisplays, {1950, 200}) == 2 &&
           nearestDisplay(adjacentDisplays, {partlyDragged.x + partlyDragged.w / 2, 200}) == 1,
           "drag-everywhere destination follows the released pointer even while the window center remains on its source display");
    const Point grabOffset{120, 30};
    const Point dragPointer{1980, 240};
    const Point draggedOrigin = leftCanvas.physicalToVirtual(
        Point{dragPointer.x - grabOffset.x, dragPointer.y - grabOffset.y});
    const Point projectedOrigin = leftCanvas.virtualToPhysical(draggedOrigin);
    expectNear(projectedOrigin.x + grabOffset.x, dragPointer.x,
               "absolute pointer drag keeps the grabbed point under the cursor across displays");
    const Point actualVisualOrigin{1450, 100};
    const Point pointerOnWindow{1490, 130};
    const Point actualGrabOffset{pointerOnWindow.x - actualVisualOrigin.x,
                                 pointerOnWindow.y - actualVisualOrigin.y};
    const Point unchangedDrag = leftCanvas.physicalToVirtual(
        Point{pointerOnWindow.x - actualGrabOffset.x, pointerOnWindow.y - actualGrabOffset.y});
    expectNear(leftCanvas.virtualToPhysical(unchangedDrag).x, actualVisualOrigin.x,
               "drag starts from the observed window frame without an initial cursor jump");

    DisplayState clippedDragDisplay({11, {0, 0, 1920, 1080}});
    clippedDragDisplay.camera().setPosition(500, 200);
    const Rect clippedModelFrame{450, 170, 640, 480};
    const Rect projectedClippedFrame = clippedDragDisplay.virtualToPhysical(clippedModelFrame);
    const Rect osClampedFrame{0, 0, 640, 480};
    const Point clippedPress{24, 16};
    expect(projectedClippedFrame.x < osClampedFrame.x,
           "clipped drag fixture projects the model frame beyond the physical display");
    const Point clampedOffset = dragPointerOffset(clippedPress, osClampedFrame);
    const Point clampedStartOrigin = draggedVirtualOrigin(clippedDragDisplay, clippedPress, clampedOffset);
    expect(clampedStartOrigin.x != clippedModelFrame.x,
           "using the OS-clamped frame as grab offset reproduces the clipped-drag position jump");
    const Point clippedOffset = dragPointerOffset(clippedPress, projectedClippedFrame);
    const Point clippedStartOrigin = draggedVirtualOrigin(clippedDragDisplay, clippedPress, clippedOffset);
    expectNear(clippedStartOrigin.x, clippedModelFrame.x,
               "clipped titlebar drag starts from the model x without snapping to the OS-clamped frame");
    expectNear(clippedStartOrigin.y, clippedModelFrame.y,
               "clipped titlebar drag starts from the model y without snapping to the OS-clamped frame");
    const Point clippedMovedOrigin = draggedVirtualOrigin(
        clippedDragDisplay, {clippedPress.x + 37, clippedPress.y + 19}, clippedOffset);
    expectNear(clippedMovedOrigin.x, clippedModelFrame.x + 37,
               "clipped titlebar drag follows pointer delta on x at a shifted camera");
    expectNear(clippedMovedOrigin.y, clippedModelFrame.y + 19,
               "clipped titlebar drag follows pointer delta on y at a shifted camera");

    display.saveBookmark(3);
    display.camera().setPosition(0.0f, 0.0f);
    expect(display.loadBookmark(3), "existing bookmark loads");
    expect(display.returning(), "bookmark starts a camera return animation");
    expectNear(display.camera().x(), 0.0f, "bookmark request leaves camera at its starting position");
    display.advanceZoom(0.18);
    expect(display.camera().x() != 0.0f && display.camera().x() != -500.0f,
           "bookmark camera moves during the return animation");
    display.advanceZoom(0.18);
    expectNear(display.camera().x(), -500.0f, "bookmark animation ends at saved camera x");
    expectNear(display.camera().y(), 200.0f, "bookmark animation ends at saved camera y");
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

    DisplayState returning({10, {-1920, -300, 1920, 1080}});
    returning.setScaleAt(0.25f, {-960, 240});
    const Point initialCamera = returning.camera().position();
    expect(returning.beginReturn(Point{400, -200}) && returning.returning(), "selection starts a native return animation");
    expectNear(returning.scale(), 0.25f, "return request never jumps to native scale immediately");
    expectNear(returning.camera().x(), initialCamera.x, "return request never jumps the camera immediately");
    returning.advanceZoom(0.18);
    expect(returning.scale() > 0.25f && returning.scale() < 1 && returning.overviewActive(), "return interpolates scale and holds overview input ownership");
    const auto halfway = returning;
    expect(!returning.requestZoom(-8, {-960, 240}), "wheel cannot interrupt a selected window return");
    returning.advanceZoom(0.18);
    expect(!returning.returning() && !returning.overviewActive() && returning.scale() == 1, "return finishes at exact native scale");
    expectNear(returning.camera().x(), 400, "return ends at the selected window camera x");
    expectNear(returning.camera().y(), -200, "return ends at the selected window camera y");
    auto frozen = halfway;
    const auto frozenCamera = frozen.camera().position();
    const auto frozenScale = frozen.scale();
    frozen.freezePresentation();
    frozen.advanceZoom(2);
    expect(frozen.scale() == frozenScale && frozen.camera().x() == frozenCamera.x &&
           frozen.camera().y() == frozenCamera.y && !frozen.returning(),
           "native DOWN freezes an in-flight return at its visible camera and scale");
    frozen.animateCameraTo({900, 800});
    frozen.freezePresentation();
    frozen.advanceZoom(2);
    expect(frozen.camera().x() == frozenCamera.x && frozen.camera().y() == frozenCamera.y,
           "native DOWN cancels camera animation without changing its current position");
    DisplayState atSixty = halfway, atOneTwenty = halfway;
    for (int i = 0; i < 6; ++i) atSixty.advanceZoom(1.0 / 60);
    for (int i = 0; i < 12; ++i) atOneTwenty.advanceZoom(1.0 / 120);
    expectNear(atSixty.scale(), atOneTwenty.scale(), "return animation is independent of frame rate");
    expectNear(atSixty.camera().x(), atOneTwenty.camera().x(), "return camera path is independent of frame rate");
    returning.setScaleAt(0.2f, {-960, 240});
    const Point returnCenter = returning.physicalToVirtual(Point{-960, 240});
    expect(!returning.beginReturn(Point{NAN, 0}) && !returning.returning(), "invalid return target is atomic");
    expect(returning.beginReturn(), "Escape starts an anchored return");
    returning.advanceZoom(0.1);
    expect(std::abs(returning.physicalToVirtual(Point{-960, 240}).x - returnCenter.x) < 0.001f,
           "Escape preserves the virtual display center while scaling within float precision");
    returning.resetZoom({-960, 240});
    expect(!returning.returning() && returning.scale() == 1, "failure recovery can still cancel return immediately");

    DisplayState mouseReturn({11, {-1920, -300, 1920, 1080}});
    mouseReturn.camera().setPosition(100, -200);
    const Point mouseAnchor{-1400, 80};
    mouseReturn.setScaleAt(0.3f, mouseAnchor);
    const Point mouseWorld = mouseReturn.physicalToVirtual(mouseAnchor);
    expect(mouseReturn.beginReturn({}, mouseAnchor), "mouse Escape return accepts a physical cursor anchor");
    mouseReturn.advanceZoom(0.18);
    const auto mouseMid = mouseReturn.physicalToVirtual(mouseAnchor);
    expect(std::abs(mouseMid.x - mouseWorld.x) < 0.001f && std::abs(mouseMid.y - mouseWorld.y) < 0.001f,
           "mouse Escape return keeps the virtual point under the cursor fixed during animation");
    mouseReturn.advanceZoom(0.18);
    expectNear(mouseReturn.camera().x(), mouseWorld.x - (mouseAnchor.x + 1920), "mouse Escape return ends at the anchored native camera");
    expect(!mouseReturn.beginReturn({}, Point{NAN, 0}), "invalid mouse return anchor is rejected atomically");

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
