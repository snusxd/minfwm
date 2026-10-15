#include "WindowRenderer.hpp"

#include <iostream>
#include <cmath>
#include <limits>
#include <string>
#include <vector>
#include <algorithm>

namespace {
using namespace minfwm;
int failures = 0;

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

class RecordingBackend final : public WindowBackend {
public:
    BackendCode moveCode = BackendCode::ok;
    BackendCode resizeCode = BackendCode::ok;
    BackendCode layerCode = BackendCode::unsupported;
    BackendCode hiddenCode = BackendCode::unsupported;
    bool failNextMove = false;
    bool transforms = false;
    bool transformed = false;
    BackendCode nativeCode = BackendCode::ok;
    BackendCode resetCode = BackendCode::ok;
    int x = 0, y = 0, layer = 0;
    float width = 0, height = 0;
    std::vector<std::string> calls;
    float scale = 1;
    BackendCode overviewCode = BackendCode::ok;
    bool supportsOverview() const override { return transforms; }
    BackendResult presentOverview(AXUIElementRef, uint32_t, int targetX, int targetY, float targetScale) override {
        calls.push_back("overview");
        x = targetX; y = targetY; scale = targetScale;
        transformed = true;
        return {overviewCode};
    }
    bool usesTransforms() const override { return transforms; }
    bool hasTransform(uint32_t) const override { return transformed; }
    BackendResult moveNative(AXUIElementRef, uint32_t, int targetX, int targetY) override {
        calls.push_back("native");
        x = targetX; y = targetY;
        if (nativeCode == BackendCode::ok) transformed = false;
        return {nativeCode};
    }
    BackendResult resetTransform(uint32_t) override {
        if (transforms) calls.push_back("reset");
        return {resetCode};
    }

    BackendResult move(AXUIElementRef, uint32_t, int targetX, int targetY) override {
        if (transforms) transformed = true;
        calls.push_back("move");
        x = targetX;
        y = targetY;
        if (failNextMove) {
            failNextMove = false;
            return {BackendCode::failed};
        }
        return {moveCode};
    }
    BackendResult resize(AXUIElementRef, uint32_t, float w, float h) override {
        calls.push_back("resize");
        width = w;
        height = h;
        return {resizeCode};
    }
    BackendResult setLayer(AXUIElementRef, uint32_t, int targetLayer) override {
        calls.push_back("layer");
        layer = targetLayer;
        return {layerCode};
    }
    BackendResult setHidden(AXUIElementRef, uint32_t, bool hidden) override {
        calls.push_back(hidden ? "hide" : "show");
        return {hiddenCode};
    }
};

void initializeWindow(ClientWindow& window) {
    window.originalPhysicalRect = core::Rect{-1700, -200, 640, 480};
    window.virtualRect = {220, 100, 640, 480};
    window.virtualCoordinatesInitialized = true;
}

void testReleaseToIgnoredDisplay() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.transformed = true;
    sa.layerCode = BackendCode::ok;
    ClientWindow window(nullptr, 83);
    initializeWindow(window);
    window.isLayerSet = true;
    window.layerAttempted = true;
    WindowRenderer renderer(ax, sa);
    expect(renderer.releaseToNative(window, {2200, 120, 640, 480}, 5).succeeded(),
           "releasing a transformed window to an ignored display succeeds");
    expect(sa.x == 2200 && sa.y == 120 && !sa.transformed && ax.calls.empty(),
           "native handoff keeps the destination frame and clears the transform");
    expect(sa.layer == kCGNormalWindowLevelKey && !window.isLayerSet,
           "native handoff restores the ordinary window layer");

    window.isHidden = true;
    window.isAXHidden = true;
    window.needsGeometryRestore = true;
    ax.hiddenCode = BackendCode::ok;
    ax.calls.clear();
    expect(renderer.releaseToNative(window, {2250, 180, 640, 480}, 6).succeeded(),
           "reloading an ignored display can release a parked window");
    expect(std::find(ax.calls.begin(), ax.calls.end(), "show") != ax.calls.end() &&
           std::find(ax.calls.begin(), ax.calls.end(), "resize") != ax.calls.end() &&
           !window.isHidden && !window.needsGeometryRestore,
           "parked window is shown at its original size before native release");
}

