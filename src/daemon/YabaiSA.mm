#import "YabaiSA.hpp"
#import <Foundation/Foundation.h>
#include <chrono>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

namespace minfwm {

namespace {

constexpr uint8_t kHandshakeOpcode = 0x01;
constexpr uint8_t kWindowMoveOpcode = 0x06;
constexpr uint8_t kWindowLayerOpcode = 0x09;
constexpr uint32_t kSetWindowAttribute = 0x20;
constexpr size_t kMaxPacketLength = 0x1000;
constexpr int kTimeoutMilliseconds = 100;

using Clock = std::chrono::steady_clock;
using Deadline = Clock::time_point;

void appendU16(std::vector<uint8_t>& packet, uint16_t value) {
    packet.push_back(static_cast<uint8_t>(value & 0xff));
    packet.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
}

void appendU32(std::vector<uint8_t>& packet, uint32_t value) {
    for (unsigned shift = 0; shift < 32; shift += 8) {
        packet.push_back(static_cast<uint8_t>((value >> shift) & 0xff));
    }
}

void appendI32(std::vector<uint8_t>& packet, int value) {
    appendU32(packet, static_cast<uint32_t>(static_cast<int32_t>(value)));
}

std::vector<uint8_t> finishPacket(std::vector<uint8_t> body) {
    if (body.size() > std::numeric_limits<int16_t>::max()) return {};
    std::vector<uint8_t> packet;
    appendU16(packet, static_cast<uint16_t>(body.size()));
    packet.insert(packet.end(), body.begin(), body.end());
    return packet;
}

bool waitFor(int fd, short events, Deadline deadline) {
    pollfd descriptor{fd, events, 0};
    for (;;) {
        const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now());
        if (remaining.count() <= 0) return false;

        const int result = poll(&descriptor, 1, static_cast<int>(remaining.count()));
        if (result > 0) {
            if ((descriptor.revents & (POLLERR | POLLNVAL)) != 0) return false;
            if ((descriptor.revents & events) != 0) return true;
            if ((events & POLLIN) != 0 && (descriptor.revents & POLLHUP) != 0) return true;
            return false;
        }
        if (result < 0 && errno == EINTR) continue;
        return false;
    }
}

bool sendAll(int fd, const uint8_t* data, size_t size) {
    const Deadline deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMilliseconds);
    size_t offset = 0;
    while (offset < size) {
        const ssize_t sent = send(fd, data + offset, size - offset, MSG_NOSIGNAL | MSG_DONTWAIT);
        if (sent > 0) {
            offset += static_cast<size_t>(sent);
            continue;
        }
        if (sent < 0 && errno == EINTR) continue;
        if (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) &&
            waitFor(fd, POLLOUT, deadline)) {
            continue;
        }
        return false;
    }
    return true;
}

bool receiveExact(int fd, uint8_t* data, size_t size, Deadline deadline) {
    size_t offset = 0;
    while (offset < size) {
        if (!waitFor(fd, POLLIN, deadline)) return false;
        const ssize_t received = recv(fd, data + offset, size - offset, MSG_DONTWAIT);
        if (received > 0) {
            offset += static_cast<size_t>(received);
            continue;
        }
        if (received < 0 && errno == EINTR) continue;
        if (received < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        return false;
    }
    return true;
}

bool receiveAckOrEof(int fd) {
    const Deadline deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMilliseconds);
    for (;;) {
        if (!waitFor(fd, POLLIN, deadline)) return false;

        uint8_t ack = 0;
        const ssize_t received = recv(fd, &ack, 1, MSG_DONTWAIT);
        if (received == 0) return true;
        if (received == 1) return ack == 0;
        if (received < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) {
            continue;
        }
        return false;
    }
}

