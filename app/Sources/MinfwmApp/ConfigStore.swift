import AppKit
import Combine
import Foundation

struct MinfwmConfig: Equatable {
    // [window]
    var enableWindowShadows: Bool = false
    var overscanBufferPx: Int = 500
    var whitelist: [String] = ["Terminal", "Music"]
    var spawnBehavior: String = "center"

    // [zoom]
    var invertZoomScrollDirection: Bool = false
    var trackInvertZoomDirection: Bool = false
    var rewindOnFocus: Bool = true
    var overviewPreviews: Bool = true
    var zoomedEscCenter: String = "screen"

    // [camera]
    var centerOnCmdTab: Bool = true
    var mouseMovementMultiplier: Double = 1.0
    var trackpadMovementMultiplier: Double = 1.0
    var trackpadInvertX: Bool = false
    var trackpadInvertY: Bool = false

    // [snap]
    var snapEnable: Bool = true
    var snapThreshold: Int = 32
    var snapVerticalTuning: String = "auto"
    var snapHorizontalTuning: String = "auto"

    // [display]
    var multiDisplayMode: String = "isolated"
    var ignoredDisplays: [String] = []

    // [bookmarks]
    var bookmarksSaveFocus: Bool = true

    // [pins]
    var pinsAlwaysOnTop: Bool = true

    // [animations]
    var animationsEnable: Bool = true
    var animationsSpeed: Double = 1.0

    // [keybinds]
    var keybindSuper: [String] = ["Cmd", "Alt"]
    var keybindCenterCameraToFocus: [String] = ["Super", "F"]
    var keybindCenterFocusToCamera: [String] = ["Super", "S"]
    var keybindTemporarilyFullscreen: [String] = ["Super", "Ctrl", "F"]
    var keybindDragEverywhere: [String] = ["Super", "Ctrl"]
    var keybindBookmarksAdd: [String] = ["Super"]
    var keybindBookmarksGoto: [String] = ["Super", "Shift"]
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config = MinfwmConfig()
    @Published private(set) var isServiceRunning = false
    @Published private(set) var statusMessage: String? = nil

    private var serviceProcess: Process?

