#pragma once

#include <cstdint>

namespace minfwm {

enum class MessageType : uint32_t {
    RELOAD = 0,
    CAMERA_MOVE = 1,
    CAMERA_CENTER_ON_WINDOW = 2,
    WINDOW_MOVE_DISPLAY = 3,
    QUERY_STATE = 4
};

struct IPCMessage {
    MessageType type;
    union {
        struct {
            float x;
            float y;
        } camera_move;
        struct {
            uint32_t window_id;
            int32_t display_id;
        } window_move;
    } data;
};

} // namespace minfwm
