#import <Foundation/Foundation.h>

#include "YabaiSA.hpp"
#include "WindowRenderer.hpp"

#include <cerrno>
#include <chrono>
#include <cstring>
#include <iostream>
#include <limits>
#include <poll.h>
#include <thread>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>

namespace {

int failures = 0;

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void expect(const std::vector<std::uint8_t>& actual,
            std::initializer_list<std::uint8_t> expected,
            const char* message) {
    if (actual != std::vector<std::uint8_t>(expected)) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

bool readExact(int fd, void* buffer, size_t length) {
    auto* bytes = static_cast<std::uint8_t*>(buffer);
    size_t offset = 0;
    while (offset < length) {
        const ssize_t received = ::read(fd, bytes + offset, length - offset);
        if (received > 0) {
            offset += static_cast<size_t>(received);
            continue;
        }
        if (received < 0 && errno == EINTR) continue;
        return false;
    }
    return true;
}

bool writeAll(int fd, const void* buffer, size_t length) {
    const auto* bytes = static_cast<const std::uint8_t*>(buffer);
    size_t offset = 0;
    while (offset < length) {
        const ssize_t written = ::write(fd, bytes + offset, length - offset);
        if (written > 0) {
            offset += static_cast<size_t>(written);
            continue;
        }
        if (written < 0 && errno == EINTR) continue;
        return false;
    }
    return true;
}

class FakeSAServer final {
public:
    FakeSAServer(bool invalidAck, bool delayAck, uint32_t attributes = 0x20,
                 bool eofAck = false, std::string version = "2.1.29", bool truncated = false,
                 int commands = 1) {
        char pathTemplate[] = "/tmp/minfwm-sa-test-XXXXXX";
        const int placeholder = ::mkstemp(pathTemplate);
        if (placeholder == -1) return;
        ::close(placeholder);
        ::unlink(pathTemplate);
        m_path = pathTemplate;

        m_listenFd = ::socket(AF_UNIX, SOCK_STREAM, 0);
        if (m_listenFd == -1) return;

        sockaddr_un address{};
        address.sun_family = AF_UNIX;
        std::strncpy(address.sun_path, m_path.c_str(), sizeof(address.sun_path) - 1);
        if (::bind(m_listenFd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == -1 ||
            ::chmod(m_path.c_str(), S_IRUSR | S_IWUSR) == -1 ||
            ::listen(m_listenFd, 2) == -1) {
            ::close(m_listenFd);
            m_listenFd = -1;
            ::unlink(m_path.c_str());
            return;
        }

        m_worker = std::thread([this, invalidAck, delayAck, attributes, eofAck, version, truncated, commands] {
            int handshakeFd = ::accept(m_listenFd, nullptr, nullptr);
            if (handshakeFd == -1) return;

            std::uint8_t handshakeRequest[3]{};
            const bool requestReceived = readExact(handshakeFd, handshakeRequest, sizeof(handshakeRequest));
            std::vector<uint8_t> response(version.begin(), version.end());
            response.push_back(0);
            for (unsigned shift = 0; shift < 32; shift += 8) {
                response.push_back(static_cast<uint8_t>(attributes >> shift));
            }
            if (truncated) response.pop_back();
            if (requestReceived) writeAll(handshakeFd, response.data(), response.size());
            ::close(handshakeFd);

            // A rejected handshake must not leave a test blocked in accept().
            for (int command = 0; command < commands; ++command) {
            pollfd listener{m_listenFd, POLLIN, 0};
            if (::poll(&listener, 1, 500) <= 0) return;
            int commandFd = ::accept(m_listenFd, nullptr, nullptr);
            if (commandFd == -1) return;
            std::uint8_t lengthBytes[2]{};
            if (readExact(commandFd, lengthBytes, sizeof(lengthBytes))) {
                const size_t payloadLength = static_cast<size_t>(lengthBytes[0]) |
                                             (static_cast<size_t>(lengthBytes[1]) << 8U);
                std::vector<std::uint8_t> payload(payloadLength);
                if (!payload.empty()) readExact(commandFd, payload.data(), payload.size());
                if (delayAck) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(250));
                } else if (!eofAck) {
                    const std::uint8_t ack = invalidAck ? 1 : 0;
                    writeAll(commandFd, &ack, sizeof(ack));
                }
            }
            ::close(commandFd);
            }
        });
    }

    ~FakeSAServer() {
        if (m_worker.joinable()) m_worker.join();
        if (m_listenFd != -1) ::close(m_listenFd);
        if (!m_path.empty()) ::unlink(m_path.c_str());
    }

    FakeSAServer(const FakeSAServer&) = delete;
    FakeSAServer& operator=(const FakeSAServer&) = delete;

    [[nodiscard]] bool ready() const { return m_listenFd != -1; }
    [[nodiscard]] const std::string& path() const { return m_path; }

private:
    int m_listenFd = -1;
    std::string m_path;
    std::thread m_worker;
};

void testMovementWithoutFocusCapability() {
    {
        FakeSAServer server(false, false, 0, true);
        minfwm::YabaiSA sa(server.path());
        const bool ready = sa.handshake();
        expect(ready, "SA movement does not require the SET_WINDOW focus flag");
        if (ready) expect(sa.moveWindow(42, -100, -200), "zero-flag SA accepts negative coordinates and EOF");
    }
    {
        FakeSAServer server(false, false, 0, true);
        minfwm::YabaiSA sa(server.path());
        const bool ready = sa.handshake();
        expect(ready, "SA layering does not require the SET_WINDOW focus flag");
        if (ready) expect(sa.setWindowLayer(42, 11), "zero-flag SA can send layer commands");
    }
    for (const std::string version : {"3.1.29", "2.invalid", "2.", "2.1.29garbage"}) {
        FakeSAServer server(false, false, 0x20, false, version);
        minfwm::YabaiSA sa(server.path());
        expect(!sa.handshake() && !sa.compatible(), "unknown or malformed versions remain unavailable");
    }
    FakeSAServer truncated(false, false, 0, false, "2.1.29", true);
    minfwm::YabaiSA sa(truncated.path());
    expect(!sa.handshake() && !sa.compatible(), "zero flags do not bypass validation of truncated handshakes");
}

class FallbackBackend final : public minfwm::WindowBackend {
public:
    int moveCalls = 0;
    minfwm::BackendResult move(AXUIElementRef, uint32_t, int x, int y) override {
        ++moveCalls;
        return {x == 100 && y == -200 ? minfwm::BackendCode::ok : minfwm::BackendCode::failed};
    }
    minfwm::BackendResult resize(AXUIElementRef, uint32_t, float, float) override {
        return {minfwm::BackendCode::unsupported};
    }
    minfwm::BackendResult setLayer(AXUIElementRef, uint32_t, int) override {
        return {minfwm::BackendCode::unsupported};
    }
    minfwm::BackendResult setHidden(AXUIElementRef, uint32_t, bool) override {
        return {minfwm::BackendCode::unsupported};
    }
};

void testVerifiedMoveAndFallback() {
    for (const bool actualPositionMatches : {false, true}) {
        FakeSAServer server(false, false, 0, true);
        int checks = 0;
        minfwm::YabaiSABackend sa(server.path(), [&](AXUIElementRef, uint32_t wid, int x, int y) {
            ++checks;
            expect(wid == 42 && x == 100 && y == -200, "verification uses the commanded WID and negative target");
            return actualPositionMatches;
        });
        expect(sa.initialize(), "zero-flag handshake enables verified backend");
        FallbackBackend ax;
        minfwm::WindowRenderer renderer(ax, sa);
        minfwm::ClientWindow window(nullptr, 42);
        window.originalPhysicalRect = minfwm::core::Rect{100, 100, 640, 480};
        window.layerAttempted = true;
        expect(renderer.render(window, {100, -200, 640, 480}, 1).succeeded(), "verified move or AX fallback succeeds");
        expect(checks == 1, "EOF is followed by actual-position verification");
        expect(ax.moveCalls == (actualPositionMatches ? 0 : 1), "unapplied SA command reaches AX fallback");
    }
    FakeSAServer server(true, false, 0);
    int checks = 0;
    minfwm::YabaiSABackend sa(server.path(), [&](AXUIElementRef, uint32_t, int, int) {
        ++checks;
        return true;
    });
    expect(sa.initialize(), "invalid-ACK backend handshakes first");
    expect(!sa.move(nullptr, 42, 100, -200).succeeded() && checks == 0,
           "position readback cannot turn an invalid ACK into success");

    expect(minfwm::windowPositionMatches({-100, -200}, -100, -200), "negative origins match without clamping");
    expect(minfwm::windowPositionMatches({100.25, -199.75}, 100, -200), "subpoint rounding is tolerated");
    expect(!minfwm::windowPositionMatches({100, 25}, 100, -200), "menu-bar-clamped position is rejected");
    expect(!minfwm::windowPositionMatches({100, -199}, 100, -200), "one-point displacement is rejected");
    expect(!minfwm::windowPositionMatches({std::numeric_limits<double>::quiet_NaN(), -200}, 100, -200),
           "non-finite positions are rejected");
}

void testInvalidAckAndTimeout() {
    {
        FakeSAServer server(true, false);
        expect(server.ready(), "invalid-ACK fake server starts");
        if (server.ready()) {
            minfwm::YabaiSA sa(server.path());
            const bool handshaken = sa.handshake();
            expect(handshaken, "fake handshake enables SA backend");
            if (handshaken) expect(!sa.moveWindow(42, 100, 200), "invalid ACK rejects SA move");
        }
    }

    {
        FakeSAServer server(false, true);
        expect(server.ready(), "timeout fake server starts");
        if (server.ready()) {
            minfwm::YabaiSA sa(server.path());
            const bool handshaken = sa.handshake();
            expect(handshaken, "timeout fake handshake enables SA backend");
            if (handshaken) expect(!sa.moveWindow(42, 100, 200), "SA timeout rejects move");
        }
    }
}

void testAbsoluteTransforms() {
    for (const auto version : {"2.1.30", "2.1.29"}) {
        FakeSAServer server(false, false, 0x80, false, version);
        minfwm::YabaiSA sa(server.path());
        expect(sa.handshake(), "transform capability handshake is complete");
        const bool extension = std::string(version) == "2.1.29";
        expect(sa.supportsTransforms() == extension, "extension requires both exact version and capability");
        if (extension) expect(sa.transformWindow(42, -100, -120), "absolute translation accepts an explicit zero ACK");
        else expect(!sa.transformWindow(42, 0, 0), "stock SA never receives extension commands");
    }
    {
        FakeSAServer server(false, false, 0, false, "2.1.29");
        minfwm::YabaiSA sa(server.path());
        expect(sa.handshake() && !sa.supportsTransforms(), "version alone cannot enable transforms");
    }
    {
        FakeSAServer server(false, false, 0x80, true, "2.1.29");
        minfwm::YabaiSA sa(server.path());
        expect(sa.handshake() && !sa.transformWindow(42, 0, -120), "EOF cannot acknowledge an absolute transform");
    }
    {
        FakeSAServer server(false, false, 0x80, false, "2.1.29", false, 3);
        minfwm::YabaiSABackend sa(server.path(), [](AXUIElementRef, uint32_t, int, int) { return true; });
        expect(sa.initialize() && sa.usesTransforms(), "backend selects translation instead of physical movement");
        expect(sa.move(nullptr, 42, 10, -120).succeeded(), "first absolute target applies");
        expect(sa.move(nullptr, 42, 20, -130).succeeded(), "second target does not toggle off the transform");
        expect(sa.resetTransform(42).succeeded() && sa.resetTransform(42).succeeded(), "reset is idempotent without a duplicate packet");
    }
    {
        FakeSAServer server(false, false, 0x80, false, "2.1.29", false, 2);
        minfwm::YabaiSABackend sa(server.path(), [](AXUIElementRef, uint32_t, int, int) { return false; });
        expect(sa.initialize(), "failed readback test enables transform backend");
        FallbackBackend ax;
        minfwm::WindowRenderer renderer(ax, sa);
        minfwm::ClientWindow window(nullptr, 42);
        window.originalPhysicalRect = minfwm::core::Rect{100, 100, 640, 480};
        window.layerAttempted = true;
        expect(renderer.render(window, {100, -200, 640, 480}, 1).succeeded() && ax.moveCalls == 1,
               "failed transform is reset before AX fallback");
    }
}

} // namespace