int connectTo(const std::string& path) {
    if (path.empty() || path.size() >= sizeof(sockaddr_un::sun_path)) return -1;
    const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::strncpy(address.sun_path, path.c_str(), sizeof(address.sun_path) - 1);
    if (connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

bool parseVersion(const std::string& version) {
    return version.size() >= 2 && version[0] == '2' && version[1] == '.';
}

} // namespace

YabaiSA::YabaiSA(std::string socketPath) : m_socketPath(std::move(socketPath)) {
    if (m_socketPath.empty()) {
        const char* user = std::getenv("USER");
        if (!user || !*user) user = [NSUserName() UTF8String];
        if (user && *user) m_socketPath = std::string("/tmp/yabai-sa_") + user + ".socket";
    }
}

bool YabaiSA::isOwnedSocket() const {
    struct stat info{};
    if (lstat(m_socketPath.c_str(), &info) != 0) return false;
    if (!S_ISSOCK(info.st_mode) || info.st_uid != getuid()) return false;
    return (info.st_mode & 077) == 0;
}

std::vector<uint8_t> YabaiSA::encodeHandshakePacket() {
    return {0x01, 0x00, kHandshakeOpcode};
}

std::vector<uint8_t> YabaiSA::encodeMovePacket(uint32_t wid, int x, int y) {
    std::vector<uint8_t> body;
    body.reserve(1 + sizeof(wid) + sizeof(int32_t) * 2);
    body.push_back(kWindowMoveOpcode);
    appendU32(body, wid);
    appendI32(body, x);
    appendI32(body, y);
    return finishPacket(std::move(body));
}

std::vector<uint8_t> YabaiSA::encodeLayerPacket(uint32_t wid, int layer) {
    std::vector<uint8_t> body;
    body.reserve(1 + sizeof(wid) + sizeof(int32_t));
    body.push_back(kWindowLayerOpcode);
    appendU32(body, wid);
    appendI32(body, layer);
    return finishPacket(std::move(body));
}

bool YabaiSA::handshake() {
    m_compatible = false;
    if (!isOwnedSocket()) return false;
    const int fd = connectTo(m_socketPath);
    if (fd < 0) return false;

    const std::vector<uint8_t> packet = encodeHandshakePacket();
    bool result = sendAll(fd, packet.data(), packet.size());
    std::string version;
    uint8_t byte = 0;
    const Deadline deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMilliseconds);
    if (result) {
        for (size_t i = 0; i < 64; ++i) {
            if (!receiveExact(fd, &byte, 1, deadline)) {
                result = false;
                break;
            }
            if (byte == 0) break;
            version.push_back(static_cast<char>(byte));
        }
    }

    uint8_t attributes[sizeof(uint32_t)]{};
    if (result && (version.empty() || version.size() >= 64 ||
                   !receiveExact(fd, attributes, sizeof(attributes), deadline))) {
        result = false;
    }

    uint32_t attributeBits = 0;
    if (result) {
        attributeBits = static_cast<uint32_t>(attributes[0]) |
                        (static_cast<uint32_t>(attributes[1]) << 8) |
                        (static_cast<uint32_t>(attributes[2]) << 16) |
                        (static_cast<uint32_t>(attributes[3]) << 24);
        m_compatible = parseVersion(version) && (attributeBits & kSetWindowAttribute) != 0;
    }
    close(fd);
    return result && m_compatible;
}

bool YabaiSA::sendPacket(const std::vector<uint8_t>& packet) const {
    if (packet.size() < 3 || packet.size() > kMaxPacketLength || !isOwnedSocket()) return false;
    const int fd = connectTo(m_socketPath);
    if (fd < 0) return false;

    bool result = sendAll(fd, packet.data(), packet.size());
    if (result) {
        // Current Yabai closes the request socket without a payload for these
        // operations. A zero byte is accepted by test doubles as an explicit ACK.
        result = receiveAckOrEof(fd);
    }
    shutdown(fd, SHUT_RDWR);
    close(fd);
    return result;
}

bool YabaiSA::moveWindow(uint32_t wid, int x, int y) const {
    return wid != 0 && m_compatible && sendPacket(encodeMovePacket(wid, x, y));
}

bool YabaiSA::setWindowLayer(uint32_t wid, int layer) const {
    return wid != 0 && m_compatible && sendPacket(encodeLayerPacket(wid, layer));
}

YabaiSABackend::YabaiSABackend(std::string socketPath) : m_sa(std::move(socketPath)) {}

bool YabaiSABackend::initialize() {
    return m_sa.handshake();
}

BackendResult YabaiSABackend::move(AXUIElementRef, uint32_t wid, int x, int y) {
    if (!available()) return {BackendCode::unavailable};
    return {m_sa.moveWindow(wid, x, y) ? BackendCode::ok : BackendCode::failed};
}

BackendResult YabaiSABackend::resize(AXUIElementRef, uint32_t, float, float) {
    return {BackendCode::unsupported};
}

BackendResult YabaiSABackend::setLayer(AXUIElementRef, uint32_t wid, int layer) {
    if (!available()) return {BackendCode::unavailable};
    return {m_sa.setWindowLayer(wid, layer) ? BackendCode::ok : BackendCode::failed};
}

BackendResult YabaiSABackend::setHidden(AXUIElementRef, uint32_t, bool) {
    return {BackendCode::unsupported};
}

BackendResult YabaiSABackend::restore(AXUIElementRef, uint32_t, int, int, float, float) {
    return {BackendCode::unsupported};
}

} // namespace minfwm