    var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/minfwm/minfwm.toml")
    }

    init() {
        load()
        refreshServiceStatus()
    }

    func load() {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return
        }
        config = Self.parseTOML(text)
    }

    func saveAndReload() {
        do {
            let dir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let toml = Self.serializeTOML(config)
            try toml.write(to: configURL, atomically: true, encoding: .utf8)
            if isServiceRunning {
                reloadService()
            }
        } catch {
            statusMessage = "Failed to save config: \(error.localizedDescription)"
        }
    }

    func toggleService() {
        if isServiceRunning {
            stopService()
        } else {
            startService()
        }
    }

    func startService() {
        guard let binary = findMinfwmBinary() else {
            statusMessage = "minfwm binary not found"
            return
        }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["service"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isServiceRunning = false
                self?.serviceProcess = nil
            }
        }

        do {
            try proc.run()
            serviceProcess = proc
            isServiceRunning = true
            statusMessage = nil
        } catch {
            statusMessage = "Could not start service: \(error.localizedDescription)"
        }
    }

    func stopService() {
        if let proc = serviceProcess, proc.isRunning {
            proc.terminate()
            serviceProcess = nil
        } else {
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-f", "minfwm (service|daemon)"]
            try? pkill.run()
            pkill.waitUntilExit()
        }
        isServiceRunning = false
    }

    func reloadService() {
        guard let binary = findMinfwmBinary() else { return }
        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["reload"]
        try? proc.run()
    }

    func refreshServiceStatus() {
        if let proc = serviceProcess, proc.isRunning {
            isServiceRunning = true
            return
        }
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", "minfwm (service|daemon)"]
        try? pgrep.run()
        pgrep.waitUntilExit()
        isServiceRunning = (pgrep.terminationStatus == 0)
    }

    private func findMinfwmBinary() -> URL? {
        let candidates: [URL] = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("minfwm"),
            Bundle.main.resourceURL?.appendingPathComponent("minfwm"),
            URL(fileURLWithPath: "/usr/local/bin/minfwm"),
            URL(fileURLWithPath: "/opt/homebrew/bin/minfwm"),
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Lightweight TOML Parser / Serializer

    static func parseTOML(_ content: String) -> MinfwmConfig {
        var cfg = MinfwmConfig()
        var currentSection = ""

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#"), !value.hasPrefix("\"") {
                value = value[..<hash].trimmingCharacters(in: .whitespaces)
            }

            switch (currentSection, key) {
            case ("window", "enable-window-shadows"): cfg.enableWindowShadows = parseBool(value, cfg.enableWindowShadows)
            case ("window", "overscan-buffer-px"): cfg.overscanBufferPx = Int(value) ?? cfg.overscanBufferPx
            case ("window", "whitelist"): cfg.whitelist = parseStringArray(value)
            case ("window", "spawn-behavior"): cfg.spawnBehavior = parseString(value)

            case ("zoom", "invert-zoom-scroll-direction"): cfg.invertZoomScrollDirection = parseBool(value, cfg.invertZoomScrollDirection)
            case ("zoom", "track-invert-zoom-direction"): cfg.trackInvertZoomDirection = parseBool(value, cfg.trackInvertZoomDirection)
            case ("zoom", "rewind-on-focus"): cfg.rewindOnFocus = parseBool(value, cfg.rewindOnFocus)
            case ("zoom", "overview-previews"): cfg.overviewPreviews = parseBool(value, cfg.overviewPreviews)
            case ("zoom", "zoomed-esc-center"): cfg.zoomedEscCenter = parseString(value)

            case ("camera", "center-on-cmd-tab"): cfg.centerOnCmdTab = parseBool(value, cfg.centerOnCmdTab)
            case ("camera", "mouse-movement-multiplier"): cfg.mouseMovementMultiplier = Double(value) ?? cfg.mouseMovementMultiplier
            case ("camera", "trackpad-movement-multiplier"): cfg.trackpadMovementMultiplier = Double(value) ?? cfg.trackpadMovementMultiplier
            case ("camera", "trackpad-invert-x"): cfg.trackpadInvertX = parseBool(value, cfg.trackpadInvertX)
            case ("camera", "trackpad-invert-y"): cfg.trackpadInvertY = parseBool(value, cfg.trackpadInvertY)

            case ("snap", "enable"): cfg.snapEnable = parseBool(value, cfg.snapEnable)
            case ("snap", "threshold"): cfg.snapThreshold = Int(value) ?? cfg.snapThreshold
            case ("snap", "vertical-tuning"): cfg.snapVerticalTuning = parseString(value)
            case ("snap", "horizontal-tuning"): cfg.snapHorizontalTuning = parseString(value)

            case ("display", "multi-display-mode"): cfg.multiDisplayMode = parseString(value)
            case ("display", "ignored-displays"): cfg.ignoredDisplays = parseStringArray(value)

            case ("bookmarks", "save-focus"): cfg.bookmarksSaveFocus = parseBool(value, cfg.bookmarksSaveFocus)
            case ("pins", "always-on-top"): cfg.pinsAlwaysOnTop = parseBool(value, cfg.pinsAlwaysOnTop)

            case ("animations", "enable"): cfg.animationsEnable = parseBool(value, cfg.animationsEnable)
            case ("animations", "speed"): cfg.animationsSpeed = Double(value) ?? cfg.animationsSpeed

            case ("keybinds", "super"): cfg.keybindSuper = parseStringArray(value)
            case ("keybinds", "center-camera-to-focus"): cfg.keybindCenterCameraToFocus = parseStringArray(value)
            case ("keybinds", "center-focus-to-camera"): cfg.keybindCenterFocusToCamera = parseStringArray(value)
            case ("keybinds", "temporarily-fullscreen"): cfg.keybindTemporarilyFullscreen = parseStringArray(value)
            case ("keybinds", "drag-everywhere"): cfg.keybindDragEverywhere = parseStringArray(value)
            case ("keybinds", "bookmarks-add"): cfg.keybindBookmarksAdd = parseStringArray(value)
            case ("keybinds", "bookmarks-goto"): cfg.keybindBookmarksGoto = parseStringArray(value)
            default: break
            }
        }
        return cfg
    }

    static func serializeTOML(_ c: MinfwmConfig) -> String {
        """
        [window]
        enable-window-shadows = \(c.enableWindowShadows)
        overscan-buffer-px = \(c.overscanBufferPx)
        whitelist = \(formatArray(c.whitelist))
        spawn-behavior = "\(c.spawnBehavior)"

        [zoom]
        invert-zoom-scroll-direction = \(c.invertZoomScrollDirection)
        track-invert-zoom-direction = \(c.trackInvertZoomDirection)
        rewind-on-focus = \(c.rewindOnFocus)
        overview-previews = \(c.overviewPreviews)
        zoomed-esc-center = "\(c.zoomedEscCenter)"

        [camera]
        center-on-cmd-tab = \(c.centerOnCmdTab)
        mouse-movement-multiplier = \(String(format: "%.2f", c.mouseMovementMultiplier))
        trackpad-movement-multiplier = \(String(format: "%.2f", c.trackpadMovementMultiplier))
        trackpad-invert-x = \(c.trackpadInvertX)
        trackpad-invert-y = \(c.trackpadInvertY)

        [snap]
        enable = \(c.snapEnable)
        threshold = \(c.snapThreshold)
        vertical-tuning = "\(c.snapVerticalTuning)"
        horizontal-tuning = "\(c.snapHorizontalTuning)"

        [display]
        multi-display-mode = "\(c.multiDisplayMode)"
        ignored-displays = \(formatArray(c.ignoredDisplays))

        [bookmarks]
        save-focus = \(c.bookmarksSaveFocus)

        [pins]
        always-on-top = \(c.pinsAlwaysOnTop)

        [animations]
        enable = \(c.animationsEnable)
        speed = \(String(format: "%.2f", c.animationsSpeed))

        [keybinds]
        super = \(formatArray(c.keybindSuper))
        center-camera-to-focus = \(formatArray(c.keybindCenterCameraToFocus))
        center-focus-to-camera = \(formatArray(c.keybindCenterFocusToCamera))
        temporarily-fullscreen = \(formatArray(c.keybindTemporarilyFullscreen))
        drag-everywhere = \(formatArray(c.keybindDragEverywhere))
        bookmarks-add = \(formatArray(c.keybindBookmarksAdd))
        bookmarks-goto = \(formatArray(c.keybindBookmarksGoto))
        """
    }

    private static func parseBool(_ s: String, _ fallback: Bool) -> Bool {
        if s == "true" { return true }
        if s == "false" { return false }
        return fallback
    }

    private static func parseString(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    private static func parseStringArray(_ s: String) -> [String] {
        let inner = s.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        if inner.isEmpty { return [] }
        return inner.split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }.filter { !$0.isEmpty }
    }

    private static func formatArray(_ items: [String]) -> String {
        "[" + items.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }
}
