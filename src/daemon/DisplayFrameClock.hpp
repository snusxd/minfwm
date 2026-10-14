#pragma once

#include <cstdint>
#include <functional>
#include <memory>

namespace minfwm {

class DisplayFrameClock final {
public:
    DisplayFrameClock();
    ~DisplayFrameClock();
    DisplayFrameClock(const DisplayFrameClock&) = delete;
    DisplayFrameClock& operator=(const DisplayFrameClock&) = delete;
    bool start(std::function<void(int64_t)> callback, std::function<void()> screenChanged = {});
    void stop();

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

}