int main() {
    @autoreleasepool {
        expect(minfwm::YabaiSA::encodeMovePacket(0x12345678, 100, -20),
               {0x0d, 0x00, 0x06, 0x78, 0x56, 0x34, 0x12,
                0x64, 0x00, 0x00, 0x00, 0xec, 0xff, 0xff, 0xff},
               "move packet uses opcode 0x06 and int32 coordinates");
        expect(minfwm::YabaiSA::encodeLayerPacket(0x12345678, 11),
               {0x09, 0x00, 0x09, 0x78, 0x56, 0x34, 0x12,
                0x0b, 0x00, 0x00, 0x00},
               "layer packet uses opcode 0x09");
        expect(minfwm::YabaiSA::encodeLayerPacket(0x12345678, kCGNormalWindowLevelKey),
               {0x09, 0x00, 0x09, 0x78, 0x56, 0x34, 0x12,
                0x04, 0x00, 0x00, 0x00},
               "normal layer restoration sends the normal-level key rather than the base-level key");
        expect(minfwm::YabaiSA::encodeHandshakePacket(), {0x01, 0x00, 0x01},
               "handshake packet uses current SA framing");
        expect(minfwm::YabaiSA::encodeTransformPacket(42, 123, -100, -120),
               {17, 0, 0x14, 42, 0, 0, 0, 123, 0, 0, 0,
                0x9c, 0xff, 0xff, 0xff, 0x88, 0xff, 0xff, 0xff},
               "absolute transform packet carries window, owner and signed coordinates");
        expect(minfwm::YabaiSA::encodeResetTransformPacket(42, 123),
               {9, 0, 0x15, 42, 0, 0, 0, 123, 0, 0, 0},
               "transform reset carries the owner and is a separate operation");
        testInvalidAckAndTimeout();
        testMovementWithoutFocusCapability();
        testVerifiedMoveAndFallback();
        testAbsoluteTransforms();
    }
    return failures == 0 ? 0 : 1;
}