void testFallbackAndShutdown() {
    RecordingBackend ax, sa;
    sa.moveCode = BackendCode::failed;
    sa.layerCode = BackendCode::failed;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa, [](AXUIElementRef, uint32_t, int, int) { return true; });
    expect(renderer.render(window, {-1500, -100, 640, 480}, 1).succeeded(),
           "failed SA operation reaches successful AX movement");
    expect(ax.x == -1500 && ax.y == -100, "AX fallback preserves negative display coordinates");
    expect(ax.calls == std::vector<std::string>{"move", "layer"},
           "failed SA layer also reaches AX fallback");
    expect(!window.isLayerSet, "unsupported layer is never recorded as applied");
    const auto previousCalls = ax.calls;
    renderer.render(window, {-1500, -100, 640, 480}, 2);
    expect(ax.calls == previousCalls, "unchanged window does not repeat unsupported layer operations");

    sa.layerCode = BackendCode::ok;
    window.layerAttempted = false;
    renderer.render(window, {-1400, -100, 640, 480}, 3);
    expect(window.isLayerSet, "successful SA layer is tracked for restoration");
    window.virtualRect = {-10000, 10000, 100, 100};
    expect(renderer.restore(window, 4).succeeded(), "shutdown restores original geometry and normal layer");
    expect(ax.x == -1700 && ax.y == -200 && ax.width == 640 && ax.height == 480,
           "shutdown uses captured physical geometry independently of the camera");
    expect(sa.layer == kCGNormalWindowLevelKey && !window.isLayerSet, "shutdown resets an applied SA layer");
}

void testPartialHideAndRestore() {
    RecordingBackend ax, sa;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa, [](AXUIElementRef, uint32_t, int, int) { return true; });
    window.lastRenderedX = -1600;
    window.lastRenderedY = -150;
    ax.failNextMove = true;
    expect(!renderer.hide(window, {-9000, 100, 640, 480}, {-1920, -300, 1920, 1080}, 1).succeeded(),
           "failed parking reports failure");
    expect(ax.x == -1600 && ax.y == -150 && ax.width == 640 && ax.height == 480,
           "failed parking rolls back the successful shrink at the last visible position");
    expect(!window.isHidden, "successful rollback leaves window visible");

    ax.calls.clear();
    expect(renderer.hide(window, {-9000, 100, 640, 480}, {-1920, -300, 1920, 1080}, 2).succeeded(),
           "AX without hidden support can park the window");
    expect(window.isHidden && !window.isAXHidden && ax.x == -1 && ax.y == 779,
           "parking uses the owning display corner with a negative origin");
    expect(renderer.render(window, {-1500, -100, 640, 480}, 3).succeeded(),
           "parked window returns to its full size");
    expect(!window.isHidden && ax.width == 640 && ax.height == 480,
           "show completes only after geometry restoration");

    ax.hiddenCode = BackendCode::ok;
    renderer.hide(window, {-9000, 100, 640, 480}, {-1920, -300, 1920, 1080}, 4);
    expect(window.isAXHidden, "successful AX hide is tracked");
    ax.calls.clear();
    sa.failNextMove = true;
    ax.failNextMove = true;
    expect(!renderer.render(window, {-1500, -100, 640, 480}, 5).succeeded(),
           "partial show remains eligible for retry");
    expect(!window.isAXHidden && !window.isHidden && window.needsGeometryRestore,
           "successful unhide is recorded even when geometry restoration fails");
    expect(ax.calls == std::vector<std::string>{"show", "resize", "move"},
           "restoration attempts size even when movement fails");
    ax.calls.clear();
    expect(renderer.render(window, {-1500, -100, 640, 480}, 6).succeeded(),
           "next update recovers from a partial show");
    expect(ax.calls == std::vector<std::string>{"resize"},
           "retry does not repeat an already successful unhide");
}

