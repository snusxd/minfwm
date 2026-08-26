#pragma once

#include "WindowBackend.hpp"
#include <cstdint>
#include <string>
#include <vector>

namespace minfwm {

class YabaiSA {
public:
    struct Handshake {
        std::string version;
        uint32_t attributes = 0;
    };

    explicit YabaiSA(std::string socketPath = {});

    bool handshake();
    bool compatible() const { return m_compatible; }

    bool moveWindow(uint32_t wid, int x, int y) const;
    bool setWindowLayer(uint32_t wid, int layer) const;

    static std::vector<uint8_t> encodeMovePacket(uint32_t wid, int x, int y);
    static std::vector<uint8_t> encodeLayerPacket(uint32_t wid, int layer);
    static std::vector<uint8_t> encodeHandshakePacket();

private:
    bool sendPacket(const std::vector<uint8_t>& packet) const;
    bool isOwnedSocket() const;

    std::string m_socketPath;
    bool m_compatible = false;
};

class YabaiSABackend final : public WindowBackend {
public:
    explicit YabaiSABackend(std::string socketPath = {});

    bool initialize();
    bool available() const { return m_sa.compatible(); }

    BackendResult move(AXUIElementRef element, uint32_t wid, int x, int y) override;
    BackendResult resize(AXUIElementRef element, uint32_t wid, float width, float height) override;
    BackendResult setLayer(AXUIElementRef element, uint32_t wid, int layer) override;
    BackendResult setHidden(AXUIElementRef element, uint32_t wid, bool hidden) override;
    BackendResult restore(AXUIElementRef element, uint32_t wid, int x, int y,
                          float width, float height) override;

private:
    YabaiSA m_sa;
};

} // namespace minfwm
