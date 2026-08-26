#include "IPCServer.hpp"

#include "ConfigManager.hpp"
#include "WindowManager.hpp"

#include <dispatch/dispatch.h>
#include <chrono>
#include <cerrno>
#include <condition_variable>
#include <cstring>
#include <iostream>
#include <memory>
#include <mutex>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>

namespace minfwm {
namespace {

constexpr mode_t kSocketMode = S_IRUSR | S_IWUSR;

std::string systemError(const char* operation, int errorNumber = errno) {
    return std::string(operation) + ": " + std::strerror(errorNumber);
}

bool removeOwnedSocketPath(const std::string& path) {
    struct stat status{};
    if (::lstat(path.c_str(), &status) == -1) {
        return errno == ENOENT;
    }
    if (!S_ISSOCK(status.st_mode) || status.st_uid != ::getuid()) {
        return false;
    }
    return ::unlink(path.c_str()) == 0 || errno == ENOENT;
}

bool prepareSocketPath(const std::string& path, std::string& error) {
    struct stat status{};
    if (::lstat(path.c_str(), &status) == -1) {
        if (errno == ENOENT) {
            return true;
        }
        error = systemError("failed to inspect socket path");
        return false;
    }

    if (!S_ISSOCK(status.st_mode)) {
        error = "refusing to replace non-socket at " + path;
        return false;
    }
    if (status.st_uid != ::getuid()) {
        error = "refusing to replace socket owned by another user";
        return false;
    }
    if ((status.st_mode & 0777) != kSocketMode) {
        error = "refusing to replace socket without mode 0600";
        return false;
    }
    if (::unlink(path.c_str()) == -1) {
        error = systemError("failed to remove stale socket");
        return false;
    }
    return true;
}

bool verifySocketDirectory(const std::string& path, std::string& error) {
    const std::size_t separator = path.find_last_of('/');
    const std::string directory = separator == std::string::npos
        ? "."
        : (separator == 0 ? "/" : path.substr(0, separator));

    struct stat status{};
    if (::lstat(directory.c_str(), &status) == -1) {
        error = systemError("failed to inspect socket directory");
        return false;
    }
    if (!S_ISDIR(status.st_mode) || status.st_uid != ::getuid()) {
        error = "socket directory is not an owned directory";
        return false;
    }
    if ((status.st_mode & (S_IWGRP | S_IWOTH)) != 0) {
        error = "socket directory is writable by another user";
        return false;
    }
    return true;
}

bool verifyBoundSocket(const std::string& path, int socketFd, std::string& error) {
    struct stat pathStatus{};
    if (::lstat(path.c_str(), &pathStatus) == -1) {
        error = systemError("failed to stat bound socket");
        return false;
    }
    if (!S_ISSOCK(pathStatus.st_mode) || pathStatus.st_uid != ::getuid()) {
        error = "bound path is not an owned Unix socket";
        return false;
    }
    if ((pathStatus.st_mode & 0777) != kSocketMode) {
        error = "bound socket does not have mode 0600";
        return false;
    }

    struct stat descriptorStatus{};
    if (::fstat(socketFd, &descriptorStatus) == -1) {
        error = systemError("failed to fstat bound socket");
        return false;
    }
    if (!S_ISSOCK(descriptorStatus.st_mode) || descriptorStatus.st_uid != ::getuid()) {
        error = "bound descriptor is not an owned Unix socket";
        return false;
    }
    return true;
}

bool setClientTimeouts(int clientFd) {
    constexpr timeval timeout = {1, 0};
    return ::setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0 &&
           ::setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) == 0;
}

struct MainQueueState {
    std::mutex mutex;
    std::condition_variable condition;
    bool complete = false;
    bool cancelled = false;
    ErrorCode result = ErrorCode::NONE;
};

} // namespace

IPCServer::IPCServer()
    : m_socketPath(ipcSocketPath()),
      m_running(false),
      m_wakeupReadFd(-1),
      m_wakeupWriteFd(-1),
      m_startComplete(false),
      m_startSucceeded(false) {}

IPCServer::~IPCServer() {
    stop();
}

