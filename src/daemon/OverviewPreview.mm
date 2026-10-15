#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#include "OverviewPreview.hpp"
#include "OverviewPreviewPolicy.hpp"
#include "WindowPool.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <iostream>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>

@interface MinfwmOverviewPanel : NSPanel
@end
@implementation MinfwmOverviewPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

namespace minfwm {
namespace {
constexpr size_t maxEdge = 512;
constexpr double launchInterval = .05;
constexpr double failureBackoff = 1.0;

void onMain(std::function<void()> completion) {
    if ([NSThread isMainThread]) completion();
    else dispatch_async(dispatch_get_main_queue(), ^{ completion(); });
}
bool validRect(core::Rect rect) {
    return std::isfinite(rect.x) && std::isfinite(rect.y) && std::isfinite(rect.w) &&
           std::isfinite(rect.h) && rect.w > 0 && rect.h > 0 &&
           std::isfinite(rect.right()) && std::isfinite(rect.bottom());
}
bool contains(core::Rect rect, core::Point point) {
    return point.x >= rect.left() && point.x < rect.right() &&
           point.y >= rect.top() && point.y < rect.bottom();
}

CGRect previewLayerFrame(core::Rect physical, core::Rect displayBounds) {
    // Window/camera coordinates start at the top. The ordinary AppKit content
    // view owns a bottom-left backing layer, including after layout/resize.
    return CGRectMake(physical.x - displayBounds.x, displayBounds.bottom() - physical.bottom(),
                      physical.w, physical.h);
}

class ScreenshotProvider final : public OverviewPreview::CaptureProvider {
    struct Cache {
        SCShareableContent* content = nil;
        double discoveredAt = -std::numeric_limits<double>::infinity();
        size_t generation = 0;
        double nextErrorLogAt = 0;
    };
    std::shared_ptr<Cache> m_cache = std::make_shared<Cache>();
    mutable double m_permissionCheckedAt = -std::numeric_limits<double>::infinity();
    mutable bool m_permitted = false;

    static void reportCaptureError(const std::shared_ptr<Cache>& cache, uint32_t wid,
                                   const char* stage, NSError* error) {
        const double now = CACurrentMediaTime();
        if (now < cache->nextErrorLogAt) return;
        cache->nextErrorLogAt = now + 5;
        const char* domain = error.domain.UTF8String;
        std::cout << "OverviewPreview: capture-error WID=" << wid << " stage=" << stage
                  << " domain=" << (domain ? domain : "none") << " code=" << (error ? error.code : 0)
                  << " fallback=live" << std::endl;
    }

