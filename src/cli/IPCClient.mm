#include "IPCClient.hpp"

#include <cstring>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

namespace minfwm {

namespace {

bool isTrustedSocketPath(const std::string& path) {
    struct stat status{};
    return ::lstat(path.c_str(), &status) == 0 &&
           S_ISSOCK(status.st_mode) &&
           status.st_uid == ::getuid() &&
           (status.st_mode & 0777) == (S_IRUSR | S_IWUSR);
}

bool setClientTimeouts(int fileDescriptor) {
    constexpr timeval timeout = {1, 0};
    return ::setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0 &&
           ::setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) == 0;
}

} // namespace

IPCClient::Result IPCClient::sendMessage(const Request& request) {
    const auto encodedRequest = encodeRequestFrame(request);
    if (!encodedRequest.has_value()) {
        return Result{false, {}, "request payload exceeds protocol limit"};
    }

    const int clientFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (clientFd == -1) {
        return Result{false, {}, "failed to create socket"};
    }

    struct ScopedDescriptor {
        int value;
        ~ScopedDescriptor() {
            if (value != -1) {
                close(value);
            }
        }
    } descriptor{clientFd};

    if (!setClientTimeouts(clientFd)) {
        return Result{false, {}, "failed to configure socket timeouts"};
    }

    const std::string path = ipcSocketPath();
    if (path.size() >= sizeof(sockaddr_un::sun_path)) {
        return Result{false, {}, "socket path is too long"};
    }
    if (!isTrustedSocketPath(path)) {
        return Result{false, {}, "daemon socket is missing or has unsafe ownership"};
    }

    struct sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

    if (connect(clientFd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) == -1) {
        return Result{false, {}, "failed to connect to daemon"};
    }

    if (!writeAll(clientFd, encodedRequest->data(), encodedRequest->size())) {
        return Result{false, {}, "failed to send request"};
    }

    Response response;
    if (!readResponse(clientFd, response)) {
        return Result{false, {}, "invalid or missing daemon response"};
    }
    return Result{true, response, {}};
}

} // namespace minfwm
