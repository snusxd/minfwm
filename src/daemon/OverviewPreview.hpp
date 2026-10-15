#pragma once

#include "Geometry.hpp"
#include <CoreGraphics/CoreGraphics.h>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <sys/types.h>
#include <vector>

namespace minfwm {
class ClientWindow;

// Main-thread adapter. Pending or failed captures always leave the original live.
class OverviewPreview {
public:
    struct Stats {
        size_t imageBytes = 0;
        size_t imageCount = 0;
        size_t captureCount = 0;
        size_t captureFailures = 0;
    };
    class Image {
    public:
        explicit Image(CGImageRef image); // Retains the borrowed image.
        ~Image();
        Image(const Image&) = delete;
        Image& operator=(const Image&) = delete;
        [[nodiscard]] CGImageRef get() const noexcept { return m_image; }
        [[nodiscard]] size_t bytes() const noexcept;
    private:
        CGImageRef m_image;
    };
    using ImagePtr = std::shared_ptr<const Image>;
    class CaptureProvider {
    public:
        using Completion = std::function<void(ImagePtr)>;
        virtual ~CaptureProvider() = default;
        [[nodiscard]] virtual bool permitted() const = 0;
        // Completion may arrive on any queue; the adapter marshals to main.
        virtual void capture(uint32_t wid, pid_t pid, size_t longestEdge, Completion completion) = 0;
        virtual void reset() {}
    };
    class Presenter {
    public:
        virtual ~Presenter() = default;
        // Prepare this frame before any original window is parked.
        // finish removes layers omitted from the completed frame.
        virtual bool begin(int64_t displayId, core::Rect globalBounds) = 0;
        virtual void show(int64_t displayId, uint32_t wid, const ImagePtr& image,
                          core::Rect physical, double zOrder) = 0;
        virtual void finish(int64_t) {}
        virtual void end(int64_t displayId) = 0;
        virtual void reset() = 0;
        [[nodiscard]] virtual bool ownsCanvasWindow(uint32_t) const { return false; }
    };

    OverviewPreview();
    OverviewPreview(std::shared_ptr<CaptureProvider> provider, std::shared_ptr<Presenter> presenter,
                    size_t imageBudget = 64 * 1024 * 1024);
    ~OverviewPreview();
    OverviewPreview(const OverviewPreview&) = delete;
    OverviewPreview& operator=(const OverviewPreview&) = delete;

    bool beginDisplay(int64_t displayId, core::Rect globalTopLeftBounds, float scale,
                      bool enabled, bool rewindOnFocus, double now,
                      const std::vector<uint32_t>& frontToBack);
    bool ready(const std::shared_ptr<ClientWindow>& window, double now);
    void show(int64_t displayId, const std::shared_ptr<ClientWindow>& window, core::Rect physical);
    void finishDisplay(int64_t displayId);
    void endDisplay(int64_t displayId);
    [[nodiscard]] std::shared_ptr<ClientWindow> hitTest(core::Point point) const;
    void reset();
    [[nodiscard]] Stats stats() const;
    [[nodiscard]] bool ownsCanvasWindow(uint32_t wid) const;

private:
    struct State;
    std::shared_ptr<State> m_state;
};
} // namespace minfwm