void testWindowIsParkedOutsideAllDisplaysAfterLeavingItsCanvas() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    ClientWindow window(nullptr, 77);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);

    // The owner display ends at x=1920; a neighbouring monitor starts there.
    expect(renderer.hide(window, {1920, 100, 640, 480}, {0, 0, 1920, 1080}, 1,
                         core::Point{3840, 1200}).succeeded(),
           "a window fully beyond its canvas is parked with the display transform");
    expect(sa.calls == std::vector<std::string>{"move"} && sa.x == 3840 && sa.y == 1200,
           "fully departed windows are parked beyond the connected desktop union");
    expect(ax.calls.empty(), "transform parking avoids resizing or hiding the client window");
}

void testUnverifiedMoveIsRetried() {
    RecordingBackend ax, sa;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa, [](AXUIElementRef, uint32_t, int, int) { return true; });
    expect(renderer.render(window, {100, 100, 640, 480}, 1).succeeded(), "initial position is cached");
    sa.moveCode = BackendCode::failed;
    ax.moveCode = BackendCode::failed;
    expect(!renderer.render(window, {100, -200, 640, 480}, 2).succeeded(),
           "unverified SA and AX movements fail the render");
    expect(std::isnan(window.lastRenderedX) && std::isnan(window.lastRenderedY),
           "failed move invalidates the previous cache as well as the requested position");
    ax.moveCode = BackendCode::ok;
    ax.calls.clear();
    expect(renderer.render(window, {100, 100, 640, 480}, 3).succeeded(),
           "returning to the old target still moves a window after a clamped operation");
    expect(ax.calls == std::vector<std::string>{"move"}, "return reaches AX fallback instead of skipping movement");

    window.isHidden = true;
    window.needsGeometryRestore = true;
    sa.moveCode = BackendCode::ok;
    sa.calls.clear();
    ax.calls.clear();
    expect(renderer.render(window, {100, -200, 640, 480}, 4).succeeded(),
           "parked window can return above the menu bar through SA");
    expect(ax.calls == std::vector<std::string>{"resize"} && sa.calls == std::vector<std::string>{"move"},
           "restoration resizes before the final privileged move");
}

void testApplicationCorrectsPositionLater() {
    RecordingBackend ax, sa;
    bool matches = true;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    window.layerAttempted = true;
    WindowRenderer renderer(ax, sa, [&](AXUIElementRef, uint32_t, int, int) { return matches; });
    expect(renderer.render(window, {100, -120, 640, 480}, 1).succeeded(), "initial SA move is provisionally accepted");
    expect(window.positionNeedsVerification, "successful movement is checked again after application events");
    matches = false;
    expect(renderer.render(window, {100, -120, 640, 480}, 1.3).succeeded(), "late correction attempts AX fallback");
    expect(ax.calls == std::vector<std::string>{"move"}, "late correction reaches AX exactly once");
    expect(!renderer.render(window, {100, -120, 640, 480}, 1.6).succeeded(), "repeated application correction rejects target");
    expect(window.rejectedPosition.has_value() && !window.positionNeedsVerification,
           "rejected target cannot be mistaken for a settled position");
    const auto previousSA = sa.calls;
    renderer.render(window, {100, -120, 640, 480}, 2);
    expect(sa.calls == previousSA && ax.calls.size() == 1, "unchanged rejected target does not cause a movement loop");
    matches = true;
    expect(renderer.render(window, {100, 100, 640, 480}, 3).succeeded(), "a new camera target can return the window");
    renderer.render(window, {100, 100, 640, 480}, 3.3);
    expect(!window.rejectedPosition && !window.positionNeedsVerification, "settled return clears verification state");

    renderer.render(window, {100, -120, 640, 480}, 4);
    matches = false;
    ax.moveCode = BackendCode::failed;
    expect(!renderer.render(window, {100, -120, 640, 480}, 4.3).succeeded(), "failed AX fallback rejects late-clamped target");
}