bool IPCServer::start() {
    std::unique_lock lock(m_stateMutex);
    if (m_running.load()) {
        return true;
    }

    if (m_serverThread.joinable()) {
        lock.unlock();
        m_serverThread.join();
        lock.lock();
    }

    int wakeupDescriptors[2] = {-1, -1};
    if (::socketpair(AF_UNIX, SOCK_STREAM, 0, wakeupDescriptors) == -1) {
        m_startComplete = true;
        m_startSucceeded = false;
        m_startError = systemError("failed to create server wakeup socket");
        return false;
    }

    m_wakeupReadFd = wakeupDescriptors[0];
    m_wakeupWriteFd = wakeupDescriptors[1];
    m_startComplete = false;
    m_startSucceeded = false;
    m_startError.clear();
    m_running = true;

    try {
        m_serverThread = std::thread(&IPCServer::run, this);
    } catch (const std::exception& exception) {
        m_running = false;
        ::close(m_wakeupReadFd);
        ::close(m_wakeupWriteFd);
        m_wakeupReadFd = -1;
        m_wakeupWriteFd = -1;
        m_startComplete = true;
        m_startSucceeded = false;
        m_startError = std::string("failed to start server thread: ") + exception.what();
        return false;
    }

    m_startCondition.wait(lock, [this] { return m_startComplete; });
    return m_startSucceeded;
}

void IPCServer::stop() {
    int wakeupWriteFd = -1;
    {
        std::lock_guard lock(m_stateMutex);
        m_running = false;
        wakeupWriteFd = m_wakeupWriteFd;
    }

    if (wakeupWriteFd != -1) {
        const std::uint8_t wakeupByte = 1;
        (void)::write(wakeupWriteFd, &wakeupByte, sizeof(wakeupByte));
    }

    if (m_serverThread.joinable()) {
        m_serverThread.join();
    }

    {
        std::lock_guard lock(m_stateMutex);
        if (m_wakeupWriteFd != -1) {
            ::close(m_wakeupWriteFd);
            m_wakeupWriteFd = -1;
        }
        if (m_wakeupReadFd != -1) {
            ::close(m_wakeupReadFd);
            m_wakeupReadFd = -1;
        }
    }

    if (!removeOwnedSocketPath(m_socketPath)) {
        std::cerr << "IPCServer: refusing to remove unexpected socket path "
                  << m_socketPath << std::endl;
    }
}

std::string IPCServer::lastError() const {
    std::lock_guard lock(m_stateMutex);
    return m_startError;
}

void IPCServer::setStartupResult(bool succeeded, std::string error) {
    {
        std::lock_guard lock(m_stateMutex);
        m_startComplete = true;
        m_startSucceeded = succeeded;
        m_startError = std::move(error);
        if (!succeeded) {
            m_running = false;
        }
    }
    m_startCondition.notify_all();
}

void IPCServer::run() {
    const int wakeupReadFd = m_wakeupReadFd;
    int serverFd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    bool pathBound = false;

    auto cleanup = [&]() {
        if (serverFd != -1) {
            ::close(serverFd);
            serverFd = -1;
        }
        if (pathBound) {
            (void)removeOwnedSocketPath(m_socketPath);
            pathBound = false;
        }
        if (wakeupReadFd != -1) {
            ::close(wakeupReadFd);
            std::lock_guard lock(m_stateMutex);
            if (m_wakeupReadFd == wakeupReadFd) {
                m_wakeupReadFd = -1;
            }
        }
    };

    auto failStartup = [&](const std::string& error) {
        std::cerr << "IPCServer: " << error << std::endl;
        setStartupResult(false, error);
        cleanup();
    };

    if (serverFd == -1) {
        failStartup(systemError("failed to create socket"));
        return;
    }

    struct sockaddr_un address{};
    if (m_socketPath.size() >= sizeof(address.sun_path)) {
        failStartup("socket path is too long");
        return;
    }
    std::string pathError;
    if (!verifySocketDirectory(m_socketPath, pathError) ||
        !prepareSocketPath(m_socketPath, pathError)) {
        failStartup(pathError);
        return;
    }

    address.sun_family = AF_UNIX;
    std::strncpy(address.sun_path, m_socketPath.c_str(), sizeof(address.sun_path) - 1);
    if (::bind(serverFd, reinterpret_cast<struct sockaddr*>(&address), sizeof(address)) == -1) {
        failStartup(systemError("failed to bind socket"));
        return;
    }
    pathBound = true;

    if (::chmod(m_socketPath.c_str(), kSocketMode) == -1) {
        failStartup(systemError("failed to chmod socket"));
        return;
    }
    if (!verifyBoundSocket(m_socketPath, serverFd, pathError)) {
        failStartup(pathError);
        return;
    }
    if (::listen(serverFd, 5) == -1) {
        failStartup(systemError("failed to listen on socket"));
        return;
    }

    setStartupResult(true, {});
    std::cout << "IPCServer: Listening on " << m_socketPath << std::endl;

    struct pollfd descriptors[2] = {
        {serverFd, POLLIN, 0},
        {wakeupReadFd, POLLIN, 0}
    };
    while (m_running.load()) {
        const int pollResult = ::poll(descriptors, 2, -1);
        if (pollResult == -1) {
            if (errno == EINTR) {
                continue;
            }
            const std::string error = systemError("server poll failed");
            std::cerr << "IPCServer: " << error << std::endl;
            std::lock_guard lock(m_stateMutex);
            m_startError = error;
            m_running = false;
            break;
        }

        if ((descriptors[1].revents & (POLLIN | POLLHUP | POLLERR)) != 0) {
            std::uint8_t wakeupByte = 0;
            (void)::read(wakeupReadFd, &wakeupByte, sizeof(wakeupByte));
            if (!m_running.load()) {
                break;
            }
        }
        if (!m_running.load()) {
            break;
        }

        if ((descriptors[0].revents & POLLIN) != 0) {
            const int clientFd = ::accept(serverFd, nullptr, nullptr);
            if (clientFd == -1) {
                if (errno != EINTR && m_running.load()) {
                    std::cerr << "IPCServer: "
                              << systemError("failed to accept connection") << std::endl;
                }
                continue;
            }
            handleClient(clientFd);
        }
    }

    cleanup();
}

