#pragma once

#include "../core/Geometry.hpp"

#include <functional>
#include <memory>

namespace minfwm {

class TrackpadInput final {
public:
    using Handler = std::function<void(bool active, core::Point delta)>;

    TrackpadInput();
    ~TrackpadInput();

    TrackpadInput(const TrackpadInput&) = delete;
    TrackpadInput& operator=(const TrackpadInput&) = delete;

    bool start(Handler handler);
    void stop();

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace minfwm
