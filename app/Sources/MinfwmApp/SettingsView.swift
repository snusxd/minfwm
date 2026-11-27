import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case permissions = "Permissions"
    case window = "Window"
    case zoom = "Zoom"
    case camera = "Camera"
    case snap = "Snap"
    case display = "Display"
    case bookmarks = "Bookmarks"
    case pins = "Pins"
    case animations = "Animations"
    case keybinds = "Keybinds"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .permissions: return "lock.shield.fill"
        case .window: return "macwindow"
        case .zoom: return "magnifyingglass"
        case .camera: return "video.fill"
        case .snap: return "rectangle.inset.filled.and.person.filled"
        case .display: return "display.2"
        case .bookmarks: return "bookmark.fill"
        case .pins: return "pin.fill"
        case .animations: return "sparkles"
        case .keybinds: return "command"
        }
    }

    var badgeColor: Color {
        switch self {
        case .general: return .gray
        case .permissions: return .teal
        case .window: return .blue
        case .zoom: return .purple
        case .camera: return .indigo
        case .snap: return .orange
        case .display: return .cyan
        case .bookmarks: return .pink
        case .pins: return .red
        case .animations: return .yellow
        case .keybinds: return .mint
        }
    }

    static var generalSections: [SettingsSection] {
        [.general, .permissions, .keybinds]
    }

    static var configSections: [SettingsSection] {
        [.window, .zoom, .camera, .snap, .display, .bookmarks, .pins, .animations]
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var monitor: PermissionsMonitor
    let onOpenOnboarding: () -> Void

    @State private var selectedSection: SettingsSection = .general
    @State private var searchText = ""

    private var filteredConfigSections: [SettingsSection] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return SettingsSection.configSections
        }
        return SettingsSection.configSections.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("General") {
                    ForEach(SettingsSection.generalSections.filter {
                        searchText.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(searchText)
                    }) { section in
                        sidebarRow(section)
                            .tag(section)
                    }
                }

                Section("Configuration") {
                    ForEach(filteredConfigSections) { section in
                        sidebarRow(section)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailContent(for: selectedSection)
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle(selectedSection.rawValue)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: store.config) { _, _ in
            store.saveAndReload()
        }
        .onAppear {
            store.load()
            store.refreshServiceStatus()
            monitor.refresh()
        }
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(section.badgeColor.gradient, in: RoundedRectangle(cornerRadius: 6))

            Text(section.rawValue)
                .font(.body)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func detailContent(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            generalSection
        case .permissions:
            permissionsSection
        case .window:
            windowSection
        case .zoom:
            zoomSection
        case .camera:
            cameraSection
        case .snap:
            snapSection
        case .display:
            displaySection
        case .bookmarks:
            bookmarksSection
        case .pins:
            pinsSection
        case .animations:
            animationsSection
        case .keybinds:
            keybindsSection
        }
    }

    // MARK: - General
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Service") {
                SettingsRow(
                    title: "Start service",
                    subtitle: store.isServiceRunning ? "minfwm service is running" : "Start the minfwm background service"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.isServiceRunning },
                        set: { _ in store.toggleService() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                if let error = store.statusMessage {
                    SoftDivider()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            }

            SettingsCard(title: "General") {
                SettingsRow(
                    title: "Configuration file",
                    subtitle: store.configURL.path
                ) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Permissions
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionCard(
                title: "Accessibility",
                icon: "figure.stand",
                color: .indigo,
                isGranted: monitor.isAccessibilityTrusted
            ) {
                monitor.openSettings(for: .accessibility)
            }

            permissionCard(
                title: "Screen Recording",
                icon: "record.circle",
                color: .teal,
                isGranted: monitor.isScreenRecordingGranted
            ) {
                monitor.openSettings(for: .screenRecording)
            }
        }
    }

    private func permissionCard(
        title: String,
        icon: String,
        color: Color,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        SettingsCard(title: title) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.body.weight(.medium))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "questionmark.circle.fill")
                        .foregroundStyle(isGranted ? .green : .secondary)
                    Text(isGranted ? "Granted" : "Not granted")
                        .font(.callout)
                        .foregroundStyle(isGranted ? .green : .secondary)
                }

                Button(isGranted ? "Open..." : "Grant Access...", action: action)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - [window]
    private var windowSection: some View {
        SettingsCard(title: "Window") {
            SettingsRow(title: "Enable window shadows", subtitle: "Keep macOS drop shadows on managed windows") {
                Toggle("", isOn: $store.config.enableWindowShadows).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Overscan buffer (px)", subtitle: "Off-screen buffer around the viewport") {
                Stepper("\(store.config.overscanBufferPx) px", value: $store.config.overscanBufferPx, in: 0...4000, step: 50)
            }
            SoftDivider()
            SettingsRow(title: "Spawn behavior", subtitle: "Where newly opened windows appear") {
                Picker("", selection: $store.config.spawnBehavior) {
                    Text("Center").tag("center")
                    Text("Mouse").tag("mouse")
                    Text("Native").tag("native")
                }
                .labelsHidden()
                .frame(width: 130)
            }
            SoftDivider()
            SettingsRow(title: "Whitelist", subtitle: "Comma-separated app names excluded from management") {
                SoftTextField(placeholder: "Terminal, Music", text: arrayBinding($store.config.whitelist), width: 220)
            }
        }
    }

    // MARK: - [zoom]
    private var zoomSection: some View {
        SettingsCard(title: "Zoom") {
            SettingsRow(title: "Invert zoom scroll direction", subtitle: "Reverse Super + wheel zoom without affecting normal scrolling") {
                Toggle("", isOn: $store.config.invertZoomScrollDirection).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Invert trackpad pinch zoom", subtitle: "Reverse four-finger trackpad pinch zoom independently") {
                Toggle("", isOn: $store.config.trackInvertZoomDirection).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Rewind on focus", subtitle: "Return to 100% scale and center on a clicked window") {
                Toggle("", isOn: $store.config.rewindOnFocus).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Overview previews", subtitle: "Render static previews for distant windows (requires Screen Recording)") {
                Toggle("", isOn: $store.config.overviewPreviews).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Escape anchor while zoomed", subtitle: "Where Escape centers the camera when exiting overview") {
                Picker("", selection: $store.config.zoomedEscCenter) {
                    Text("Screen").tag("screen")
                    Text("Mouse").tag("mouse")
                    Text("Focus").tag("focus")
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    // MARK: - [camera]
    private var cameraSection: some View {
        SettingsCard(title: "Camera") {
            SettingsRow(title: "Center on Cmd+Tab", subtitle: "Center the camera on the active app's focused window") {
                Toggle("", isOn: $store.config.centerOnCmdTab).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Mouse movement multiplier", subtitle: "2.0 is twice as fast; 0.5 is half speed") {
                HStack(spacing: 10) {
                    Slider(value: roundedBinding($store.config.mouseMovementMultiplier, step: 0.1), in: 0.2...4.0)
                        .frame(width: 140)
                    Text(String(format: "%.1fx", store.config.mouseMovementMultiplier))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            SoftDivider()
            SettingsRow(title: "Trackpad movement multiplier", subtitle: "Scale camera panning for three-finger trackpad gestures") {
                HStack(spacing: 10) {
                    Slider(value: roundedBinding($store.config.trackpadMovementMultiplier, step: 0.1), in: 0.2...4.0)
                        .frame(width: 140)
                    Text(String(format: "%.1fx", store.config.trackpadMovementMultiplier))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            SoftDivider()
            SettingsRow(title: "Invert trackpad X axis") {
                Toggle("", isOn: $store.config.trackpadInvertX).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Invert trackpad Y axis") {
                Toggle("", isOn: $store.config.trackpadInvertY).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: - [snap]
    private var snapSection: some View {
        SettingsCard(title: "Snap") {
            SettingsRow(title: "Enable snapping", subtitle: "Ease toward a nearby near-fullscreen window after panning ends") {
                Toggle("", isOn: $store.config.snapEnable).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Threshold (pt)", subtitle: "Maximum edge distance in physical display points (0–1000)") {
                Stepper("\(store.config.snapThreshold) pt", value: $store.config.snapThreshold, in: 0...1000, step: 4)
            }
            SoftDivider()
            SettingsRow(title: "Vertical tuning", subtitle: "Where the window lands vertically inside the viewport") {
                Picker("", selection: $store.config.snapVerticalTuning) {
                    Text("Auto").tag("auto")
                    Text("Top").tag("top")
                    Text("Center").tag("center")
                    Text("Bottom").tag("bottom")
                }
                .labelsHidden()
                .frame(width: 130)
            }
            SoftDivider()
            SettingsRow(title: "Horizontal tuning", subtitle: "Where the window lands horizontally inside the viewport") {
                Picker("", selection: $store.config.snapHorizontalTuning) {
                    Text("Auto").tag("auto")
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    // MARK: - [display]
    private var displaySection: some View {
        SettingsCard(title: "Display") {
            SettingsRow(title: "Multi-display mode", subtitle: "How workspaces behave across multiple monitors") {
                Picker("", selection: $store.config.multiDisplayMode) {
                    Text("Isolated").tag("isolated")
                    Text("Unified").tag("unified")
                }
                .labelsHidden()
                .frame(width: 130)
            }
            SoftDivider()
            SettingsRow(title: "Ignored displays", subtitle: "Comma-separated display IDs or names to ignore") {
                SoftTextField(placeholder: "None", text: arrayBinding($store.config.ignoredDisplays), width: 220)
            }
        }
    }

    // MARK: - [bookmarks]
    private var bookmarksSection: some View {
        SettingsCard(title: "Bookmarks") {
            SettingsRow(title: "Save focus", subtitle: "Save focused window with each bookmark and restore it when jumping") {
                Toggle("", isOn: $store.config.bookmarksSaveFocus).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: - [pins]
    private var pinsSection: some View {
        SettingsCard(title: "Pins") {
            SettingsRow(title: "Always on top", subtitle: "Keep pinned windows floating above regular windows") {
                Toggle("", isOn: $store.config.pinsAlwaysOnTop).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: - [animations]
    private var animationsSection: some View {
        SettingsCard(title: "Animations") {
            SettingsRow(title: "Enable animations", subtitle: "Enable camera, zoom, and window movement animations") {
                Toggle("", isOn: $store.config.animationsEnable).labelsHidden().toggleStyle(.switch)
            }
            SoftDivider()
            SettingsRow(title: "Animation speed", subtitle: "2.0 is twice as fast; 0.5 is half speed (0.1–10.0)") {
                HStack(spacing: 10) {
                    Slider(value: roundedBinding($store.config.animationsSpeed, step: 0.1), in: 0.1...5.0)
                        .frame(width: 140)
                    Text(String(format: "%.1fx", store.config.animationsSpeed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - [keybinds]
    private var keybindsSection: some View {
        VStack(alignment: .trailing, spacing: 14) {
            SettingsCard(title: "Keybinds") {
                keybindRow("Super modifier", binding: $store.config.keybindSuper, modifiersOnly: true, collapseSuper: false)
                SoftDivider()
                keybindRow("Center camera to focus", binding: $store.config.keybindCenterCameraToFocus, modifiersOnly: false)
                SoftDivider()
                keybindRow("Center focus to camera", binding: $store.config.keybindCenterFocusToCamera, modifiersOnly: false)
                SoftDivider()
                keybindRow("Temporarily fullscreen", binding: $store.config.keybindTemporarilyFullscreen, modifiersOnly: false)
                SoftDivider()
                keybindRow("Drag everywhere", binding: $store.config.keybindDragEverywhere, modifiersOnly: true)
                SoftDivider()
                keybindRow("Add bookmark", binding: $store.config.keybindBookmarksAdd, modifiersOnly: true)
                SoftDivider()
                keybindRow("Go to bookmark", binding: $store.config.keybindBookmarksGoto, modifiersOnly: true)
            }

            Button("Restore to Default") {
                let defaults = MinfwmConfig()
                store.config.keybindSuper = defaults.keybindSuper
                store.config.keybindCenterCameraToFocus = defaults.keybindCenterCameraToFocus
                store.config.keybindCenterFocusToCamera = defaults.keybindCenterFocusToCamera
                store.config.keybindTemporarilyFullscreen = defaults.keybindTemporarilyFullscreen
                store.config.keybindDragEverywhere = defaults.keybindDragEverywhere
                store.config.keybindBookmarksAdd = defaults.keybindBookmarksAdd
                store.config.keybindBookmarksGoto = defaults.keybindBookmarksGoto
            }
            .controlSize(.regular)
        }
    }

    private func keybindRow(
        _ title: String,
        binding: Binding<[String]>,
        modifiersOnly: Bool,
        collapseSuper: Bool = true
    ) -> some View {
        SettingsRow(title: title) {
            ShortcutRecorderView(
                keys: binding,
                superModifiers: collapseSuper ? store.config.keybindSuper : [],
                modifiersOnly: modifiersOnly
            )
        }
    }

    private func roundedBinding(_ binding: Binding<Double>, step: Double) -> Binding<Double> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = (newValue / step).rounded() * step
            }
        )
    }

    private func arrayBinding(_ binding: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.joined(separator: ", ") },
            set: { newValue in
                binding.wrappedValue = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

// MARK: - Reusable macOS Settings-style Card, Row, Divider & SoftTextField

private struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

private struct SoftTextField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 200
    var monospaced: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.88))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.042), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
