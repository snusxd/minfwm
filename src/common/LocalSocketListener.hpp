#pragma once

#include "UniqueFd.hpp"
#include <optional>
#include <string>
#include <sys/stat.h>

namespace minfwm {

class LocalSocketListener final {
public:
    explicit LocalSocketListener(std::string path) : m_path(std::move(path)) {}
    ~LocalSocketListener() { (void)close(); }
    LocalSocketListener(const LocalSocketListener&) = delete;
    LocalSocketListener& operator=(const LocalSocketListener&) = delete;

    bool open(std::string& error);
    bool close() noexcept;
    [[nodiscard]] int fd() const noexcept { return m_socket.get(); }

private:
    std::string m_path;
    UniqueFd m_lock;
    UniqueFd m_socket;
    std::optional<struct stat> m_boundIdentity;
};

} // namespace minfwm