void testLateCorrectionAboveMenuBarKeepsTransform() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    bool matches = true;
    ClientWindow window(nullptr, 43);
    initializeWindow(window);
    window.layerAttempted = true;
    WindowRenderer renderer(ax, sa, [&](AXUIElementRef, uint32_t, int, int) { return matches; });
    expect(renderer.render(window, {100, -120, 640, 480}, 1).succeeded(),
           "above-bar window is initially presented with a transform");
    matches = false;
    expect(renderer.render(window, {100, -120, 640, 480}, 1.3).succeeded(),
           "late correction retries the presentation transform once");
    expect(sa.calls == std::vector<std::string>{"move", "move"} && ax.calls.empty(),
           "late correction above the menu bar never resets the transform or moves through AX");
    expect(!renderer.render(window, {100, -120, 640, 480}, 1.6).succeeded(),
           "a second late correction rejects the target without a movement loop");
    expect(sa.calls == std::vector<std::string>{"move", "move"} && ax.calls.empty(),
           "rejected above-bar target remains transformed without AX flicker");
}

void testFailedTransformNeverFallsBackToAXOutsideNativeBounds() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.moveCode = BackendCode::failed;
    ClientWindow window(nullptr, 44);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);
    expect(!renderer.render(window, {100, -120, 640, 480}, 1).succeeded(),
           "a failed above-bar transform reports a failed presentation");
    expect(ax.calls.empty(), "failed above-bar transform does not ask AX to clamp the native frame");
    expect(std::isnan(window.lastRenderedX) && !window.rejectedPosition,
           "failed transformed target remains eligible for retry after backoff");
    sa.moveCode = BackendCode::ok;
    const auto callsBeforeBackoff = sa.calls;
    expect(!renderer.render(window, {100, -120, 640, 480}, 1.1).succeeded() &&
           sa.calls == callsBeforeBackoff,
           "transient SA failure is not retried during the short backoff");
    expect(renderer.render(window, {100, -120, 640, 480}, 1.3).succeeded() &&
           sa.calls.size() >= 2 && sa.calls[0] == "move" && sa.calls[1] == "move" &&
           std::find(ax.calls.begin(), ax.calls.end(), "move") == ax.calls.end(),
           "same target recovers after transient SA failure without AX clamping");
}

void testTransformLifecycle() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.layerCode = BackendCode::ok;
    ax.hiddenCode = BackendCode::ok;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa, [](AXUIElementRef, uint32_t, int, int) { return true; });
    expect(renderer.render(window, {100, -120, 640, 480}, 1).succeeded() && window.isLayerSet,
           "transform and layer are applied together");
    sa.calls.clear(); ax.calls.clear();
    expect(renderer.hide(window, {100, -120, 640, 480}, {0, 0, 1000, 800}, 2).succeeded(),
           "transformed window can be hidden");
    expect(sa.calls == std::vector<std::string>{"reset"} && ax.calls == std::vector<std::string>{"hide"},
           "transform resets before AX hiding");
    expect(!window.isLayerSet && !window.layerAttempted, "payload level restoration invalidates layer bookkeeping");
    sa.calls.clear(); ax.calls.clear();
    expect(renderer.render(window, {100, -120, 640, 480}, 3).succeeded(), "hidden transformed window reappears");
    expect(sa.calls == std::vector<std::string>{"reset", "move", "layer"} && window.isLayerSet,
           "reappearance reapplies the transform and restored layer");
    sa.resetCode = BackendCode::failed;
    ax.calls.clear();
    expect(!renderer.hide(window, {100, -120, 640, 480}, {0, 0, 1000, 800}, 4).succeeded() && ax.calls.empty(),
           "failed transform cleanup prevents AX parking under an unknown transform");
    expect(!renderer.restore(window, 5).succeeded(), "shutdown reports failed transform cleanup");
    expect(ax.width == 640 && ax.height == 480, "shutdown still attempts native geometry restoration");
}

void testInvalidGeometry() {
    RecordingBackend ax, sa;
    ClientWindow window(nullptr, 42);
    WindowRenderer renderer(ax, sa, [](AXUIElementRef, uint32_t, int, int) { return true; });
    expect(!renderer.restore(window, 1).succeeded(), "missing original geometry is not fabricated");
    initializeWindow(window);
    expect(!renderer.render(window, {std::numeric_limits<float>::max(), 0, 640, 480}, 2).succeeded(),
           "out-of-range coordinates are rejected before conversion to integers");
    expect(!renderer.render(window, {0, 0, std::numeric_limits<float>::quiet_NaN(), 480}, 3).succeeded(),
           "non-finite size is rejected");
    expect(ax.calls.empty() && sa.calls.empty(), "invalid geometry never reaches either backend");
}

