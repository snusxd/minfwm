#include "Geometry.hpp"
#include <cmath>
#include <limits>
#include <algorithm>

namespace minfwm::core {

bool canUseNativePosition(Rect frame, Rect usable) noexcept {
    const auto valid = [](Rect rect) {
        return std::isfinite(rect.x) && std::isfinite(rect.y) && std::isfinite(rect.w) && std::isfinite(rect.h) &&
            std::isfinite(rect.right()) && std::isfinite(rect.bottom()) && rect.w > 0 && rect.h > 0;
    };
    if (!valid(frame) || !valid(usable) || frame.y < usable.y) return false;
    const float visibleWidth = std::min(frame.right(), usable.right()) - std::max(frame.x, usable.x);
    const float visibleHeight = std::min(frame.bottom(), usable.bottom()) - std::max(frame.y, usable.y);
    return visibleWidth >= std::min(40.0f, frame.w) && visibleHeight >= std::min(40.0f, frame.h);
}

Rect snapViewportToNearFullscreenWindow(Rect previousViewport, Rect viewport,
                                         Rect window, float edgeThreshold,
                                         SnapTuning horizontal, SnapTuning vertical) noexcept {
    const auto valid = [](Rect rect) {
        return std::isfinite(rect.x) && std::isfinite(rect.y) &&
            std::isfinite(rect.w) && std::isfinite(rect.h) &&
            std::isfinite(rect.right()) && std::isfinite(rect.bottom()) &&
            rect.w > 0 && rect.h > 0;
    };
    if (!valid(previousViewport) || !valid(viewport) || !valid(window) ||
        !std::isfinite(edgeThreshold) || edgeThreshold < 0 ||
        window.w < viewport.w * 0.9f || window.h < viewport.h * 0.9f ||
        window.w > viewport.w * 1.2f || window.h > viewport.h * 1.2f) return viewport;

    const auto snapAxis = [edgeThreshold](float previousOrigin, float origin, float viewportLength,
                                          float windowOrigin, float windowLength) {
        const float leadingTarget = windowOrigin;
        const float trailingTarget = windowOrigin + windowLength - viewportLength;
        const float previousLeadingDistance = std::abs(previousOrigin - leadingTarget);
        const float previousTrailingDistance = std::abs(previousOrigin - trailingTarget);
        const float leadingDistance = std::abs(origin - leadingTarget);
        const float trailingDistance = std::abs(origin - trailingTarget);
        const float previousDistance = std::min(previousLeadingDistance, previousTrailingDistance);
        const float distance = std::min(leadingDistance, trailingDistance);
        if (distance > edgeThreshold || distance >= previousDistance) return origin;
        return leadingDistance <= trailingDistance ? leadingTarget : trailingTarget;
    };
    const float autoX = snapAxis(previousViewport.x, viewport.x, viewport.w, window.x, window.w);
    const float autoY = snapAxis(previousViewport.y, viewport.y, viewport.h, window.y, window.h);
    if (autoX == viewport.x && autoY == viewport.y) return viewport;

    const auto tunedTarget = [](SnapTuning tuning, float automaticTarget, float windowOrigin,
                                float windowLength, float viewportLength) {
        switch (tuning) {
            case SnapTuning::leading: return windowOrigin;
            case SnapTuning::center: return static_cast<float>(
                double(windowOrigin) + (double(windowLength) - viewportLength) / 2.0);
            case SnapTuning::trailing: return windowOrigin + windowLength - viewportLength;
            case SnapTuning::automatic: return automaticTarget;
        }
        return automaticTarget;
    };
    viewport.x = tunedTarget(horizontal, autoX, window.x, window.w, viewport.w);
    viewport.y = tunedTarget(vertical, autoY, window.y, window.h, viewport.h);
    return viewport;
}

Rect Rect::expanded(float amount) const noexcept {
    return { x - amount, y - amount, w + (2.0f * amount), h + (2.0f * amount) };
}

Rect Rect::translated(Point delta) const noexcept {
    return { x + delta.x, y + delta.y, w, h };
}

bool Rect::intersects(const Rect& other) const noexcept {
    return right() > other.left() && left() < other.right() &&
           bottom() > other.top() && top() < other.bottom();
}

std::optional<std::int64_t> nearestDisplay(
    std::span<const DisplayGeometry> displays, Point point) noexcept {
    if (!std::isfinite(point.x) || !std::isfinite(point.y)) return std::nullopt;
    std::optional<std::int64_t> closest;
    double closestDistance = std::numeric_limits<double>::infinity();
    for (const auto& display : displays) {
        const Rect& bounds = display.bounds;
        if (!std::isfinite(bounds.x) || !std::isfinite(bounds.y) ||
            !std::isfinite(bounds.w) || !std::isfinite(bounds.h) ||
            !std::isfinite(bounds.right()) || !std::isfinite(bounds.bottom()) ||
            bounds.w <= 0 || bounds.h <= 0) continue;
        if (point.x >= bounds.left() && point.x < bounds.right() &&
            point.y >= bounds.top() && point.y < bounds.bottom()) return display.id;

        const double dx = point.x < bounds.left() ? double(bounds.left()) - point.x :
                          point.x > bounds.right() ? double(point.x) - bounds.right() : 0.0;
        const double dy = point.y < bounds.top() ? double(bounds.top()) - point.y :
                          point.y > bounds.bottom() ? double(point.y) - bounds.bottom() : 0.0;
        const double distance = dx * dx + dy * dy;
        if (distance < closestDistance) {
            closest = display.id;
            closestDistance = distance;
        }
    }
    return closest;
}

} // namespace minfwm::core
