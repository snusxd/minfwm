#include "IPCServer.hpp"
#include "IPCClient.hpp"
#include "UniqueFd.hpp"

#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <optional>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>

namespace {
int failures = 0;
void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

int descriptorCount() {
    int count = 0;
    for (int fd = 0; fd < 1024; ++fd) {
        if (::fcntl(fd, F_GETFD) != -1) ++count;
    }
    return count;
}

bool exists(const std::string& path) {
    struct stat status{};
    return ::lstat(path.c_str(), &status) == 0;
}

void sendInvalidRequest(const std::string& path, bool partial) {
    minfwm::UniqueFd client(::socket(AF_UNIX, SOCK_STREAM, 0));
    expect(bool(client), "test client socket is created");
    if (!client) return;
    constexpr timeval timeout{1, 0};
    expect(::setsockopt(client.get(), SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0,
           "test client read is bounded");
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
    const bool connected = ::connect(client.get(), reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0;
    expect(connected, "active server remains connectable after failed duplicate startup");
    if (!connected) return;
    const auto frame = minfwm::encodeRequestFrame(minfwm::Request{99, {}});
    expect(minfwm::writeAll(client.get(), frame->data(), partial ? 5 : frame->size()),
           "test request is sent");
    if (partial) expect(::shutdown(client.get(), SHUT_WR) == 0, "partial request ends before its header is complete");
    minfwm::Response response;
    expect(minfwm::readResponse(client.get(), response), "server returns an error frame");
    expect(response.status == minfwm::ResponseStatus::ERROR &&
           response.error == (partial ? minfwm::ErrorCode::MALFORMED : minfwm::ErrorCode::UNSUPPORTED),
           "server rejects partial and unsupported requests before dispatching to AX");
}
}

int main() {
    char directoryTemplate[] = "/tmp/minfwm-server-test-XXXXXX";
    const char* directory = ::mkdtemp(directoryTemplate);
    expect(directory != nullptr, "private server test directory is created");
    if (!directory) return 1;
    const char* previous = std::getenv("TMPDIR");
    const std::optional<std::string> previousDirectory = previous
        ? std::optional<std::string>(previous) : std::nullopt;
    expect(::setenv("TMPDIR", directory, 1) == 0, "test server uses its private directory");
    const std::string path = minfwm::ipcSocketPath();
    {
        minfwm::IPCServer owner, duplicate;
        expect(owner.start(), "IPC server starts without initializing live window state");
        expect(owner.start(), "IPC server start is idempotent");
        const int descriptorsBeforeFailure = descriptorCount();
        for (int attempt = 0; attempt < 8; ++attempt) {
            expect(!duplicate.start(), "duplicate startup is rejected");
            expect(!duplicate.lastError().empty(), "failed startup supplies a diagnostic");
        }
        duplicate.stop();
        duplicate.stop();
        expect(descriptorCount() == descriptorsBeforeFailure,
               "repeated failed startup and stop release all wakeup descriptors");
        expect(exists(path), "failed server stop does not unlink the running server socket");
        sendInvalidRequest(path, false);
        sendInvalidRequest(path, true);
        minfwm::IPCClient client;
        const auto beforeReady = client.sendMessage(minfwm::makePingRequest());
        expect(beforeReady.transportSucceeded && beforeReady.response.status == minfwm::ResponseStatus::ERROR,
               "ping rejects a server before daemon initialization finishes");
        owner.markReady();
        const auto ready = client.sendMessage(minfwm::makePingRequest());
        expect(ready.transportSucceeded && ready.response.status == minfwm::ResponseStatus::OK,
               "ping confirms a ready daemon");
        const auto owned = client.sendMessage(minfwm::makePingRequest(), ::getpid());
        expect(owned.transportSucceeded && owned.response.status == minfwm::ResponseStatus::OK,
               "ping accepts the expected daemon PID");
        expect(owned.peerPid == ::getpid(), "client reports the daemon PID");
        const auto wrongOwner = client.sendMessage(minfwm::makePingRequest(), ::getpid() + 1);
        expect(!wrongOwner.transportSucceeded &&
               wrongOwner.error.find("not expected PID") != std::string::npos,
               "ping rejects a socket owned by another process before sending");
        owner.stop();
        owner.stop();
        expect(!exists(path), "server stop removes its owned socket idempotently");
        expect(duplicate.start(), "failed instance can restart after the owner exits");
        duplicate.stop();
        expect(owner.start(), "stopped owner can start again");
    }
    expect(!exists(path), "server destructor removes its owned socket");
    if (previousDirectory) ::setenv("TMPDIR", previousDirectory->c_str(), 1);
    else ::unsetenv("TMPDIR");
    ::unlink((path + ".lock").c_str());
    ::rmdir(directory);
    return failures == 0 ? 0 : 1;
}