void testRestoreFailures() {
    RecordingBackend ax, sa;
    sa.layerCode = BackendCode::failed;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa, [](AXUIElementRef, uint32_t, int, int) { return true; });
    window.isLayerSet = true;
    window.isAXHidden = true;
    window.isHidden = true;
    ax.failNextMove = true;
    expect(!renderer.restore(window, 1).succeeded(), "shutdown reports backend restoration failures");
    expect(ax.calls == std::vector<std::string>{"show", "move", "resize", "layer"},
           "shutdown attempts unhide, size and layer even after movement failure");
    expect(window.isAXHidden && window.isLayerSet && window.needsGeometryRestore,
           "failed restoration retains state for a retry");
    ax.hiddenCode = BackendCode::ok;
    sa.layerCode = BackendCode::ok;
    expect(renderer.restore(window, 2).succeeded(), "restoration can recover after backend availability returns");
    expect(!window.isHidden && !window.isAXHidden && !window.isLayerSet && !window.needsGeometryRestore,
           "successful restoration clears only the state it recovered");
}

void testRejectedMovementDoesNotLoop() {
    RecordingBackend ax, sa;
    ax.moveCode = sa.moveCode = BackendCode::failed;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);
    renderer.render(window, {100, -120, 640, 480}, 1);
    const auto axCalls = ax.calls;
    const auto saCalls = sa.calls;
    renderer.render(window, {100, -120, 640, 480}, 1.016);
    expect(ax.calls == axCalls && sa.calls == saCalls, "immediately rejected target is not resent every frame");
    renderer.render(window, {100, -121, 640, 480}, 1.032);
    expect(ax.calls == axCalls && sa.calls == saCalls, "moving camera does not bypass failed-operation backoff");
    ax.moveCode = BackendCode::ok;
    expect(renderer.render(window, {100, 100, 640, 480}, 2).succeeded(), "a later valid target recovers after failure");
}

void testPixelCacheAndOffscreenTranslation() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);
    renderer.render(window, {100.1f, -120.1f, 640, 480}, 1);
    const auto calls = sa.calls;
    renderer.render(window, {100.2f, -120.2f, 640, 480}, 1.016);
    expect(sa.calls == calls, "subpixel camera changes do not resend identical integer positions");
    ax.calls.clear(); sa.calls.clear();
    expect(renderer.hide(window, {-3000, -2000, 640, 480}, {0, 0, 1000, 800}, 2).succeeded(),
           "offscreen transformed window is culled without changing native size");
    expect(ax.calls.empty() && sa.calls == std::vector<std::string>{"move"},
           "offscreen translation does not reset, shrink, park or restore the native frame");
    expect(window.isHidden && !window.needsGeometryRestore && !window.isAXHidden,
           "translation-only culling retains native geometry");
    sa.calls.clear();
    renderer.render(window, {100, -120, 640, 480}, 3);
    expect(ax.calls.empty() && sa.calls == std::vector<std::string>{"move"},
           "returning translated window does not resize through AX");
}

void testFailedParkingDoesNotLoop() {
    RecordingBackend ax, sa;
    ax.moveCode = BackendCode::failed;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);
    renderer.hide(window, {-3000, 100, 640, 480}, {0, 0, 1000, 800}, 1);
    const auto calls = ax.calls;
    renderer.hide(window, {-3010, 100, 640, 480}, {0, 0, 1000, 800}, 1.016);
    expect(ax.calls == calls, "failed parking does not shrink and roll back again at 60 Hz");
}

