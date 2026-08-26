#import <Foundation/Foundation.h>

#include "YabaiSA.hpp"

#include <cerrno>
#include <chrono>
#include <cstring>
#include <iostream>
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
    FakeSAServer(bool invalidAck, bool delayAck) {
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

        m_worker = std::thread([this, invalidAck, delayAck] {
            int handshakeFd = ::accept(m_listenFd, nullptr, nullptr);
            if (handshakeFd == -1) return;

            std::uint8_t handshakeRequest[3]{};
            const bool requestReceived = readExact(handshakeFd, handshakeRequest, sizeof(handshakeRequest));
            const std::uint8_t handshakeResponse[] = {
                '2', '.', '1', '.', '3', '0', 0, 0x20, 0, 0, 0
            };
            if (requestReceived) writeAll(handshakeFd, handshakeResponse, sizeof(handshakeResponse));
            ::close(handshakeFd);

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
                } else {
                    const std::uint8_t ack = invalidAck ? 1 : 0;
                    writeAll(commandFd, &ack, sizeof(ack));
                }
            }
            ::close(commandFd);
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
        expect(minfwm::YabaiSA::encodeHandshakePacket(), {0x01, 0x00, 0x01},
               "handshake packet uses current SA framing");
        testInvalidAckAndTimeout();
    }
    return failures == 0 ? 0 : 1;
}
