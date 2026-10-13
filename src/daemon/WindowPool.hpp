#pragma once

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <cstddef>
#include <cstdint>
#include <vector>
#include <memory>
#include <unordered_map>
#include <optional>

#include "CFRAII.hpp"
#include "Geometry.hpp"

namespace minfwm {

class ClientWindow {
public:
    explicit ClientWindow(AXUIElementRef windowRef);
    ClientWindow(AXUIElementRef windowRef, std::uint32_t windowId);
    ~ClientWindow() noexcept;

    ClientWindow(const ClientWindow&) = delete;
    ClientWindow& operator=(const ClientWindow&) = delete;

    [[nodiscard]] AXUIElementRef ref() const noexcept { return m_windowRef.get(); }
    [[nodiscard]] std::uint32_t wid() const noexcept { return m_wid; }
    [[nodiscard]] pid_t pid() const noexcept { return m_pid; }
    bool captureInitialGeometry();

    VirtualRect virtualRect;
    std::optional<VirtualRect> originalPhysicalRect;
    float lastRenderedX = -99999.0f;
    float lastRenderedY = -99999.0f;
    double lastProgrammaticMoveTime = 0.0;
    double positionVerificationTime = 0.0;
    bool positionNeedsVerification = false;
    bool positionFallbackAttempted = false;
    std::optional<core::Point> rejectedPosition;
    bool isHidden = false;
    bool isAXHidden = false;
    bool needsGeometryRestore = false;
    bool isLayerSet = false;
    bool layerAttempted = false;
    bool virtualCoordinatesInitialized = false;
    bool centerOnAdoption = false;

private:
    CFRef<AXUIElementRef> m_windowRef;
    std::uint32_t m_wid;
    pid_t m_pid = 0;
};

class WindowPool {
public:
    using WindowIdResolver = std::uint32_t (*)(AXUIElementRef);

    explicit WindowPool(WindowIdResolver windowIdResolver = nullptr);

    // Uses the private AX-to-WID lookup only for the optional Yabai backend.
    static WindowIdResolver optionalWindowIdResolver() noexcept;

    WindowPool(const WindowPool&) = delete;
    WindowPool& operator=(const WindowPool&) = delete;

    std::shared_ptr<ClientWindow> addWindow(AXUIElementRef windowRef);
    void removeWindow(AXUIElementRef windowRef);
    void removeWindowsForPid(pid_t pid);

    [[nodiscard]] std::shared_ptr<ClientWindow> findWindowByWID(std::uint32_t wid) const;
    [[nodiscard]] std::shared_ptr<ClientWindow> findWindowByAXRef(AXUIElementRef windowRef) const;

    [[nodiscard]] const std::vector<std::shared_ptr<ClientWindow>>& windows() const noexcept {
        return m_windows;
    }

private:
    struct AXRefHash {
        std::size_t operator()(AXUIElementRef ref) const noexcept;
    };

    struct AXRefEqual {
        bool operator()(AXUIElementRef lhs, AXUIElementRef rhs) const noexcept;
    };

    static std::uint32_t defaultWindowIdResolver(AXUIElementRef windowRef) noexcept;

    WindowIdResolver m_windowIdResolver;
    std::vector<std::shared_ptr<ClientWindow>> m_windows;
    std::unordered_map<std::uint32_t, std::shared_ptr<ClientWindow>> m_windowsByWID;
    std::unordered_map<AXUIElementRef, std::shared_ptr<ClientWindow>, AXRefHash, AXRefEqual> m_windowsByAXRef;
};

} // namespace minfwm