void testNativeDropSurvivesNextPan() {
    RecordingBackend ax, sa;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    window.layerAttempted = true;
    window.positionNeedsVerification = true;
    window.positionFallbackAttempted = true;
    window.rejectedPosition = core::Point{100, 100};
    window.positionRetryTime = 100;
    window.lastProgrammaticMoveTime = 99;
    core::DisplayState state({1, {-1920, -300, 1920, 1080}});
    state.camera().setPosition(600, -200);
    WindowRenderer renderer(ax, sa);
    const core::Rect dropped{-1500, 120, 640, 480};
    expect(renderer.acceptNativeGeometry(window, dropped, state), "mouse release adopts final observed geometry");
    const auto expected = state.physicalToVirtual(dropped);
    expect(window.virtualRect.x == expected.x && window.virtualRect.y == expected.y,
           "drop uses the camera and negative display origin exactly once");
    expect(!window.positionNeedsVerification && !window.rejectedPosition && window.positionRetryTime == 0,
           "native drop overrides stale verification and rejected-move state");
    expect(renderer.render(window, state.virtualToPhysical(window.virtualRect), 1).succeeded() && sa.calls.empty() && ax.calls.empty(),
           "adopting a native drop does not send a move back to the old position");
    state.camera().move({100, -80});
    expect(renderer.render(window, state.virtualToPhysical(window.virtualRect), 2).succeeded() && sa.x == -1600 && sa.y == 200,
           "next pan starts from the final drop, not the first native movement event");
    state.camera().move({-100, 80});
    renderer.render(window, state.virtualToPhysical(window.virtualRect), 3);
    expect(sa.x == dropped.x && sa.y == dropped.y, "returning camera preserves the chosen drop position");
    const auto before = window.virtualRect;
    expect(!renderer.acceptNativeGeometry(window, {NAN, 0, 640, 480}, state) && window.virtualRect.x == before.x,
           "invalid native observation leaves canvas position intact");
}

void testApplicationNotificationCannotAdoptCameraTransform() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    ClientWindow window(nullptr, 78);
    initializeWindow(window);
    core::DisplayState state({1, {0, 0, 1920, 1080}});
    WindowRenderer renderer(ax, sa);
    const auto initial = window.virtualRect;
    const core::Rect staleVisualFrame{1200, 100, 700, 500};
    expect(renderer.acceptApplicationGeometry(window, staleVisualFrame, state, true),
           "application resize notification can still update window dimensions");
    expect(window.virtualRect.x == initial.x && window.virtualRect.y == initial.y,
           "AX notification while transformed cannot turn camera movement into a canvas move");
    expect(window.virtualRect.w == 700 && window.virtualRect.h == 500,
           "real application resize is preserved while the presentation is transformed");
    expect(!renderer.acceptApplicationGeometry(window, {1200, 100, NAN, 500}, state, true) &&
           window.virtualRect.w == 700,
           "invalid transformed resize cannot corrupt canvas geometry");
    state.camera().setPosition(50, -20);
    expect(renderer.acceptApplicationGeometry(window, {300, 200, 700, 500}, state, false),
           "untransformed application movement is accepted within its existing canvas");
    expect(window.virtualRect.x == 350 && window.virtualRect.y == 180,
           "untransformed application geometry uses the owner display camera");
}

void testVisibleFrameReturnsToNativeGeometry() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.layerCode = BackendCode::ok;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    window.layerAttempted = true;
    WindowRenderer renderer(ax, sa);
    renderer.render(window, {100, -120, 640, 480}, 1);
    expect(sa.transformed, "above-bar target uses translation");
    sa.calls.clear(); ax.calls.clear();
    window.preferNativePosition = true;
    renderer.render(window, {450, 200, 640, 480}, 2);
    expect(!sa.transformed && !sa.calls.empty() && sa.calls.front() == "native" && ax.calls.empty(),
           "returning visible window moves its native frame and clears translation before native input");
    sa.nativeCode = BackendCode::failed;
    sa.calls.clear();
    renderer.render(window, {500, 200, 640, 480}, 3);
    expect(sa.calls.size() >= 2 && sa.calls[0] == "native" && sa.calls[1] == "move",
           "failed native handoff retains transform fallback");
}

