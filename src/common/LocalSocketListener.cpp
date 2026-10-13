#include "LocalSocketListener.hpp"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/un.h>

namespace minfwm {
namespace {

std::string systemError(const char* operation) {
    return std::string(operation) + ": " + std::strerror(errno);
}

bool sameSocket(const struct stat& first, const struct stat& second) {
    return S_ISSOCK(first.st_mode) && S_ISSOCK(second.st_mode) &&
        first.st_uid == ::getuid() && second.st_uid == ::getuid() &&
        first.st_dev == second.st_dev && first.st_ino == second.st_ino;
}

bool verifyDirectory(const std::string& path, std::string& error) {
    const auto separator = path.find_last_of('/');
    const std::string directory = separator == std::string::npos ? "." :
        separator == 0 ? "/" : path.substr(0, separator);
    struct stat status{};
    if (::lstat(directory.c_str(), &status) != 0) {
        error = systemError("failed to inspect socket directory");
        return false;
    }
    if (!S_ISDIR(status.st_mode) || status.st_uid != ::getuid() ||
        (status.st_mode & (S_IWGRP | S_IWOTH)) != 0) {
        error = "socket directory must be owned by the user and not writable by other users";
        return false;
    }
    return true;
}

bool removeStaleSocket(const std::string& path, const sockaddr_un& address, std::string& error) {
    struct stat original{};
    if (::lstat(path.c_str(), &original) != 0) {
        if (errno == ENOENT) return true;
        error = systemError("failed to inspect socket path");
        return false;
    }
    if (!S_ISSOCK(original.st_mode) || original.st_uid != ::getuid() || (original.st_mode & 0777) != 0600) {
        error = "refusing to replace socket path with unsafe type, ownership or permissions";
        return false;
    }
    // Also protect a running daemon from an older version without the lock.
    UniqueFd probe(::socket(AF_UNIX, SOCK_STREAM, 0));
    if (!probe || ::fcntl(probe.get(), F_SETFL, O_NONBLOCK) == -1) {
        error = systemError("failed to probe existing socket");
        return false;
    }
    const int result = ::connect(probe.get(), reinterpret_cast<const sockaddr*>(&address), sizeof(address));
    if (result == 0 || errno != ECONNREFUSED) {
        error = "socket is already in use or cannot be safely reclaimed";
        return false;
    }
    struct stat current{};
    if (::lstat(path.c_str(), &current) != 0 || !sameSocket(original, current)) {
        error = "socket path changed while checking for a stale listener";
        return false;
    }
    if (::unlink(path.c_str()) != 0) {
        error = systemError("failed to remove stale socket");
        return false;
    }
    return true;
}

} // namespace

bool LocalSocketListener::open(std::string& error) {
    error.clear();
    if (m_socket) return true;
    sockaddr_un address{};
    if (m_path.empty() || m_path.find('\0') != std::string::npos || m_path.size() >= sizeof(address.sun_path)) {
        error = "socket path is empty or too long";
        return false;
    }
    if (!verifyDirectory(m_path, error)) return false;
    auto fail = [&](std::string message) {
        error = std::move(message);
        (void)close();
        return false;
    };
    m_lock.reset(::open((m_path + ".lock").c_str(), O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600));
    if (!m_lock) return fail(systemError("failed to open socket lock"));
    struct stat lockStatus{};
    if (::fstat(m_lock.get(), &lockStatus) != 0) return fail(systemError("failed to inspect socket lock"));
    if (!S_ISREG(lockStatus.st_mode) || lockStatus.st_uid != ::getuid() ||
        (lockStatus.st_mode & 0777) != 0600 || lockStatus.st_nlink != 1) {
        return fail("socket lock has unsafe type, ownership or permissions");
    }
    if (::flock(m_lock.get(), LOCK_EX | LOCK_NB) != 0) return fail("another daemon owns the socket lock");

    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, m_path.c_str(), m_path.size() + 1);
    if (!removeStaleSocket(m_path, address, error)) return fail(error);
    m_socket.reset(::socket(AF_UNIX, SOCK_STREAM, 0));
    if (!m_socket) return fail(systemError("failed to create socket"));
    if (::bind(m_socket.get(), reinterpret_cast<const sockaddr*>(&address), sizeof(address)) != 0) {
        return fail(systemError("failed to bind socket"));
    }
    struct stat bound{};
    if (::lstat(m_path.c_str(), &bound) != 0) return fail(systemError("failed to inspect bound socket"));
    if (!S_ISSOCK(bound.st_mode) || bound.st_uid != ::getuid()) return fail("bound socket path was replaced");
    m_boundIdentity = bound;
    if (::chmod(m_path.c_str(), 0600) != 0) return fail(systemError("failed to set socket permissions"));
    struct stat verified{};
    if (::lstat(m_path.c_str(), &verified) != 0 || !sameSocket(bound, verified) ||
        (verified.st_mode & 0777) != 0600) return fail("bound socket identity or permissions changed");
    if (::listen(m_socket.get(), 5) != 0) return fail(systemError("failed to listen on socket"));
    return true;
}

bool LocalSocketListener::close() noexcept {
    m_socket.reset();
    bool succeeded = true;
    if (m_boundIdentity) {
        struct stat current{};
        if (::lstat(m_path.c_str(), &current) == 0) {
            if (sameSocket(*m_boundIdentity, current)) succeeded = ::unlink(m_path.c_str()) == 0 || errno == ENOENT;
        } else {
            succeeded = errno == ENOENT;
        }
        m_boundIdentity.reset();
    }
    // Keep the lock file's inode stable across restarts. Unlinking it while
    // another process opens it would let two daemons hold different locks.
    m_lock.reset();
    return succeeded;
}

} // namespace minfwm