    // Blocks preserve C++ reference parameters as references. Own this value so
    // the asynchronous screenshot callback cannot outlive the caller's copy.
    static void captureWindow(std::shared_ptr<Cache> cache, SCShareableContent* content,
                              uint32_t wid, pid_t pid, size_t longestEdge, Completion completion) {
        SCWindow* selected = nil;
        for (SCWindow* candidate in content.windows) {
            if (candidate.windowID == wid && candidate.owningApplication.processID == pid) {
                selected = candidate;
                break;
            }
        }
        if (!selected) {
            // A newly created window may be absent from the short-lived discovery cache.
            cache->content = nil;
            reportCaptureError(cache, wid, "window-lookup", nil);
            completion({});
            return;
        }
        const CGRect frame = selected.frame;
        const double longest = std::max(frame.size.width, frame.size.height);
        if (!std::isfinite(longest) || longest <= 0 || frame.size.width <= 0 || frame.size.height <= 0) {
            reportCaptureError(cache, wid, "invalid-source-frame", nil);
            completion({});
            return;
        }
        const double factor = std::min(1.0, static_cast<double>(longestEdge) / longest);
        SCStreamConfiguration* configuration = [[SCStreamConfiguration alloc] init];
        configuration.width = std::max<size_t>(1, static_cast<size_t>(std::floor(frame.size.width * factor)));
        configuration.height = std::max<size_t>(1, static_cast<size_t>(std::floor(frame.size.height * factor)));
        configuration.showsCursor = NO;
        configuration.ignoreShadowsSingleWindow = YES;
        configuration.captureResolution = SCCaptureResolutionNominal;
        if (@available(macOS 14.2, *)) configuration.includeChildWindows = NO;
        SCContentFilter* filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:selected];
        const auto generation = cache->generation;
        [SCScreenshotManager captureImageWithFilter:filter configuration:configuration
                                 completionHandler:^(CGImageRef image, NSError* error) {
            // Retain before ScreenCaptureKit releases its borrowed callback image.
            auto retained = !error && image ? std::make_shared<OverviewPreview::Image>(image) : nullptr;
            onMain([cache, generation, wid, completion, retained, error] {
                if (cache->generation != generation) { completion({}); return; }
                if (error || !retained) reportCaptureError(cache, wid, "screenshot", error);
                completion(retained);
            });
        }];
    }
public:
    bool permitted() const override {
        const double now = CACurrentMediaTime();
        if (now - m_permissionCheckedAt >= 1.0) {
            m_permitted = CGPreflightScreenCaptureAccess();
            m_permissionCheckedAt = now;
        }
        return m_permitted;
    }
    bool requestPermission() override {
        std::cout << "minfwm daemon: requesting Screen Recording permission for overview previews" << std::endl;
        const bool granted = CGRequestScreenCaptureAccess();
        // Do not reuse a cached denial after the user responds to the dialog.
        m_permissionCheckedAt = -std::numeric_limits<double>::infinity();
        if (!granted) {
            std::cerr << "minfwm daemon: overview previews need Screen Recording access; enable it in "
                         "System Settings > Privacy & Security > Screen Recording. "
                         "Windows remain live without access; macOS may require a daemon restart after granting it."
                      << std::endl;
        }
        return granted;
    }
    void reset() override {
        m_cache->content = nil;
        ++m_cache->generation;
    }
    void capture(uint32_t wid, pid_t pid, size_t longestEdge, Completion completion) override {
        auto cache = m_cache;
        if (cache->content && CACurrentMediaTime() - cache->discoveredAt < 2.0) {
            captureWindow(cache, cache->content, wid, pid, longestEdge, std::move(completion));
            return;
        }
        const auto generation = cache->generation;
        [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:NO
                                                   completionHandler:^(SCShareableContent* content, NSError* error) {
            onMain([cache, generation, content, error, wid, pid, longestEdge, completion] {
                if (cache->generation != generation) { completion({}); return; }
                if (error || !content) {
                    reportCaptureError(cache, wid, "discovery", error);
                    completion({});
                    return;
                }
                cache->content = content;
                cache->discoveredAt = CACurrentMediaTime();
                captureWindow(cache, content, wid, pid, longestEdge, completion);
            });
        }];
    }
};

class LayerPresenter final : public OverviewPreview::Presenter {
    struct PreviewLayer {
        CALayer* layer = nil;
        CGImageRef contents = nullptr; // Borrowed from layer.contents; used only for identity comparison.
        core::Rect physical;
        double zOrder = 0;
    };
    struct Canvas {
        MinfwmOverviewPanel* panel = nil;
        CALayer* layer = nil;
        core::Rect bounds;
        std::unordered_map<uint32_t, PreviewLayer> images;
        std::unordered_set<uint32_t> seen;
    };
    std::unordered_map<int64_t, Canvas> m_canvases;
    static bool sameRect(core::Rect lhs, core::Rect rhs) {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.w == rhs.w && lhs.h == rhs.h;
    }
public:
    bool begin(int64_t displayId, core::Rect bounds) override {
        if (![NSThread isMainThread] || !NSApp || !validRect(bounds)) return false;
        auto& canvas = m_canvases[displayId];
        const bool created = !canvas.panel;
        if (created) {
            canvas.panel = [[MinfwmOverviewPanel alloc]
                initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                backing:NSBackingStoreBuffered defer:NO];
            if (!canvas.panel) return false;
            canvas.panel.releasedWhenClosed = NO;
            canvas.panel.opaque = NO;
            canvas.panel.backgroundColor = NSColor.clearColor;
            canvas.panel.hasShadow = NO;
            canvas.panel.ignoresMouseEvents = YES;
            canvas.panel.hidesOnDeactivate = NO;
            canvas.panel.level = CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey) - 1;
            canvas.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
            canvas.panel.contentView.wantsLayer = YES;
            canvas.layer = canvas.panel.contentView.layer;
            // AppKit manages the backing layer's orientation. Convert window
            // rectangles in previewLayerFrame rather than overriding it here.
            canvas.layer.masksToBounds = YES;
        }
        if (created || !sameRect(canvas.bounds, bounds)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            const CGFloat primaryHeight = CGDisplayBounds(CGMainDisplayID()).size.height;
            [canvas.panel setFrame:NSMakeRect(bounds.x, primaryHeight - bounds.y - bounds.h, bounds.w, bounds.h)
                          display:NO];
            // Existing image frames are relative to bounds; force them to update after display movement.
            for (auto& [wid, image] : canvas.images) image.physical = {};
            canvas.bounds = bounds;
            [CATransaction commit];
        }
        canvas.seen.clear();
        if (created) [canvas.panel orderFront:nil];
        return canvas.layer != nil;
    }
    void show(int64_t displayId, uint32_t wid, const OverviewPreview::ImagePtr& image,
              core::Rect physical, double zOrder) override {
        auto found = m_canvases.find(displayId);
        if (found == m_canvases.end() || !image || !image->get()) return;
        auto& canvas = found->second;
        canvas.seen.insert(wid);
        auto& preview = canvas.images[wid];
        const bool created = !preview.layer;
        if (!created && sameRect(preview.physical, physical) && preview.contents == image->get() &&
            preview.zOrder == zOrder) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (created) {
            preview.layer = [CALayer layer];
            preview.layer.contentsGravity = kCAGravityResize;
            preview.layer.minificationFilter = kCAFilterLinear;
            preview.layer.magnificationFilter = kCAFilterLinear;
            [canvas.layer addSublayer:preview.layer];
        }
        if (created || !sameRect(preview.physical, physical)) {
            preview.layer.frame = previewLayerFrame(physical, canvas.bounds);
            preview.physical = physical;
        }
        if (preview.contents != image->get()) {
            preview.layer.contents = (__bridge id)image->get();
            preview.contents = image->get();
        }
        if (created || preview.zOrder != zOrder) {
            preview.layer.zPosition = zOrder;
            preview.zOrder = zOrder;
        }
        [CATransaction commit];
    }
    void finish(int64_t displayId) override {
        auto found = m_canvases.find(displayId);
        if (found == m_canvases.end()) return;
        auto& canvas = found->second;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (auto it = canvas.images.begin(); it != canvas.images.end();) {
            if (canvas.seen.contains(it->first)) ++it;
            else {
                [it->second.layer removeFromSuperlayer];
                it = canvas.images.erase(it);
            }
        }
        [CATransaction commit];
    }
    void end(int64_t displayId) override {
        auto found = m_canvases.find(displayId);
        if (found == m_canvases.end()) return;
        [found->second.panel orderOut:nil];
        [found->second.panel close];
        m_canvases.erase(found);
    }
    void reset() override {
        for (auto& [id, canvas] : m_canvases) {
            [canvas.panel orderOut:nil];
            [canvas.panel close];
        }
        m_canvases.clear();
    }
    bool ownsCanvasWindow(uint32_t wid) const override {
        for (const auto& [id, canvas] : m_canvases) {
            if (static_cast<uint32_t>(canvas.panel.windowNumber) == wid) return true;
        }
        return false;
    }
    ~LayerPresenter() override { reset(); }
};
} // namespace

