#include "NativeWindowInteraction.hpp"
#include <iostream>
#include <limits>
using namespace minfwm::core;
int failures = 0;
void expect(bool value, const char* why) { if (!value) { std::cerr << "FAIL: " << why << '\n'; ++failures; } }
int main() {
    const Rect native{200, 100, 740, 833}, canvas{-450, -860, 740, 833}, visual{1213, 517, 740, 833};
    auto moving = NativeWindowInteraction::begin(native, canvas, visual, {1672, 556}, 1);
    auto result = moving->observe({1209, 243, 740, 833}, {1666, 556}, true);
    expect(result && result->x == -456 && result->y == -860, "native coordinate jump never becomes a canvas jump");
    result = moving->observe({1209, 243, 740, 833}, {1600, 580}, true);
    expect(result && result->x == -522 && result->y == -836, "recognized move follows pointer when native frame clamps");
    expect(moving->kind() == NativeWindowInteraction::Kind::move, "native origin change under pointer drag identifies movement");
    auto content = NativeWindowInteraction::begin(native, canvas, visual, {1400, 800}, 1);
    result = content->observe(native, {1600, 900}, true);
    expect(result && result->x == canvas.x && result->y == canvas.y && content->kind() == NativeWindowInteraction::Kind::stationary,
           "control/scrollbar drag without native frame changes never moves the canvas");
    auto resize = NativeWindowInteraction::begin(native, canvas, visual, {1216, 520}, 1);
    result = resize->observe({0, 46, 600, 700}, {1300, 600}, true);
    expect(result && result->w == 600 && result->h == 700 && result->right() == canvas.right() && result->bottom() == canvas.bottom(),
           "actual native resize dimensions anchor opposite canvas edges without adopting clamp origin");
    for (int edge = 0; edge < 8; ++edge) {
        const bool left = edge == 0 || edge == 4 || edge == 6;
        const bool right = edge == 1 || edge == 5 || edge == 7;
        const bool top = edge == 2 || edge == 4 || edge == 5;
        const bool bottom = edge == 3 || edge == 6 || edge == 7;
        const Point pointer{visual.x + (left ? 1 : right ? visual.w - 1 : visual.w / 2),
                            visual.y + (top ? 1 : bottom ? visual.h - 1 : visual.h / 2)};
        auto transaction = NativeWindowInteraction::begin(native, canvas, visual, pointer, 1);
        const Rect actual{-1900, -1000, left || right ? 600.f : native.w, top || bottom ? 700.f : native.h};
        result = transaction->observe(actual, {pointer.x + 50, pointer.y + 50}, true);
        expect(result && (left ? result->right() == canvas.right() : result->x == canvas.x) &&
               (top ? result->bottom() == canvas.bottom() : result->y == canvas.y),
               "all four edges and corners keep their opposite canvas anchors despite native clamp");
    }
    auto staleWidth = NativeWindowInteraction::begin(native, {-450, -860, 940.724f, 833}, visual, {1500, 520}, 1);
    result = staleWidth->observe({200, 46, 740, 1080}, {1500, 400}, true);
    expect(result && result->w == 740 && result->h == 1080, "untouched axis uses native dimensions rather than a stale canvas size");
    auto scaled = NativeWindowInteraction::begin(native, canvas, {-1500, -200, 370, 416.5f}, {-1400, -180}, .5f);
    result = scaled->observe({210, 110, 740, 833}, {-1370, -160}, true);
    expect(result && result->x == canvas.x + 60 && result->y == canvas.y + 40 && result->w == 740,
           "pointer delta divides by scale once while native size stays in canvas units");
    auto click = NativeWindowInteraction::begin(native, canvas, visual, {1400, 550}, 1);
    result = click->observe(native, {1400, 550}, false);
    expect(result && result->x == canvas.x && click->kind() == NativeWindowInteraction::Kind::stationary, "stationary click has no canvas movement");
    expect(!click->observe({NAN, 0, 740, 833}, {1400, 550}, true), "malformed native observation is rejected atomically");
    expect(!NativeWindowInteraction::begin(native, canvas, visual, {0, 0}, 0), "invalid scale cannot start interaction");
    auto overflow = NativeWindowInteraction::begin(native, canvas, visual,
        {-std::numeric_limits<float>::max(), 0}, 1);
    expect(!overflow->observe({210, 100, 740, 833}, {std::numeric_limits<float>::max(), 0}, true) &&
           overflow->kind() == NativeWindowInteraction::Kind::stationary,
           "overflowed pointer displacement cannot mutate gesture classification");
    return failures ? 1 : 0;
}
