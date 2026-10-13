#include "WindowRenderer.hpp"

#include <iostream>
#include <cmath>
#include <limits>
#include <string>
#include <vector>

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
    BackendCode resetCode = BackendCode::ok;
    int x = 0, y = 0, layer = 0;
    float width = 0, height = 0;
    std::vector<std::string> calls;
    bool usesTransforms() const override { return transforms; }
    BackendResult resetTransform(uint32_t) override {
        if (transforms) calls.push_back("reset");
        return {resetCode};
    }

    BackendResult move(AXUIElementRef, uint32_t, int targetX, int targetY) override {
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
}

int main() {
    testFallbackAndShutdown();
    testPartialHideAndRestore();
    testInvalidGeometry();
    testRestoreFailures();
    testUnverifiedMoveIsRetried();
    testApplicationCorrectsPositionLater();
    testTransformLifecycle();
    testRejectedMovementDoesNotLoop();
    testPixelCacheAndOffscreenTranslation();
    testFailedParkingDoesNotLoop();
    return failures == 0 ? 0 : 1;
}
