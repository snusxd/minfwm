#include "LocalSocketListener.hpp"

#include <cstring>
#include <cstdlib>
#include <fcntl.h>
#include <iostream>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {
int failures = 0;
void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

minfwm::UniqueFd legacyListener(const std::string& path) {
    minfwm::UniqueFd fd(::socket(AF_UNIX, SOCK_STREAM, 0));
    if (!fd) return {};
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
    if (::bind(fd.get(), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
        ::chmod(path.c_str(), 0600) != 0 || ::listen(fd.get(), 5) != 0) return {};
    return fd;
}

bool exists(const std::string& path) {
    struct stat status{};
    return ::lstat(path.c_str(), &status) == 0;
}
}

int main() {
    char directoryTemplate[] = "/tmp/minfwm-ipc-test-XXXXXX";
    const char* directory = ::mkdtemp(directoryTemplate);
    expect(directory != nullptr, "private test directory is created");
    if (!directory) return 1;
    const std::string path = std::string(directory) + "/minfwm.sock";
    std::string error;

    {
        minfwm::LocalSocketListener first(path), second(path);
        expect(first.open(error), "first listener starts");
        struct stat status{};
        expect(::lstat(path.c_str(), &status) == 0 && (status.st_mode & 0777) == 0600 &&
               status.st_uid == ::getuid(), "socket is owned by the user with mode 0600");
        expect(first.open(error), "starting an active listener is idempotent");
        expect(!second.open(error), "second instance cannot replace a running listener");
        expect(second.close() && exists(path), "failed instance cleanup preserves the active socket");
        expect(first.close() && !exists(path), "owner cleanup removes its socket");
        expect(first.close(), "owner cleanup is idempotent");
        expect(second.open(error), "listener can start again after the owner stops");
    }
    expect(!exists(path), "destructor cleans up the owned socket");

    const pid_t child = ::fork();
    expect(child != -1, "crashed-owner test process starts");
    if (child == 0) {
        minfwm::LocalSocketListener crashedOwner(path);
        // Simulate a crash: the kernel closes descriptors, while C++ cleanup
        // never removes the socket pathname.
        ::_exit(crashedOwner.open(error) ? 0 : 1);
    }
    if (child > 0) {
        int status = 0;
        expect(::waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
               "crashed owner successfully bound its socket");
        minfwm::LocalSocketListener restarted(path);
        expect(restarted.open(error), "kernel releases the crash owner's lock and its stale socket is reclaimed");
    }

    {
        auto legacy = legacyListener(path);
        expect(bool(legacy), "legacy listener without a lock starts");
        minfwm::LocalSocketListener candidate(path);
        expect(!candidate.open(error), "active socket without a lock is not mistaken for a stale socket");
        expect(candidate.close() && exists(path), "failed startup preserves the legacy listener");
        legacy.reset();
        expect(candidate.open(error), "closed stale socket can be reclaimed");
    }

    {
        minfwm::LocalSocketListener owner(path);
        expect(owner.open(error), "listener for replacement test starts");
        expect(::unlink(path.c_str()) == 0, "test removes the original pathname");
        auto replacement = legacyListener(path);
        expect(bool(replacement), "replacement socket starts at the same pathname");
        expect(owner.close() && exists(path), "cleanup preserves a replacement with a different inode");
        replacement.reset();
        ::unlink(path.c_str());
    }

    {
        minfwm::UniqueFd ordinary(::open(path.c_str(), O_CREAT | O_EXCL | O_WRONLY, 0600));
        expect(bool(ordinary), "ordinary file at the socket path is created");
        minfwm::LocalSocketListener candidate(path);
        expect(!candidate.open(error), "ordinary file is rejected");
        expect(candidate.close() && exists(path), "cleanup preserves an ordinary file");
        ordinary.reset();
        ::unlink(path.c_str());

        expect(::symlink("missing-target", path.c_str()) == 0, "test symlink is created");
        expect(!candidate.open(error), "symlink socket path is rejected");
        expect(candidate.close() && exists(path), "cleanup preserves a symlink");
        ::unlink(path.c_str());
    }

    {
        expect(::chmod(directory, 0777) == 0, "test directory becomes writable by other users");
        minfwm::LocalSocketListener unsafe(path);
        expect(!unsafe.open(error) && !exists(path), "unsafe runtime directory is rejected before binding");
        ::chmod(directory, 0700);
    }
    ::unlink((path + ".lock").c_str());
    ::rmdir(directory);
    return failures == 0 ? 0 : 1;
}