void testNativeHandoffAfterDragWithoutCoordinateChange() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    ClientWindow window(nullptr, 79);
    initializeWindow(window);
    window.layerAttempted = true;
    WindowRenderer renderer(ax, sa, [](AXUIElementRef, uint32_t, int, int) { return true; });
    expect(renderer.render(window, {300, 200, 640, 480}, 1).succeeded() && sa.transformed,
           "drag presentation initially uses a transform");
    sa.calls.clear();
    window.preferNativePosition = true;
    expect(renderer.render(window, {300, 200, 640, 480}, 2).succeeded(),
           "ending a drag can hand off to native geometry at the same position");
    expect(!sa.calls.empty() && sa.calls.front() == "native" && !sa.transformed,
           "same-coordinate handoff restores native hover hit testing");

    window.preferNativePosition = false;
    renderer.render(window, {300, 200, 640, 480}, 3);
    sa.nativeCode = BackendCode::failed;
    window.preferNativePosition = true;
    sa.calls.clear();
    renderer.render(window, {300, 200, 640, 480}, 4);
    const auto failedHandoffCalls = sa.calls;
    renderer.render(window, {300, 200, 640, 480}, 4.1);
    expect(sa.calls == failedHandoffCalls,
           "failed same-coordinate native handoff is not retried every frame");
}
}

void testOverviewPresentationAndReturn() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.layerCode = BackendCode::ok;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);
    expect(renderer.renderOverview(window, {200, 100, 320, 240}, 0.5f, 1).succeeded(), "overview applies presentation scale");
    expect(sa.x == 200 && sa.y == 100 && sa.scale == 0.5f && ax.calls.empty(), "overview does not resize or move the native frame through AX");
    const auto before = sa.calls;
    renderer.renderOverview(window, {200, 100, 320, 240}, 0.5f, 2);
    expect(sa.calls == before, "unchanged overview does not send redundant packets");
    window.preferNativePosition = true;
    expect(renderer.render(window, {200, 100, 640, 480}, 3).succeeded() && std::find(sa.calls.begin(), sa.calls.end(), "native") != sa.calls.end(),
           "return at identical origin still hands scaled geometry back to native movement");
    sa.overviewCode = BackendCode::failed;
    ax.calls.clear();
    expect(!renderer.renderOverview(window, {220, 100, 320, 240}, 0.5f, 4).succeeded() && ax.calls.empty(),
           "failed overview leaves normal scale recovery to caller instead of AX shrinking applications");
}

void testExternalApplicationSuspension() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.layerCode = BackendCode::ok;
    ClientWindow window(nullptr, 42);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);
    renderer.renderOverview(window, {200, 100, 320, 240}, 0.5f, 1);
    expect(renderer.suspend(window, 2).succeeded() && !window.overviewPresented,
           "hiding an application clears its owned presentation before suspension");
    expect(ax.calls.empty(), "suspension never moves, resizes or unhides a user-hidden application");
    const auto original = window.virtualRect;
    window.preferNativePosition = true;
    expect(renderer.render(window, {200, 100, 640, 480}, 3).succeeded() &&
           window.virtualRect.x == original.x && window.virtualRect.w == original.w,
           "unhidden application resumes from unchanged virtual geometry");
}

