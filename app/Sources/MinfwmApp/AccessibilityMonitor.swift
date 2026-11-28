import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum RequiredPermission: String, CaseIterable, Identifiable {
    case accessibility = "Accessibility"
    case screenRecording = "Screen Recording"

    var id: String { rawValue }
}

@MainActor
final class PermissionsMonitor: ObservableObject {
    @Published private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @Published private(set) var isScreenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()
    @Published private(set) var settingsWindowFrame: CGRect? = nil

    private var timer: Timer?

    var allGranted: Bool {
        isAccessibilityTrusted && isScreenRecordingGranted
    }

    init() {
        refresh()
    }

    func isGranted(_ permission: RequiredPermission) -> Bool {
        switch permission {
        case .accessibility: return isAccessibilityTrusted
        case .screenRecording: return isScreenRecordingGranted
        }
    }

    func startPolling(interval: TimeInterval = 0.35) {
        stopPolling()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        if ax != isAccessibilityTrusted {
            isAccessibilityTrusted = ax
        }

        let screen = CGPreflightScreenCaptureAccess()
        if screen != isScreenRecordingGranted {
            isScreenRecordingGranted = screen
        }

        let frame = Self.findSystemSettingsWindowFrame()
        if frame != settingsWindowFrame {
            settingsWindowFrame = frame
        }
    }

    func openSettings(for permission: RequiredPermission) {
        let urlString: String
        switch permission {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Triggers macOS's ScreenCaptureKit one-time consent prompt during onboarding
    /// so it does not interrupt the user later when overview previews are captured.
    @discardableResult
    func requestScreenCaptureConsent() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    /// Detects Screen Recording access live (even before app restart) by checking whether
    /// another process's on-screen window exposes a non-empty kCGWindowName.
    static func hasLiveScreenRecordingAccess() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for info in infoList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let name = info[kCGWindowName as String] as? String,
                  !name.isEmpty
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Returns the System Settings main window frame in AppKit global screen coordinates (bottom-left origin).
    static func findSystemSettingsWindowFrame() -> CGRect? {
        let settingsPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == "com.apple.systempreferences" }
                .map(\.processIdentifier)
        )
        guard !settingsPIDs.isEmpty else { return nil }

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        guard primaryHeight > 0 else { return nil }

        for info in infoList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  settingsPIDs.contains(pid),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  cgRect.width >= 400,
                  cgRect.height >= 300
            else {
                continue
            }

            // Convert CG top-left origin to AppKit bottom-left origin
            let appKitY = primaryHeight - cgRect.origin.y - cgRect.height
            return CGRect(x: cgRect.origin.x, y: appKitY, width: cgRect.width, height: cgRect.height)
        }
        return nil
    }
}
