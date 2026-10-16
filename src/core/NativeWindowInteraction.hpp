#pragma once

#include "Geometry.hpp"
#include <cmath>
#include <optional>

namespace minfwm::core {

// Immutable coordinate epochs: native frame, canvas frame, screen pointer.
// Application chrome and accessibility roles are deliberately not inputs.
class NativeWindowInteraction final {
public:
    enum class Kind { stationary, move, resize };
    static std::optional<NativeWindowInteraction> begin(Rect native, Rect canvas, Rect visual,
                                                       Point pointer, float scale) {
        if (!valid(native) || !valid(canvas) || !valid(visual) || !finite(pointer) ||
            !std::isfinite(scale) || scale <= 0) return {};
        return NativeWindowInteraction(native, canvas, visual, pointer, scale);
    }
    std::optional<Rect> observe(Rect native, Point pointer, bool dragging) {
        if (!valid(native) || !finite(pointer)) return {};
        const bool resized = std::abs(native.w - m_native.w) > 0.5f || std::abs(native.h - m_native.h) > 0.5f;
        const bool moved = std::abs(native.x - m_native.x) > 0.5f || std::abs(native.y - m_native.y) > 0.5f;
        Kind kind = m_kind;
        if (dragging && resized) kind = Kind::resize;
        else if (dragging && moved && kind == Kind::stationary) kind = Kind::move;
        Rect result = m_canvas;
        // Native dimensions are logical window units. Inverse projection of a
        // presentation rect would corrupt them whenever the camera is scaled.
        result.w = native.w;
        result.h = native.h;
        if (kind == Kind::move) {
            result.x += (pointer.x - m_pointer.x) / m_scale;
            result.y += (pointer.y - m_pointer.y) / m_scale;
        } else if (kind == Kind::resize) {
            // Infer anchors after observing a real native resize. These halves
            // are not hit areas: all controls still receive their native input.
            if (m_pointer.x < m_visual.x + m_visual.w / 2 && std::abs(native.w - m_native.w) > 0.5f)
                result.x = m_canvas.x + m_native.w - native.w;
            if (m_pointer.y < m_visual.y + m_visual.h / 2 && std::abs(native.h - m_native.h) > 0.5f)
                result.y = m_canvas.y + m_native.h - native.h;
        }
        if (!valid(result)) return {};
        m_kind = kind;
        return result;
    }
    Kind kind() const { return m_kind; }
private:
    static bool finite(Point p) { return std::isfinite(p.x) && std::isfinite(p.y); }
    static bool valid(Rect r) {
        return finite({r.x, r.y}) && std::isfinite(r.w) && std::isfinite(r.h) && r.w > 0 && r.h > 0 &&
            std::isfinite(r.right()) && std::isfinite(r.bottom());
    }
    NativeWindowInteraction(Rect native, Rect canvas, Rect visual, Point pointer, float scale)
        : m_native(native), m_canvas(canvas), m_visual(visual), m_pointer(pointer), m_scale(scale) {}
    Rect m_native, m_canvas, m_visual;
    Point m_pointer;
    float m_scale;
    Kind m_kind = Kind::stationary;
};
} // namespace minfwm::core