OverviewPreview::Image::Image(CGImageRef image) : m_image(image ? CGImageRetain(image) : nullptr) {}
OverviewPreview::Image::~Image() { if (m_image) CGImageRelease(m_image); }
size_t OverviewPreview::Image::bytes() const noexcept {
    if (!m_image) return 0;
    const auto height = CGImageGetHeight(m_image);
    const auto row = CGImageGetBytesPerRow(m_image);
    if (height && row > std::numeric_limits<size_t>::max() / height) return std::numeric_limits<size_t>::max();
    return row * height;
}

struct OverviewPreview::State {
    struct Entry {
        std::weak_ptr<ClientWindow> window;
        ImagePtr image;
        double retryAt = 0;
        bool pending = false;
    };
    struct DrawItem {
        std::weak_ptr<ClientWindow> window;
        core::Rect physical;
        ImagePtr image;
        double zOrder = 0;
    };
    struct Display {
        core::Rect bounds;
        std::vector<uint32_t> frontToBack;
        std::vector<DrawItem> items;
        // Presenter still retains omitted old layers until finishDisplay.
        std::vector<DrawItem> previousItems;
        bool frameOpen = false;
        bool firstPreviewLogged = false;
        double nextSummaryLogAt = 0;
        size_t loggedShown = std::numeric_limits<size_t>::max();
        size_t loggedImages = std::numeric_limits<size_t>::max();
        size_t loggedFailures = std::numeric_limits<size_t>::max();
        size_t loggedCaptures = std::numeric_limits<size_t>::max();
        bool loggedInFlight = false;
    };
    std::shared_ptr<CaptureProvider> provider;
    std::shared_ptr<Presenter> presenter;
    std::unordered_map<uint32_t, Entry> images;
    std::unordered_map<int64_t, Display> displays;
    size_t budget;
    size_t generation = 0;
    bool inFlight = false;
    bool permissionRequestAttempted = false;
    std::optional<bool> loggedPermission;
    std::unordered_map<int64_t, std::string> loggedModes;
    double nextFailureLogAt = 0;
    bool budgetLogged = false;
    double lastLaunch = -std::numeric_limits<double>::infinity();
    double latestNow = 0;
    double captureRetryAt = 0;
    Stats stats;

