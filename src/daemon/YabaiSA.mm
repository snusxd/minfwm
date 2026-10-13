#import "YabaiSA.hpp"
#import <Foundation/Foundation.h>
#include "UniqueFd.hpp"
#include <chrono>
#include <charconv>
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

bool receiveAckOrEof(int fd, bool explicitAck) {
    const Deadline deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMilliseconds);
    for (;;) {
        if (!waitFor(fd, POLLIN, deadline)) return false;

        uint8_t ack = 0;
        const ssize_t received = recv(fd, &ack, 1, MSG_DONTWAIT);
        if (received == 0) return !explicitAck;
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
    // Accept the existing 2.x.y wire family, with three numeric components.
    const char* cursor = version.data();
    const char* end = cursor + version.size();
    for (int component = 0; component < 3; ++component) {
        unsigned value = 0;
        const auto parsed = std::from_chars(cursor, end, value);
        if (parsed.ec != std::errc{} || parsed.ptr == cursor || (component == 0 && value != 2)) return false;
        if (component == 2) return parsed.ptr == end;
        if (parsed.ptr == end || *parsed.ptr != '.') return false;
        cursor = parsed.ptr + 1;
    }
    return false;
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
    m_transformSupport = false;
    if (!isOwnedSocket()) return false;
    UniqueFd fd(connectTo(m_socketPath));
    if (!fd) return false;

    const std::vector<uint8_t> packet = encodeHandshakePacket();
    bool result = sendAll(fd.get(), packet.data(), packet.size());
    std::string version;
    uint8_t byte = 0;
    const Deadline deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMilliseconds);
    if (result) {
        for (size_t i = 0; i < 64; ++i) {
            if (!receiveExact(fd.get(), &byte, 1, deadline)) {
                result = false;
                break;
            }
            if (byte == 0) break;
            version.push_back(static_cast<char>(byte));
        }
    }

    uint8_t attributes[sizeof(uint32_t)]{};
    if (result && (version.empty() || version.size() >= 64 ||
                   !receiveExact(fd.get(), attributes, sizeof(attributes), deadline))) {
        result = false;
    }

    if (result) {
        // SET_WINDOW (0x20) advertises set_front_window_fp, used for focus.
        // WINDOW_MOVE and WINDOW_LAYER call SkyLight directly and do not
        // depend on that flag. Still require the complete versioned handshake.
        m_compatible = parseVersion(version);
        // This extension is shipped with the pinned minfwm SA patch only.
        m_transformSupport = version == "2.1.29" && (attributes[0] & 0x80) != 0 &&
            (attributes[1] & 0x01) != 0; // Lifecycle v2 restores the current native baseline.
    }
    return result && m_compatible;
}

bool YabaiSA::sendPacket(const std::vector<uint8_t>& packet, bool explicitAck) const {
    if (packet.size() < 3 || packet.size() > kMaxPacketLength || !isOwnedSocket()) return false;
    UniqueFd fd(connectTo(m_socketPath));
    if (!fd) return false;

    bool result = sendAll(fd.get(), packet.data(), packet.size());
    if (result) {
        // Current Yabai closes the request socket without a payload for these
        // operations. A zero byte is accepted by test doubles as an explicit ACK.
        result = receiveAckOrEof(fd.get(), explicitAck);
    }
    shutdown(fd.get(), SHUT_RDWR);
    return result;
}

bool YabaiSA::moveWindow(uint32_t wid, int x, int y) const {
    return wid != 0 && m_compatible && sendPacket(encodeMovePacket(wid, x, y));
}

bool YabaiSA::setWindowLayer(uint32_t wid, int layer) const {
    return wid != 0 && m_compatible && sendPacket(encodeLayerPacket(wid, layer));
}

YabaiSABackend::YabaiSABackend(std::string socketPath, WindowPositionCheck check)
    : m_sa(std::move(socketPath)), m_checkPosition(std::move(check)) {}

std::vector<uint8_t> YabaiSA::encodeTransformPacket(uint32_t wid, uint32_t ownerPid, int x, int y) {
    std::vector<uint8_t> body{0x14};
    appendU32(body, wid);
    appendU32(body, ownerPid);
    appendI32(body, x);
    appendI32(body, y);
    return finishPacket(std::move(body));
}

std::vector<uint8_t> YabaiSA::encodeResetTransformPacket(uint32_t wid, uint32_t ownerPid) {
    std::vector<uint8_t> body{0x15};
    appendU32(body, wid);
    appendU32(body, ownerPid);
    return finishPacket(std::move(body));
}

bool YabaiSA::transformWindow(uint32_t wid, int x, int y) const {
    return wid && supportsTransforms() &&
        sendPacket(encodeTransformPacket(wid, static_cast<uint32_t>(getpid()), x, y), true);
}

bool YabaiSA::resetTransform(uint32_t wid) const {
    return wid && supportsTransforms() &&
        sendPacket(encodeResetTransformPacket(wid, static_cast<uint32_t>(getpid())), true);
}

YabaiSABackend::~YabaiSABackend() {
    for (uint32_t wid : m_transformed) (void)m_sa.resetTransform(wid);
}

BackendResult YabaiSABackend::resetTransform(uint32_t wid) {
    if (!m_transformed.contains(wid)) return {BackendCode::ok};
    if (!m_sa.resetTransform(wid)) return {BackendCode::failed};
    m_transformed.erase(wid);
    return {BackendCode::ok};
}

bool YabaiSABackend::initialize() {
    return m_sa.handshake();
}

BackendResult YabaiSABackend::move(AXUIElementRef element, uint32_t wid, int x, int y) {
    if (!available()) return {BackendCode::unavailable};
    if (usesTransforms()) {
        if (!wid) return {BackendCode::failed};
        // Track before sending: a lost ACK may follow a successful transform.
        m_transformed.insert(wid);
        const bool applied = m_sa.transformWindow(wid, x, y) && m_checkPosition &&
            m_checkPosition(element, wid, x, y);
        if (!applied) (void)resetTransform(wid);
        return {applied ? BackendCode::ok : BackendCode::failed};
    }
    const bool moved = m_sa.moveWindow(wid, x, y) && m_checkPosition && m_checkPosition(element, wid, x, y);
    return {moved ? BackendCode::ok : BackendCode::failed};
}

BackendResult YabaiSABackend::resize(AXUIElementRef, uint32_t, float, float) {
    return {BackendCode::unsupported};
}

BackendResult YabaiSABackend::moveNative(AXUIElementRef element, uint32_t wid, int x, int y) {
    if (!available() || !wid) return {BackendCode::unavailable};
    // Move the native frame first. Resetting first would expose its old
    // position for one frame before moving the application under the pointer.
    const bool moved = m_sa.moveWindow(wid, x, y);
    const bool reset = resetTransform(wid).succeeded();
    return {moved && reset && m_checkPosition && m_checkPosition(element, wid, x, y) ? BackendCode::ok : BackendCode::failed};
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
