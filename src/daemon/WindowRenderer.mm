#include "WindowRenderer.hpp"

#include <cmath>
#include <limits>
#include <iostream>

namespace minfwm {
namespace {

bool pixelPosition(core::Rect rect, int& x, int& y) {
    if (!std::isfinite(rect.x) || !std::isfinite(rect.y) ||
        !std::isfinite(rect.w) || !std::isfinite(rect.h) || rect.w <= 0 || rect.h <= 0) return false;
    const double roundedX = std::round(static_cast<double>(rect.x));
    const double roundedY = std::round(static_cast<double>(rect.y));
    if (roundedX < std::numeric_limits<int>::min() || roundedX > std::numeric_limits<int>::max() ||
        roundedY < std::numeric_limits<int>::min() || roundedY > std::numeric_limits<int>::max()) return false;
    x = static_cast<int>(roundedX);
    y = static_cast<int>(roundedY);
    return true;
}

void invalidatePosition(ClientWindow& window) {
    window.lastRenderedX = std::numeric_limits<float>::quiet_NaN();
    window.lastRenderedY = std::numeric_limits<float>::quiet_NaN();
}

} // namespace

BackendResult WindowRenderer::suspend(ClientWindow& window, double now) {
    const auto result = resetTransform(window);
    if (!result.succeeded()) return result;
    invalidatePosition(window);
    window.positionNeedsVerification = false;
    window.rejectedPosition.reset();
    window.positionRetryTime = 0;
    window.lastProgrammaticMoveTime = now;
    window.applicationSuspended = true;
    window.nativePresentationChecked = false;
    return result;
}

BackendResult WindowRenderer::releaseToNative(ClientWindow& window, core::Rect physical, double now) {
    int x = 0, y = 0;
    if (!pixelPosition(physical, x, y)) return {BackendCode::failed};

    window.lastProgrammaticMoveTime = now;
    window.positionNeedsVerification = false;
    window.rejectedPosition.reset();
    window.positionRetryTime = 0;
    window.hideRetryTime = 0;

    // Transfer the currently presented position to the native frame before
    // dropping any Yabai transform, so pinning does not jump to the old frame.
    BackendResult moved{BackendCode::failed};
    if (m_yabai.usesTransforms()) moved = m_yabai.moveNative(window.ref(), window.wid(), x, y);
    if (!moved.succeeded()) {
        (void)resetTransform(window);
        moved = m_ax.move(window.ref(), window.wid(), x, y);
    }
    if (!moved.succeeded()) return moved;

    if (window.isLayerSet) {
        if (!restoreLayer(window).succeeded()) return {BackendCode::failed};
        window.isLayerSet = false;
    }
    window.layerAttempted = false;
    window.lastRenderedX = x;
    window.lastRenderedY = y;
    window.lastRenderedScale = 1;
    window.overviewPresented = false;
    window.isHidden = false;
    window.isAXHidden = false;
    window.needsGeometryRestore = false;
    return {BackendCode::ok};
}

BackendResult WindowRenderer::setPinnedLayer(ClientWindow& window, bool alwaysOnTop) {
    BackendResult result = m_yabai.setPinnedLayer(window.ref(), window.wid(), alwaysOnTop);
    if (!result.succeeded()) result = m_ax.setPinnedLayer(window.ref(), window.wid(), alwaysOnTop);
    if (result.succeeded()) {
        window.isLayerSet = alwaysOnTop;
        window.pinnedLevelSet = alwaysOnTop;
        window.layerAttempted = true;
        window.pinnedAlwaysOnTop = alwaysOnTop;
        window.pinLayerRetryTime = 0;
    }
    return result;
}

bool WindowRenderer::acceptNativeGeometry(ClientWindow& window, core::Rect physical, const core::DisplayState& state) {
    int x = 0, y = 0;
    if (!pixelPosition(physical, x, y)) return false;
    const auto virtualFrame = state.physicalToVirtual(physical);
    if (!std::isfinite(virtualFrame.x) || !std::isfinite(virtualFrame.y)) return false;
    window.virtualRect = virtualFrame;
    window.virtualCoordinatesInitialized = true;
    window.lastRenderedX = x;
    window.lastRenderedY = y;
    // A native drag can clear the WindowServer presentation transform. Force
    // the next overview frame to reapply its scale at the newly accepted spot.
    window.lastRenderedScale = 1;
    window.positionNeedsVerification = false;
    window.positionFallbackAttempted = false;
    window.rejectedPosition.reset();
    window.positionRetryTime = 0;
    window.hideRetryTime = 0;
    window.lastProgrammaticMoveTime = 0;
    return true;
}

BackendResult WindowRenderer::move(ClientWindow& window, int x, int y) {
    if (window.preferNativePosition && m_yabai.usesTransforms()) {
        const bool hadTransform = m_yabai.hasTransform(window.wid());
        const auto native = m_yabai.moveNative(window.ref(), window.wid(), x, y);
        if (hadTransform && !m_yabai.hasTransform(window.wid()) &&
            !(native.succeeded() && m_yabai.nativeMovePreservesLayer())) {
            window.isLayerSet = false;
            window.layerAttempted = false;
        }
        if (native.succeeded()) return native;
    }
    const BackendResult result = m_yabai.move(window.ref(), window.wid(), x, y);
    if (result.succeeded()) return result;
    (void)resetTransform(window);
    return m_ax.move(window.ref(), window.wid(), x, y);
}

BackendResult WindowRenderer::resetTransform(ClientWindow& window) {
    const BackendResult result = m_yabai.resetTransform(window.wid());
    if (result.succeeded() && m_yabai.usesTransforms()) {
        // The payload restores the captured level along with the transform.
        window.isLayerSet = window.pinnedLevelSet;
        window.layerAttempted = false;
        window.lastRenderedScale = 1;
        window.overviewPresented = false;
    }
    return result;
}

BackendResult WindowRenderer::setLayer(ClientWindow& window, int layer) {
    const BackendResult result = m_yabai.setLayer(window.ref(), window.wid(), layer);
    return result.succeeded() ? result : m_ax.setLayer(window.ref(), window.wid(), layer);
}

BackendResult WindowRenderer::restoreLayer(ClientWindow& window) {
    const BackendResult result = window.pinnedLevelSet
        ? m_yabai.setPinnedLayer(window.ref(), window.wid(), false)
        : setLayer(window, kCGNormalWindowLevelKey);
    if (result.succeeded()) {
        window.pinnedLevelSet = false;
        window.isLayerSet = false;
    }
    return result;
}

BackendResult WindowRenderer::render(ClientWindow& window, core::Rect physical, double now) {
    int x = 0, y = 0;
    if (!window.originalPhysicalRect || !pixelPosition(physical, x, y)) return {BackendCode::failed};
    window.applicationSuspended = false;
    if (window.overviewPresented || window.lastRenderedScale != 1) {
        invalidatePosition(window);
        window.positionNeedsVerification = false;
        window.rejectedPosition.reset();
        window.positionRetryTime = 0;
    }
    if (now < window.positionRetryTime) return {BackendCode::failed};
    window.hideRetryTime = 0;
    if (window.rejectedPosition) {
        if (window.rejectedPosition->x == x && window.rejectedPosition->y == y) return {BackendCode::failed};
        window.rejectedPosition.reset();
    }
    const bool geometryDirty = window.isHidden || window.needsGeometryRestore ||
        window.lastRenderedX != x || window.lastRenderedY != y;
    if (!geometryDirty && window.positionNeedsVerification && now >= window.positionVerificationTime) {
        const bool matched = m_checkPosition && m_checkPosition(window.ref(), window.wid(), x, y);
        if (matched) {
            window.positionNeedsVerification = false;
        } else {
            // AppKit may correct the position after the synchronous SA readback.
            // Attempt AX once, then stop fighting an application that constrains
            // the frame. A new camera target allows movement again.
            (void)resetTransform(window);
            const bool recovered = !window.positionFallbackAttempted &&
                m_ax.move(window.ref(), window.wid(), x, y).succeeded();
            window.positionFallbackAttempted = true;
            if (!recovered) {
                window.positionNeedsVerification = false;
                window.rejectedPosition = core::Point{static_cast<float>(x), static_cast<float>(y)};
                window.positionRetryTime = now + 0.25;
                invalidatePosition(window);
                std::cerr << "WindowRenderer: position rejected after readback (WID " << window.wid()
                          << ", target " << x << ',' << y << ")" << std::endl;
                return {BackendCode::failed};
            }
            window.lastProgrammaticMoveTime = now;
            window.positionVerificationTime = now + 0.25;
        }
    }
    if (!geometryDirty && window.layerAttempted) return {BackendCode::ok};

    window.lastProgrammaticMoveTime = now;
    if (geometryDirty) {
        if (window.isAXHidden) {
            const BackendResult shown = m_ax.setHidden(window.ref(), window.wid(), false);
            if (!shown.succeeded()) return shown;
            window.isAXHidden = false;
            window.isHidden = false;
            window.needsGeometryRestore = true;
        }
        BackendResult geometry;
        if (window.needsGeometryRestore) {
            // Resizing via AX can pull the frame below the menu bar. Apply the
            // final position through SA (with AX fallback) after restoring size.
            (void)resetTransform(window);
            const BackendResult resized = m_ax.resize(window.ref(), window.wid(), physical.w, physical.h);
            const BackendResult moved = move(window, x, y);
            geometry = resized.succeeded() ? moved : resized;
        } else {
            geometry = move(window, x, y);
        }
        if (!geometry.succeeded()) {
            // A failed operation may still have changed or clamped the frame.
            // Do not reuse the previously cached position on the next render.
            invalidatePosition(window);
            window.positionNeedsVerification = false;
            if (!window.needsGeometryRestore) {
                window.rejectedPosition = core::Point{static_cast<float>(x), static_cast<float>(y)};
            }
            window.positionRetryTime = now + 0.25;
            return geometry;
        }
        window.isHidden = false;
        window.needsGeometryRestore = false;
        window.lastRenderedX = x;
        window.lastRenderedY = y;
        window.lastRenderedScale = 1;
        window.overviewPresented = false;
        window.positionRetryTime = 0;
        window.positionNeedsVerification = true;
        window.positionFallbackAttempted = false;
        window.positionVerificationTime = now + 0.25;
    }
    if (!window.layerAttempted) {
        window.isLayerSet = setLayer(window, kCGPopUpMenuWindowLevelKey).succeeded();
        window.layerAttempted = true;
    }
    return {BackendCode::ok};
}

BackendResult WindowRenderer::renderOverview(ClientWindow& window, core::Rect physical, float scale, double now) {
    int x = 0, y = 0;
    if (!m_yabai.supportsOverview()) return {BackendCode::unsupported};
    if (!window.originalPhysicalRect || !pixelPosition(physical, x, y) ||
        !std::isfinite(scale) || scale < 0.2f || scale > 1) return {BackendCode::failed};
    window.applicationSuspended = false;
    scale = std::round(scale * 1000) / 1000;
    if (window.lastRenderedX == x && window.lastRenderedY == y && window.lastRenderedScale == scale &&
        !window.isHidden && !window.needsGeometryRestore) return {BackendCode::ok};
    window.lastProgrammaticMoveTime = now;
    window.positionNeedsVerification = false;
    window.rejectedPosition.reset();
    window.positionRetryTime = 0;
    if (window.isAXHidden) {
        if (!m_ax.setHidden(window.ref(), window.wid(), false).succeeded()) return {BackendCode::failed};
        window.isAXHidden = false;
    }
    if (window.needsGeometryRestore) {
        if (!resetTransform(window).succeeded() ||
            !m_ax.resize(window.ref(), window.wid(), window.virtualRect.w, window.virtualRect.h).succeeded()) {
            return {BackendCode::failed};
        }
        window.needsGeometryRestore = false;
    }
    // Scale presentation only. AX resize would relayout the application and
    // cannot provide an overview of its existing content.
    const auto result = m_yabai.presentOverview(window.ref(), window.wid(), x, y, scale);
    if (!result.succeeded()) {
        invalidatePosition(window);
        return result;
    }
    window.lastRenderedX = x;
    window.lastRenderedY = y;
    window.lastRenderedScale = scale;
    window.overviewPresented = true;
    window.isHidden = false;
    if (!window.layerAttempted) {
        window.isLayerSet = setLayer(window, kCGPopUpMenuWindowLevelKey).succeeded();
        window.layerAttempted = true;
    }
    return result;
}

BackendResult WindowRenderer::hide(ClientWindow& window, core::Rect physical,
                                    core::Rect displayBounds, double now) {
    if (!window.originalPhysicalRect) return {BackendCode::failed};
    if (window.isHidden) return {BackendCode::ok};
    if (now < window.hideRetryTime) return {BackendCode::failed};
    window.hideRetryTime = now + 0.5;
    // A fully culled window can retain its native frame. Resetting a transform
    // and AX-shrinking it exposes it to AppKit's minimum-size/edge corrections.
    const bool outside = physical.right() <= displayBounds.x || physical.x >= displayBounds.right() ||
        physical.bottom() <= displayBounds.y || physical.y >= displayBounds.bottom();
    int translatedX = 0, translatedY = 0;
    if (m_yabai.usesTransforms() && outside && pixelPosition(physical, translatedX, translatedY)) {
        const BackendResult translated = m_yabai.move(window.ref(), window.wid(), translatedX, translatedY);
        if (translated.succeeded()) {
            window.isHidden = true;
            window.lastRenderedScale = 1;
            window.overviewPresented = false;
            window.positionNeedsVerification = false;
            window.rejectedPosition.reset();
            window.hideRetryTime = 0;
            window.positionRetryTime = 0;
            window.lastProgrammaticMoveTime = now;
            invalidatePosition(window);
            return translated;
        }
    }
    if (!resetTransform(window).succeeded()) return {BackendCode::failed};
    window.positionNeedsVerification = false;
    window.rejectedPosition.reset();
    window.lastProgrammaticMoveTime = now;
    const BackendResult hidden = m_ax.setHidden(window.ref(), window.wid(), true);
    if (hidden.succeeded()) {
        window.isHidden = true;
        window.isAXHidden = true;
        window.hideRetryTime = 0;
        invalidatePosition(window);
        return hidden;
    }

    core::Rect previous = physical;
    if (std::isfinite(window.lastRenderedX) && std::isfinite(window.lastRenderedY)) {
        previous.x = window.lastRenderedX;
        previous.y = window.lastRenderedY;
    }
    int previousX = 0, previousY = 0, cornerX = 0, cornerY = 0;
    if (!pixelPosition(previous, previousX, previousY) ||
        !pixelPosition({displayBounds.right() - 1, displayBounds.bottom() - 1, 1, 1}, cornerX, cornerY)) {
        return {BackendCode::failed};
    }
    const BackendResult resized = m_ax.resize(window.ref(), window.wid(), 1, 1);
    if (!resized.succeeded()) return resized;
    window.needsGeometryRestore = true;
    const BackendResult parked = m_ax.move(window.ref(), window.wid(), cornerX, cornerY);
    if (!parked.succeeded()) {
        // A successful shrink must be undone even if the subsequent move fails.
        const BackendResult rollback = m_ax.restore(window.ref(), window.wid(), previousX, previousY,
                                                     previous.w, previous.h);
        window.needsGeometryRestore = !rollback.succeeded();
        if (!rollback.succeeded()) invalidatePosition(window);
        return parked;
    }
    window.isHidden = true;
    window.isAXHidden = false;
    window.hideRetryTime = 0;
    invalidatePosition(window);
    return {BackendCode::ok};
}

BackendResult WindowRenderer::restore(ClientWindow& window, double now) {
    int x = 0, y = 0;
    if (!window.originalPhysicalRect || !pixelPosition(*window.originalPhysicalRect, x, y)) {
        return {BackendCode::failed};
    }
    window.lastProgrammaticMoveTime = now;
    window.positionNeedsVerification = false;
    window.rejectedPosition.reset();
    window.positionRetryTime = 0;
    window.hideRetryTime = 0;
    bool shown = true;
    const bool transformReset = resetTransform(window).succeeded();
    if (window.isAXHidden) {
        shown = m_ax.setHidden(window.ref(), window.wid(), false).succeeded();
        if (shown) window.isAXHidden = false;
    }
    const core::Rect original = *window.originalPhysicalRect;
    const BackendResult geometry = m_ax.restore(window.ref(), window.wid(), x, y, original.w, original.h);
    window.needsGeometryRestore = !geometry.succeeded();
    if (geometry.succeeded()) {
        if (shown) window.isHidden = false;
        window.lastRenderedX = original.x;
        window.lastRenderedY = original.y;
    }
    bool layerRestored = true;
    if (window.isLayerSet) {
        layerRestored = restoreLayer(window).succeeded();
        if (layerRestored) window.isLayerSet = false;
    }
    return {transformReset && shown && geometry.succeeded() && layerRestored ? BackendCode::ok : BackendCode::failed};
}

} // namespace minfwm