void IPCServer::handleClient(int clientFd) {
    if (!setClientTimeouts(clientFd)) {
        ::close(clientFd);
        return;
    }

    Request request;
    const ErrorCode parseError = readRequestFrame(clientFd, request);
    Response response;
    if (parseError != ErrorCode::NONE) {
        response = makeErrorResponse(parseError);
    } else {
        const ErrorCode dispatchError = dispatchRequest(request);
        response = dispatchError == ErrorCode::NONE
            ? makeSuccessResponse()
            : makeErrorResponse(dispatchError);
    }

    (void)writeResponse(clientFd, response);
    ::close(clientFd);
}

ErrorCode IPCServer::dispatchRequest(const Request& request) {
    switch (static_cast<Command>(request.command)) {
        case Command::RELOAD: {
            auto state = std::make_shared<MainQueueState>();
            dispatch_async(dispatch_get_main_queue(), ^{
                bool cancelled = false;
                {
                    std::lock_guard lock(state->mutex);
                    cancelled = state->cancelled;
                }
                if (!cancelled) {
                    try {
                        std::cout << "IPCServer: Received RELOAD" << std::endl;
                        if (!ConfigManager::instance().load()) {
                            std::lock_guard lock(state->mutex);
                            state->result = ErrorCode::INTERNAL;
                        }
                    } catch (...) {
                        std::lock_guard lock(state->mutex);
                        state->result = ErrorCode::INTERNAL;
                    }
                }
                {
                    std::lock_guard lock(state->mutex);
                    state->complete = true;
                }
                state->condition.notify_one();
            });

            std::unique_lock lock(state->mutex);
            while (!state->complete) {
                if (state->condition.wait_for(lock, std::chrono::milliseconds(10),
                                              [&] { return state->complete; })) {
                    break;
                }
                if (!m_running.load()) {
                    state->cancelled = true;
                    return ErrorCode::INTERNAL;
                }
            }
            return state->result;
        }
        case Command::CAMERA_MOVE: {
            float x = 0.0F;
            float y = 0.0F;
            if (!decodeCameraMove(request, x, y)) {
                return ErrorCode::MALFORMED;
            }

            auto state = std::make_shared<MainQueueState>();
            dispatch_async(dispatch_get_main_queue(), ^{
                bool cancelled = false;
                {
                    std::lock_guard lock(state->mutex);
                    cancelled = state->cancelled;
                }
                if (!cancelled) {
                    try {
                        std::cout << "IPCServer: Received CAMERA_MOVE: " << x << ", " << y << std::endl;
                        auto& wm = WindowManager::instance();
                        wm.mainDisplay().camera().move(x, y);
                        wm.updateWindows();
                    } catch (...) {
                        std::lock_guard lock(state->mutex);
                        state->result = ErrorCode::INTERNAL;
                    }
                }
                {
                    std::lock_guard lock(state->mutex);
                    state->complete = true;
                }
                state->condition.notify_one();
            });

            std::unique_lock lock(state->mutex);
            while (!state->complete) {
                if (state->condition.wait_for(lock, std::chrono::milliseconds(10),
                                              [&] { return state->complete; })) {
                    break;
                }
                if (!m_running.load()) {
                    state->cancelled = true;
                    return ErrorCode::INTERNAL;
                }
            }
            return state->result;
        }
        default:
            return ErrorCode::UNSUPPORTED;
    }
}

} // namespace minfwm
