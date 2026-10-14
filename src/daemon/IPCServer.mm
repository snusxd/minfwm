#include "IPCServer.hpp"

#include "ConfigManager.hpp"
#include "WindowManager.hpp"
#include "LocalSocketListener.hpp"

#include <dispatch/dispatch.h>
#include <chrono>
#include <cerrno>
#include <condition_variable>
#include <iostream>
#include <memory>
#include <mutex>
#include <poll.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <thread>
#include <unistd.h>

namespace minfwm {
namespace {

std::string systemError(const char* operation, int errorNumber = errno) {
    return std::string(operation) + ": " + std::strerror(errorNumber);
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
    if (m_wakeupReadFd != -1) {
        ::close(m_wakeupReadFd);
        m_wakeupReadFd = -1;
    }
    if (m_wakeupWriteFd != -1) {
        ::close(m_wakeupWriteFd);
        m_wakeupWriteFd = -1;
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
        (void)::send(wakeupWriteFd, &wakeupByte, sizeof(wakeupByte), MSG_NOSIGNAL);
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
    LocalSocketListener listener(m_socketPath);

    auto cleanup = [&]() {
        if (!listener.close()) {
            std::cerr << "IPCServer: failed to remove owned socket path" << std::endl;
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

    std::string pathError;
    if (!listener.open(pathError)) {
        failStartup(pathError);
        return;
    }
    const int serverFd = listener.fd();

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
    UniqueFd client(clientFd);
    if (!setClientTimeouts(clientFd)) {
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
                        if (!wm.mainDisplay().camera().move(x, y)) {
                            std::lock_guard lock(state->mutex);
                            state->result = ErrorCode::MALFORMED;
                        } else {
                            wm.mainDisplay().state().cancelCameraAnimation();
                            wm.updateWindows();
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
        default:
            return ErrorCode::UNSUPPORTED;
    }
}

} // namespace minfwm
