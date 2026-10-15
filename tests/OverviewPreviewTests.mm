#import <Foundation/Foundation.h>
#include "OverviewPreview.hpp"
#include "OverviewPreviewPolicy.hpp"
#include "WindowPool.hpp"
#include <iostream>
#include <limits>
#include <utility>
#include <thread>
#include <unordered_map>
#include <sstream>

namespace {
int failures = 0;
void expect(bool value, const char* message) {
    if (!value) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}
using namespace minfwm;
class Capture final : public OverviewPreview::CaptureProvider {
public:
    bool permission = true;
    bool grantOnRequest = false;
    size_t permissionRequests = 0;
    size_t requests = 0;
    std::vector<Completion> pending;
    bool permitted() const override { return permission; }
    bool requestPermission() override {
        ++permissionRequests;
        if (grantOnRequest) permission = true;
        return permission;
    }
    void capture(uint32_t, pid_t, size_t edge, Completion completion) override {
        expect(edge == 512, "capture is bounded at source");
        ++requests;
        pending.push_back(std::move(completion));
    }
    void complete(OverviewPreview::ImagePtr result) {
        auto completion = std::move(pending.front());
        pending.erase(pending.begin());
        completion(std::move(result));
    }
};
class Presenter final : public OverviewPreview::Presenter {
public:
    bool usable = true;
    size_t shown = 0;
    size_t closed = 0;
    size_t finished = 0;
    std::unordered_map<uint32_t, double> ranks;
    bool begin(int64_t, core::Rect) override { return usable; }
    void show(int64_t, uint32_t wid, const OverviewPreview::ImagePtr&, core::Rect, double rank) override {
        ++shown;
        ranks[wid] = rank;
    }
    void finish(int64_t) override { ++finished; }
    void end(int64_t) override { ++closed; }
    void reset() override { ++closed; }
    bool ownsCanvasWindow(uint32_t wid) const override { return wid == 999; }
};
std::shared_ptr<ClientWindow> window(uint32_t wid) {
    return std::make_shared<ClientWindow>(nullptr, wid);
}
OverviewPreview::ImagePtr image(size_t width = 16, size_t height = 16) {
    auto color = CGColorSpaceCreateDeviceRGB();
    auto context = CGBitmapContextCreate(nullptr, width, height, 8, width * 4, color,
                                        kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);
    if (!context) return {};
    auto result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    auto owned = std::make_shared<OverviewPreview::Image>(result);
    CGImageRelease(result);
    return owned;
}
class CapturedLogs {
    std::ostringstream m_output;
    std::streambuf* m_previous;
public:
    CapturedLogs() : m_previous(std::cout.rdbuf(m_output.rdbuf())) {}
    ~CapturedLogs() { std::cout.rdbuf(m_previous); }
    size_t occurrences(const std::string& text) const {
        const auto output = m_output.str();
        size_t count = 0, position = 0;
        while ((position = output.find(text, position)) != std::string::npos) {
            ++count;
            position += text.size();
        }
        return count;
    }
};
void diagnosticLogTests() {
    CapturedLogs logs;
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    OverviewPreview previews(capture, presenter);
    const core::Rect bounds{0, 0, 100, 100};
    auto first = window(1);
    for (int frame = 0; frame < 10; ++frame) {
        previews.beginDisplay(1, bounds, 1, true, true, frame / 100.0, {});
    }
    expect(logs.occurrences("screen-recording=granted") == 1 &&
           logs.occurrences("mode=live reason=zoom") == 1,
           "permission and live status are logged only on change");
    previews.beginDisplay(1, bounds, .2f, true, true, 1, {1});
    previews.ready(first, 1);
    previews.finishDisplay(1);
    capture->complete(image());
    expect(logs.occurrences("first-snapshot-ready") == 1 && logs.occurrences("first-preview-shown") == 0,
           "capture success does not claim the original has already been replaced");
    previews.beginDisplay(1, bounds, .2f, true, true, 1.001, {1});
    previews.show(1, first, {0, 0, 100, 100});
    previews.finishDisplay(1);
    for (int frame = 1; frame <= 60; ++frame) {
        previews.beginDisplay(1, bounds, .2f, true, true, 1 + frame / 120.0, {1});
        previews.show(1, first, {0, 0, 100, 100});
        previews.finishDisplay(1);
    }
    expect(logs.occurrences("mode=previews") == 1 && logs.occurrences("display=1 shown=") == 1 &&
           logs.occurrences("first-preview-shown display=1 WID=1") == 1,
           "first actual preview is reported immediately while frame summaries remain rate limited");
    previews.beginDisplay(1, bounds, .6f, true, true, 2, {1});
    expect(logs.occurrences("preview-session-ended") == 1 && logs.occurrences("cache-released") == 1,
           "returning to live logs session completion and snapshot release");
    capture->permission = false;
    for (int frame = 0; frame < 10; ++frame) {
        previews.beginDisplay(1, bounds, .2f, true, true, 3 + frame / 100.0, {});
    }
    expect(logs.occurrences("screen-recording=missing") == 1 &&
           logs.occurrences("mode=live reason=permission-missing") == 1,
           "revoked permission reports live fallback once without per-frame spam");

    auto failing = std::make_shared<Capture>();
    OverviewPreview failures(failing, presenter);
    failures.beginDisplay(2, bounds, .2f, true, true, 0, {1});
    for (int attempt = 0; attempt < 4; ++attempt) {
        failures.ready(first, attempt * 1.1);
        failing->complete({});
    }
    expect(failures.stats().captureFailures == 4 && logs.occurrences("capture-failed") == 1,
           "repeated capture failures keep counters accurate but limit error logs to once per five seconds");
}
void policyTests() {
    using core::overviewPreviewActive;
    expect(overviewPreviewActive(false, .45f, true, true, true), "enter threshold is inclusive");
    expect(!overviewPreviewActive(false, .46f, true, true, true), "entry preserves live mode in hysteresis band");
    expect(overviewPreviewActive(true, .54f, true, true, true), "active session remains in hysteresis band");
    expect(!overviewPreviewActive(true, .55f, true, true, true), "leave threshold is inclusive");
    expect(!overviewPreviewActive(true, .2f, false, true, true), "disabled configuration exits");
    expect(overviewPreviewActive(true, .2f, true, false, true), "disabled focus rewind preserves preview mode");
    expect(overviewPreviewActive(false, .45f, true, false, true), "previews enter at the same threshold without focus rewind");
    expect(!overviewPreviewActive(true, .2f, true, true, false), "permission absent exits");
    expect(!overviewPreviewActive(true, std::numeric_limits<float>::quiet_NaN(), true, true, true), "NaN exits");
    expect(!overviewPreviewActive(true, -1.f, true, true, true), "negative zoom exits");
    expect(!overviewPreviewActive(true, 1.f, true, true, true), "native scale exits");
    expect(core::overviewPreviewEligible({}), "ordinary window is eligible");
    for (int field = 0; field < 5; ++field) {
        core::OverviewPreviewInteraction interaction;
        if (field == 0) interaction.focused = true;
        if (field == 1) interaction.whitelisted = true;
        if (field == 2) interaction.pinned = true;
        if (field == 3) interaction.dragged = true;
        if (field == 4) interaction.auxiliary = true;
        expect(!core::overviewPreviewEligible(interaction), "direct interaction is excluded");
    }
}
void permissionRequestTests() {
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    OverviewPreview previews(capture, presenter);
    capture->permission = false;
    const core::Rect bounds{0, 0, 100, 100};
    expect(!previews.beginDisplay(1, bounds, 1, false, true, 0, {}) &&
           capture->permissionRequests == 0, "disabled previews never request screen recording");
    expect(!previews.beginDisplay(1, bounds, std::numeric_limits<float>::quiet_NaN(), true, true, 0, {}) &&
           capture->permissionRequests == 0, "invalid display input cannot trigger a permission prompt");
    expect(!previews.beginDisplay(1, bounds, 1, true, false, 0, {}) &&
           capture->permissionRequests == 1, "non-rewinding overview also requests missing capture permission");
    expect(!previews.beginDisplay(1, bounds, 1, true, true, 0, {}) &&
           capture->permissionRequests == 1, "startup at native scale requests missing access once");
    for (int frame = 1; frame <= 4; ++frame) {
        expect(!previews.beginDisplay(frame, bounds, .2f, true, true, frame, {}),
               "denied access keeps every display in live mode");
        previews.reset();
    }
    expect(capture->permissionRequests == 1 && capture->requests == 0 && presenter->shown == 0,
           "frames, multiple displays and session resets do not repeat a denied prompt or capture");
    capture->permission = true;
    expect(previews.beginDisplay(1, bounds, .2f, true, false, 5, {}) && capture->permissionRequests == 1,
           "access granted in Settings is detected without another permission request");

    auto granted = std::make_shared<Capture>();
    OverviewPreview alreadyGranted(granted, presenter);
    expect(alreadyGranted.beginDisplay(2, bounds, .2f, true, true, 6, {}) &&
           granted->permissionRequests == 0, "previously authorized startup never prompts");

    auto immediate = std::make_shared<Capture>();
    immediate->permission = false;
    immediate->grantOnRequest = true;
    OverviewPreview grantedByPrompt(immediate, presenter);
    expect(grantedByPrompt.beginDisplay(3, bounds, .2f, true, true, 7, {}) &&
           immediate->permissionRequests == 1, "a successful permission request enables preview mode immediately");
}

void adapterTests() {
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    OverviewPreview previews(capture, presenter);
    auto first = window(1), second = window(2);
    const core::Rect bounds{-1000, -200, 1000, 800};
    auto begin = [&](double now, float scale = .3f) {
        return previews.beginDisplay(7, bounds, scale, true, true, now, {2, 1});
    };
    expect(begin(0), "canvas is usable before caller parks windows");
    expect(previews.ownsCanvasWindow(999) && !previews.ownsCanvasWindow(998), "canvas ID seam preserves native stack hit testing");
    expect(!previews.ready(first, 0), "capture pending remains live");
    expect(!previews.ready(second, 0), "one global in-flight capture");
    expect(capture->requests == 1, "second capture is not launched concurrently");
    capture->complete(image());
    expect(previews.ready(first, .01), "completed snapshot becomes ready");
    first->isHidden = true;
    first->isAXHidden = true;
    first->needsGeometryRestore = true;
    expect(previews.ready(first, .01), "parked source with cached snapshot remains ready");
    first->isHidden = first->isAXHidden = first->needsGeometryRestore = false;
    expect(!previews.ready(second, .01) && capture->requests == 1, "launch interval is bounded");
    previews.show(7, first, {-950, -150, 300, 300});
    expect(previews.hitTest({-900, -100}) == first, "negative global origins hit correctly");
    expect(!previews.hitTest({-1001, -100}), "hit test clips to display");
    expect(!previews.ready(second, .051) && capture->requests == 2, "later capture can launch");
    capture->complete(image());
    previews.show(7, second, {-950, -150, 300, 300});
    expect(previews.hitTest({-900, -100}) == second, "front-to-back ordering controls hit test");
    second->applicationSuspended = true;
    expect(previews.hitTest({-900, -100}) == first, "suspended window is excluded from hit test");
    expect(!previews.ready(second, .06), "suspended window cannot capture");
    second->applicationSuspended = false;
    expect(!previews.hitTest({0, -100}), "display right edge is excluded");
    expect(previews.stats().imageCount == 2 && presenter->shown == 2, "cache and presentation are tracked");
    expect(begin(.1), "repeated frame begins");
    expect(!previews.hitTest({-900, -100}), "begin clears stale draw items");
    previews.finishDisplay(7);
    expect(previews.ready(first, .1) && capture->requests == 2, "snapshot remains frozen during session");
    first->pinned = true;
    expect(!previews.ready(first, .1), "pinned window stays live even with image");
    first->pinned = false;
    first->isAuxiliaryWindow = true;
    expect(!previews.ready(first, .1), "auxiliary window stays live");
    first->isAuxiliaryWindow = false;
    auto replacement = window(1);
    expect(!previews.ready(replacement, .11), "reused WID never receives prior identity image");
    first.reset();
    capture->complete(image());
    expect(previews.ready(replacement, .12), "replacement receives only its own capture");
    previews.endDisplay(7);
    expect(previews.stats().imageCount == 0, "all displays leaving releases snapshots");
    expect(begin(.2), "new session begins");
    auto third = window(3);
    expect(!previews.ready(third, .2), "new capture starts");
    previews.reset();
    expect(begin(.21), "reset allows new session");
    expect(!previews.ready(second, .3) && capture->requests == 4, "reset does not overlap outstanding capture");
    capture->complete(image());
    expect(previews.stats().imageCount == 0, "completion from old generation is ignored");
    expect(!previews.ready(second, .31) && capture->requests == 5, "new session resumes after old completion");
    capture->complete({});
    expect(previews.stats().captureFailures == 1, "failed capture recorded");
    expect(!previews.ready(second, .4) && capture->requests == 5, "failure backs off");
    auto otherFailureCandidate = window(77);
    expect(!previews.ready(otherFailureCandidate, .5) && capture->requests == 5,
           "capture failure globally backs off discovery for other windows");
    expect(!previews.ready(second, 1.4) && capture->requests == 6, "retry after failure backoff");
    second.reset();
    capture->complete(image());
    expect(previews.stats().imageCount == 0, "expired weak window discards completion");
    capture->permission = false;
    expect(!begin(2), "revoked capture permission exits without prompt");
    presenter->usable = false;
    capture->permission = true;
    expect(!begin(3), "unavailable canvas prevents parking");
}
void asyncAndDisplaysTests() {
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    OverviewPreview previews(capture, presenter);
    auto first = window(1), second = window(2);
    previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, 0, {1});
    previews.beginDisplay(2, {-100, 0, 100, 100}, .2f, true, true, 0, {2});
    previews.ready(first, 0);
    previews.endDisplay(2);
    auto thumbnail = image();
    std::thread background([capture, thumbnail] { capture->complete(thumbnail); });
    background.join();
    expect(previews.stats().imageCount == 0, "background callback does not mutate main-thread state");
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .05, false);
    expect(previews.stats().imageCount == 1 && previews.ready(first, .1),
           "secondary display exit preserves main display in-flight capture");
    previews.beginDisplay(2, {-100, 0, 100, 100}, .2f, true, true, .2, {2});
    previews.ready(second, .2);
    for (int i = 0; i < 10; ++i) {
        previews.reset();
        previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, .3 + i, {1});
        previews.ready(first, .3 + i);
    }
    expect(capture->requests == 2, "rapid reset and re-entry preserves global outstanding capture gate");
    capture->complete(image());
    expect(previews.stats().imageCount == 0, "rapid reset rejects old session callback");
    previews.ready(first, 11);
    capture->complete(image(513, 1));
    expect(previews.stats().imageCount == 0, "provider output above maximum edge is rejected");
}
void reusedIdentityTests() {
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    OverviewPreview previews(capture, presenter);
    auto original = window(1), replacement = window(1);
    previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, 0, {1});
    previews.ready(original, 0);
    expect(!previews.ready(replacement, .1), "reused ID cannot bypass pending global capture");
    capture->complete(image());
    expect(previews.stats().imageCount == 0, "old identity completion ignored even while old model survives");
    previews.ready(replacement, .2);
    capture->complete(image());
    previews.show(1, replacement, {0, 0, 100, 100});
    const auto bytes = previews.stats().imageBytes;
    expect(!previews.ready(original, .3), "displayed replacement cannot be evicted on ID reuse");
    expect(previews.stats().imageBytes == bytes, "displayed image stays included in memory budget");
    replacement.reset();
    expect(!previews.hitTest({50, 50}), "expired displayed identity cannot be hit");
    previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, .4, {1});
    expect(!previews.ready(original, .4), "previous-frame layer remains budgeted until finish");
    expect(previews.stats().imageBytes == bytes, "begin does not undercount native retained contents");
    previews.finishDisplay(1);
    expect(!previews.ready(original, .5) && capture->requests == 3,
           "after finish retires old layer the reused ID can capture");
    capture->complete(image());
    expect(previews.ready(original, .6), "new identity becomes ready after old layer retires");
}
void hiddenSourceTests() {
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    OverviewPreview previews(capture, presenter);
    auto source = window(1);
    previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, 0, {});
    source->isHidden = true;
    expect(!previews.ready(source, 0) && capture->requests == 0, "culled source waits for live restoration");
    source->isHidden = false;
    source->isAXHidden = true;
    expect(!previews.ready(source, .1) && capture->requests == 0, "AX-hidden source waits for restoration");
    source->isAXHidden = false;
    source->needsGeometryRestore = true;
    expect(!previews.ready(source, .2) && capture->requests == 0, "shrunken source waits for geometry restoration");
    source->needsGeometryRestore = false;
    expect(!previews.ready(source, .3) && capture->requests == 1, "restored source schedules capture next frame");
    capture->complete(image());
    expect(previews.ready(source, .4), "restored source preview becomes ready");
}
void frameAndOrderingTests() {
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    OverviewPreview previews(capture, presenter);
    auto first = window(10), second = window(20);
    previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, 0, {});
    previews.ready(first, 0);
    capture->complete(image());
    previews.ready(second, .1);
    capture->complete(image());
    previews.show(1, first, {0, 0, 100, 100});
    previews.show(1, second, {0, 0, 100, 100});
    expect(presenter->ranks.at(10) != presenter->ranks.at(20), "new windows have distinct ranks");
    expect(previews.hitTest({50, 50}) == first, "unknown window append order matches layer ordering");
    previews.finishDisplay(1);
    expect(previews.stats().imageCount == 2 && presenter->finished == 1,
           "finish commits frame without deactivating display");
    const auto firstRank = presenter->ranks.at(10), secondRank = presenter->ranks.at(20);
    previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, .2, {});
    previews.show(1, second, {0, 0, 100, 100});
    previews.show(1, first, {0, 0, 100, 100});
    expect(presenter->ranks.at(10) == firstRank && presenter->ranks.at(20) == secondRank,
           "new window ranks remain stable across reversed draw order");
    previews.finishDisplay(1);
    expect(previews.hitTest({50, 50}) == first, "committed hit test remains stable");
}
void lifetimeAndBudgetTests() {
    auto capture = std::make_shared<Capture>();
    auto presenter = std::make_shared<Presenter>();
    auto first = window(1);
    {
        OverviewPreview previews(capture, presenter);
        previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, 0, {});
        previews.ready(first, 0);
    }
    capture->complete(image());
    expect(true, "completion survives adapter destruction");
    OverviewPreview previews(capture, presenter, 1024);
    previews.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, 1, {1, 2});
    previews.ready(first, 1);
    capture->complete(image());
    expect(previews.ready(first, 1.1), "exact budget image accepted");
    previews.show(1, first, {0, 0, 100, 100});
    auto second = window(2);
    expect(!previews.ready(second, 1.1), "exhausted budget keeps next window live");
    expect(previews.stats().imageBytes == 1024 && previews.stats().imageCount == 1,
           "budget retains displayed image without eviction");
    previews.beginDisplay(2, {100, 0, 100, 100}, .2f, true, true, 1.2, {});
    previews.endDisplay(1);
    expect(previews.stats().imageCount == 1, "remaining active display retains session cache");
    previews.endDisplay(2);
    expect(previews.stats().imageCount == 0, "last active display frees cache");
    OverviewPreview small(capture, presenter, 512);
    small.beginDisplay(1, {0, 0, 100, 100}, .2f, true, true, 2, {});
    small.ready(first, 2);
    capture->complete(image());
    expect(small.stats().imageCount == 0, "oversized image rejected at completion");
}
}
int main() {
    @autoreleasepool {
        policyTests();
        permissionRequestTests();
        diagnosticLogTests();
        adapterTests();
        asyncAndDisplaysTests();
        reusedIdentityTests();
        frameAndOrderingTests();
        hiddenSourceTests();
        lifetimeAndBudgetTests();
    }
    if (!failures) std::cout << "overview preview tests passed\n";
    return failures ? 1 : 0;
}