void testPreviewParkingAndRecovery() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.layerCode = BackendCode::ok;
    ClientWindow window(nullptr, 92);
    initializeWindow(window);
    WindowRenderer renderer(ax, sa);
    const auto original = window.virtualRect;
    expect(renderer.renderOverview(window, {200, 100, 256, 192}, 0.4f, 1).succeeded(),
           "live overview is initially presented");
    sa.calls.clear();
    expect(renderer.parkForPreview(window, {4000, 3000}, 2).succeeded() && window.isHidden &&
           !window.overviewPresented && sa.x == 4000 && sa.y == 3000,
           "preview originals park beyond the complete desktop even when their model frame is visible");
    expect(ax.calls.empty() && window.virtualRect.x == original.x && window.virtualRect.w == original.w,
           "parking neither resizes the app nor changes its model geometry");
    const auto operations = sa.calls.size();
    expect(renderer.parkForPreview(window, {4000, 3000}, 2.1).succeeded() && sa.calls.size() == operations,
           "cached preview parking sends no per-frame backend operations");
    expect(renderer.renderOverview(window, {220, 120, 384, 288}, 0.6f, 3).succeeded() &&
           !window.isHidden && window.overviewPresented && sa.scale == 0.6f,
           "crossing the exit threshold restores live overview from the unchanged model");
    sa.failNextMove = true;
    expect(!renderer.parkForPreview(window, {4000, 3000}, 4).succeeded() && !window.isHidden,
           "failed parking cannot publish a thumbnail-only window");
    sa.calls.clear();
    expect(renderer.renderOverview(window, {220, 120, 384, 288}, 0.6f, 4.01).succeeded() &&
           std::find(sa.calls.begin(), sa.calls.end(), "overview") != sa.calls.end(),
           "a failed parking request invalidates the live transform cache for recovery");
    sa.calls.clear();
    expect(!renderer.parkForPreview(window, {4000, 3000}, 4.1).succeeded() && sa.calls.empty(),
           "failed parking retries are bounded instead of blocking every animation frame");
    expect(renderer.parkForPreview(window, {4000, 3000}, 5).succeeded(), "parking can retry after backoff");
    expect(renderer.restore(window, 6).succeeded() && !window.isHidden && !window.overviewPresented,
           "shutdown restores parked originals");
    sa.transforms = false;
    sa.calls.clear();
    ax.calls.clear();
    expect(!renderer.parkForPreview(window, {4000, 3000}, 7).succeeded() && ax.calls.empty(),
           "preview parking requires transforms and never hides applications through AX");
}

void testManyPreviewFramesDoNotMoveOriginals() {
    RecordingBackend ax, sa;
    sa.transforms = true;
    sa.layerCode = BackendCode::ok;
    WindowRenderer renderer(ax, sa);
    std::vector<std::unique_ptr<ClientWindow>> windows;
    for (uint32_t id = 100; id < 200; ++id) {
        auto window = std::make_unique<ClientWindow>(nullptr, id);
        initializeWindow(*window);
        windows.push_back(std::move(window));
    }
    for (int frame = 0; frame < 60; ++frame) {
        for (const auto& window : windows) {
            expect(renderer.renderOverview(*window, {float(frame), 100, 256, 192}, .4f, frame).succeeded(),
                   "live comparison presentation succeeds");
        }
    }
    const auto liveUpdates = std::count(sa.calls.begin(), sa.calls.end(), "overview");
    sa.calls.clear();
    for (int frame = 60; frame < 120; ++frame) {
        for (const auto& window : windows) {
            expect(renderer.parkForPreview(*window, {4000, 3000}, frame).succeeded(),
                   "cached preview source remains parked through navigation frames");
        }
    }
    const auto parkedUpdates = std::count(sa.calls.begin(), sa.calls.end(), "move");
    expect(liveUpdates == 6000 && parkedUpdates == 100 && ax.calls.empty(),
           "100 windows across 60 frames require only 100 one-time parking moves instead of 6000 live updates");
}

int main() {
    testManyPreviewFramesDoNotMoveOriginals();
    testPreviewParkingAndRecovery();
    testReleaseToIgnoredDisplay();
    testOverviewPresentationAndReturn();
    testExternalApplicationSuspension();
    testFallbackAndShutdown();
    testPartialHideAndRestore();
    testWindowIsParkedOutsideAllDisplaysAfterLeavingItsCanvas();
    testInvalidGeometry();
    testRestoreFailures();
    testUnverifiedMoveIsRetried();
    testApplicationCorrectsPositionLater();
    testLateCorrectionAboveMenuBarKeepsTransform();
    testFailedTransformNeverFallsBackToAXOutsideNativeBounds();
    testTransformLifecycle();
    testRejectedMovementDoesNotLoop();
    testPixelCacheAndOffscreenTranslation();
    testFailedParkingDoesNotLoop();
    testNativeDropSurvivesNextPan();
    testApplicationNotificationCannotAdoptCameraTransform();
    testVisibleFrameReturnsToNativeGeometry();
    testNativeHandoffAfterDragWithoutCoordinateChange();
    return failures == 0 ? 0 : 1;
}