    void logPermission(bool permitted) {
        if (loggedPermission && *loggedPermission == permitted) return;
        loggedPermission = permitted;
        std::cout << "OverviewPreview: screen-recording=" << (permitted ? "granted" : "missing") << std::endl;
    }
    void logMode(int64_t displayId, const char* mode, float scale, bool force = false) {
        auto& previous = loggedModes[displayId];
        if (!force && previous == mode) return;
        previous = mode;
        std::cout << "OverviewPreview: display=" << displayId << " mode=" << mode
                  << " scale=" << scale << std::endl;
    }

    void clearSession() {
        ++generation;
        if (stats.imageCount) {
            std::cout << "OverviewPreview: cache-released images=" << stats.imageCount
                      << " bytes=" << stats.imageBytes << std::endl;
        }
        images.clear();
        stats.imageBytes = 0;
        stats.imageCount = 0;
        budgetLogged = false;
        provider->reset();
        // inFlight remains true until the outstanding callback acknowledges cancellation.
    }
};

OverviewPreview::OverviewPreview()
    : OverviewPreview(std::make_shared<ScreenshotProvider>(), std::make_shared<LayerPresenter>()) {}
OverviewPreview::OverviewPreview(std::shared_ptr<CaptureProvider> provider,
                                 std::shared_ptr<Presenter> presenter, size_t imageBudget)
    : m_state(std::make_shared<State>()) {
    m_state->provider = std::move(provider);
    m_state->presenter = std::move(presenter);
    m_state->budget = std::min<size_t>(imageBudget, 64 * 1024 * 1024);
}
OverviewPreview::~OverviewPreview() {
    if ([NSThread isMainThread]) reset();
    else {
        // Keep AppKit teardown on main even if ownership is released on another queue.
        auto state = std::move(m_state);
        onMain([state] {
            state->displays.clear();
            if (state->presenter) state->presenter->reset();
            if (state->provider) state->clearSession();
        });
    }
}

