#pragma once

#include <unistd.h>
#include <utility>

namespace minfwm {

class UniqueFd final {
public:
    UniqueFd() noexcept = default;
    explicit UniqueFd(int fd) noexcept : m_fd(fd) {}
    ~UniqueFd() { reset(); }
    UniqueFd(const UniqueFd&) = delete;
    UniqueFd& operator=(const UniqueFd&) = delete;
    UniqueFd(UniqueFd&& other) noexcept : m_fd(other.release()) {}
    UniqueFd& operator=(UniqueFd&& other) noexcept {
        if (this != &other) reset(other.release());
        return *this;
    }
    [[nodiscard]] int get() const noexcept { return m_fd; }
    explicit operator bool() const noexcept { return m_fd != -1; }
    int release() noexcept { return std::exchange(m_fd, -1); }
    void reset(int fd = -1) noexcept {
        if (m_fd != -1) (void)::close(m_fd);
        m_fd = fd;
    }

private:
    int m_fd = -1;
};

} // namespace minfwm