bool OverviewPreview::beginDisplay(int64_t displayId, core::Rect bounds, float scale,
                                  bool enabled, bool rewindOnFocus, double now,
                                  const std::vector<uint32_t>& frontToBack) {
    if (![NSThread isMainThread]) return false;
    auto& state = *m_state;
    const bool active = state.displays.contains(displayId);
    if (active && state.displays.at(displayId).frameOpen) finishDisplay(displayId);
    if (!std::isfinite(now) || !validRect(bounds) || !state.provider || !state.presenter) {
        endDisplay(displayId);
        return false;
    }
    state.latestNow = now;
    bool permitted = false;
    if (enabled && std::isfinite(scale) && scale > 0 && scale <= 1) {
        permitted = state.provider->permitted();
        state.logPermission(permitted);
        if (!permitted && !state.permissionRequestAttempted) {
            // Request during initial native-scale frames as well as overview,
            // never repeatedly during animation, denial or session reset.
            state.permissionRequestAttempted = true;
            permitted = state.provider->requestPermission();
            state.logPermission(permitted);
        }
    }
    if (!core::overviewPreviewActive(active, scale, enabled, rewindOnFocus, permitted)) {
        const char* reason = !enabled ? "live reason=disabled" :
            !std::isfinite(scale) || scale <= 0 || scale > 1 ? "live reason=invalid-scale" :
            !permitted ? "live reason=permission-missing" : "live reason=zoom";
        state.logMode(displayId, reason, scale);
        endDisplay(displayId);
        return false;
    }
    if (!state.presenter->begin(displayId, bounds)) {
        state.logMode(displayId, "live reason=canvas-unavailable", scale);
        endDisplay(displayId);
        return false;
    }
    state.logMode(displayId, "previews", scale, !active);
    auto& display = state.displays[displayId];
    auto ordering = frontToBack;
    for (auto wid : display.frontToBack) {
        if (std::find(ordering.begin(), ordering.end(), wid) == ordering.end()) ordering.push_back(wid);
    }
    display.bounds = bounds;
    display.frontToBack = std::move(ordering);
    display.previousItems = std::move(display.items);
    display.items.clear();
    display.frameOpen = true;
    return true;
}
bool OverviewPreview::ready(const std::shared_ptr<ClientWindow>& window, double now) {
    if (![NSThread isMainThread] || !window || !window->wid() || window->pinned || window->isAuxiliaryWindow ||
        !std::isfinite(now) || window->applicationSuspended) return false;
    auto& state = *m_state;
    if (state.displays.empty()) return false;
    state.latestNow = now;
    auto& entry = state.images[window->wid()];
    if (entry.window.lock() != window) {
        // A displayed layer still owns this snapshot until the frame is cleared.
        // Keep its allocation accounted for instead of evicting it on WID reuse.
        if (entry.image) {
            for (const auto& [id, display] : state.displays) {
                for (const auto& item : display.items) {
                    if (item.image == entry.image) return false;
                }
                for (const auto& item : display.previousItems) {
                    if (item.image == entry.image) return false;
                }
            }
        }
        if (entry.image) {
            state.stats.imageBytes -= entry.image->bytes();
            --state.stats.imageCount;
        }
        entry = {window, {}, 0, false};
    }
    if (entry.image) return true;
    // The live renderer must restore a culled or AX-shrunken source before capture.
    if (window->isHidden || window->isAXHidden || window->needsGeometryRestore) return false;
    if (state.stats.imageBytes >= state.budget) {
        if (!state.budgetLogged) {
            state.budgetLogged = true;
            std::cout << "OverviewPreview: cache-budget-reached bytes=" << state.stats.imageBytes
                      << " limit=" << state.budget << " fallback=live" << std::endl;
        }
        return false;
    }
    if (entry.pending || state.inFlight || now < entry.retryAt || now < state.captureRetryAt ||
        now - state.lastLaunch < launchInterval) return false;
    entry.pending = true;
    state.inFlight = true;
    state.lastLaunch = now;
    ++state.stats.captureCount;
    if (state.stats.imageCount == 0 && state.stats.captureCount == 1) {
        std::cout << "OverviewPreview: capture-start WID=" << window->wid() << std::endl;
    }
    const auto generation = state.generation;
    const std::weak_ptr<State> weakState = m_state;
    const std::weak_ptr<ClientWindow> weakWindow = window;
    const auto wid = window->wid();
    state.provider->capture(wid, window->pid(), maxEdge,
        [weakState, weakWindow, wid, generation, now](ImagePtr image) {
            onMain([weakState, weakWindow, wid, generation, now, image] {
                auto state = weakState.lock();
                if (!state) return;
                state->inFlight = false;
                if (state->generation != generation) return;
                auto window = weakWindow.lock();
                auto found = state->images.find(wid);
                if (!window || found == state->images.end() || found->second.window.lock() != window) return;
                auto& entry = found->second;
                entry.pending = false;
                const auto bytes = image ? image->bytes() : 0;
                if (!image || !image->get() || !bytes || CGImageGetWidth(image->get()) > maxEdge ||
                    CGImageGetHeight(image->get()) > maxEdge || bytes > state->budget - state->stats.imageBytes) {
                    ++state->stats.captureFailures;
                    entry.retryAt = std::max(now, state->latestNow) + failureBackoff;
                    state->captureRetryAt = entry.retryAt;
                    const double failureTime = std::max(now, state->latestNow);
                    if (failureTime >= state->nextFailureLogAt) {
                        state->nextFailureLogAt = failureTime + 5;
                        const char* reason = !image || !image->get() || !bytes ? "empty-image" :
                            bytes > state->budget - state->stats.imageBytes ? "cache-budget" : "image-dimensions";
                        std::cout << "OverviewPreview: capture-failed WID=" << wid << " reason=" << reason
                                  << " failures=" << state->stats.captureFailures << " retry-seconds=1 fallback=live"
                                  << std::endl;
                    }
                    return;
                }
                entry.image = image;
                state->stats.imageBytes += bytes;
                ++state->stats.imageCount;
                if (state->stats.imageCount == 1) {
                    std::cout << "OverviewPreview: first-snapshot-ready WID=" << wid
                              << " width=" << CGImageGetWidth(image->get())
                              << " height=" << CGImageGetHeight(image->get())
                              << " bytes=" << bytes << std::endl;
                }
            });
        });
    return false;
}
void OverviewPreview::show(int64_t displayId, const std::shared_ptr<ClientWindow>& window, core::Rect physical) {
    if (![NSThread isMainThread] || !window || !validRect(physical)) return;
    auto& state = *m_state;
    auto display = state.displays.find(displayId);
    auto entry = state.images.find(window->wid());
    if (display == state.displays.end() || entry == state.images.end() || entry->second.window.lock() != window ||
        !entry->second.image) return;
    auto& target = display->second;
    auto index = std::find(target.frontToBack.begin(), target.frontToBack.end(), window->wid());
    if (index == target.frontToBack.end()) {
        target.frontToBack.push_back(window->wid());
        index = std::prev(target.frontToBack.end());
    }
    // Negative ranks keep already shown layers stable as new windows append behind them.
    const double zOrder = -static_cast<double>(std::distance(target.frontToBack.begin(), index));
    target.items.push_back({window, physical, entry->second.image, zOrder});
    state.presenter->show(displayId, window->wid(), entry->second.image, physical, zOrder);
    if (!target.firstPreviewLogged) {
        target.firstPreviewLogged = true;
        std::cout << "OverviewPreview: first-preview-shown display=" << displayId
                  << " WID=" << window->wid() << std::endl;
    }
}
void OverviewPreview::finishDisplay(int64_t displayId) {
    if (![NSThread isMainThread]) return;
    auto found = m_state->displays.find(displayId);
    if (found == m_state->displays.end() || !found->second.frameOpen) return;
    m_state->presenter->finish(displayId);
    auto& display = found->second;
    const auto& stats = m_state->stats;
    const bool changed = display.loggedShown != display.items.size() || display.loggedImages != stats.imageCount ||
        display.loggedFailures != stats.captureFailures || display.loggedCaptures != stats.captureCount ||
        display.loggedInFlight != m_state->inFlight;
    if (changed && m_state->latestNow >= display.nextSummaryLogAt) {
        std::cout << "OverviewPreview: display=" << displayId << " shown=" << display.items.size()
                  << " cached-images=" << stats.imageCount << " cache-bytes=" << stats.imageBytes
                  << " captures=" << stats.captureCount << " failures=" << stats.captureFailures
                  << " in-flight=" << m_state->inFlight << std::endl;
        display.nextSummaryLogAt = m_state->latestNow + 1;
        display.loggedShown = display.items.size();
        display.loggedImages = stats.imageCount;
        display.loggedFailures = stats.captureFailures;
        display.loggedCaptures = stats.captureCount;
        display.loggedInFlight = m_state->inFlight;
    }
    found->second.previousItems.clear();
    found->second.frameOpen = false;
}
void OverviewPreview::endDisplay(int64_t displayId) {
    if (![NSThread isMainThread]) return;
    auto& state = *m_state;
    if (state.presenter) state.presenter->end(displayId);
    if (state.displays.contains(displayId)) {
        std::cout << "OverviewPreview: display=" << displayId << " preview-session-ended" << std::endl;
    }
    if (state.displays.erase(displayId) && state.displays.empty()) state.clearSession();
}
std::shared_ptr<ClientWindow> OverviewPreview::hitTest(core::Point point) const {
    if (![NSThread isMainThread]) return {};
    std::shared_ptr<ClientWindow> result;
    double best = -std::numeric_limits<double>::infinity();
    for (const auto& [id, display] : m_state->displays) {
        if (!contains(display.bounds, point)) continue;
        for (const auto& item : display.items) {
            if (item.zOrder >= best && contains(item.physical, point)) {
                auto window = item.window.lock();
                if (window && !window->applicationSuspended) { result = std::move(window); best = item.zOrder; }
            }
        }
    }
    return result;
}
void OverviewPreview::reset() {
    if (![NSThread isMainThread] || !m_state) return;
    if (!m_state->displays.empty()) {
        std::cout << "OverviewPreview: reset displays=" << m_state->displays.size() << std::endl;
    }
    m_state->displays.clear();
    if (m_state->presenter) m_state->presenter->reset();
    if (m_state->provider) m_state->clearSession();
}
OverviewPreview::Stats OverviewPreview::stats() const { return m_state->stats; }
bool OverviewPreview::ownsCanvasWindow(uint32_t wid) const {
    return [NSThread isMainThread] && wid && m_state->presenter &&
           m_state->presenter->ownsCanvasWindow(wid);
}
} // namespace minfwm
