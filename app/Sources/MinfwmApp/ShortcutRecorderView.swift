import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var keys: [String]
    let superModifiers: [String]
    let modifiersOnly: Bool

    @State private var isRecording = false
    @State private var liveModifiers: [String] = []
    @State private var peakModifiers: [String] = []
    @State private var eventMonitor: Any?

    // Vertical rolling carousel state for idle recording popover
    @State private var carouselIndex = 0
    @State private var carouselTimer: Timer?

    private static let sampleCombos: [[String]] = [
        ["⌘", "⌥", "F"],
        ["⌃", "⇧", "K"],
        ["⌘", "⇧", "Space"],
        ["⌥", "⌃", "Z"],
        ["⌘", "⌥", "✦"],
        ["⇧", "⌥", "R"],
        ["⌃", "⌘", "1"],
        ["⌘", "⌥", "S"],
    ]

    private static let sampleModifierCombos: [[String]] = [
        ["⌘", "⌥"],
        ["⌃", "⌥"],
        ["⌘", "⇧"],
        ["⌃", "⇧"],
        ["⌘", "⌃", "⌥"],
        ["⌥", "⇧"],
    ]

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 5) {
                    if keys.isEmpty {
                        Text("Record")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                            KeycapChip(label: displaySymbol(for: key), active: isRecording)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 112, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isRecording ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.09),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isRecording, arrowEdge: .top) {
                recorderPopover
            }

            if !keys.isEmpty {
                Button {
                    keys = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if !newValue {
                cleanup()
            }
        }
        .onDisappear {
            cleanup()
        }
    }

    private var recorderPopover: some View {
        let combos = modifiersOnly ? Self.sampleModifierCombos : Self.sampleCombos
        let currentSample = combos[carouselIndex % combos.count]

        return VStack(spacing: 8) {
            ZStack {
                if liveModifiers.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(Array(currentSample.enumerated()), id: \.offset) { idx, token in
                            ZStack {
                                KeycapChip(label: token, active: false, large: true, muted: true)
                                    .id("\(carouselIndex)-\(idx)-\(token)")
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)
                                        )
                                    )
                            }
                            .frame(height: 36)
                            .clipped()
                            .animation(
                                .spring(response: 0.44, dampingFraction: 0.62).delay(Double(idx) * 0.085),
                                value: carouselIndex
                            )
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(liveModifiers.enumerated()), id: \.offset) { _, mod in
                            KeycapChip(label: displaySymbol(for: mod), active: true, large: true)
                        }
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(height: 38)

            Text("Recording shortcut")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 196)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: liveModifiers.isEmpty)
    }

    private func startRecording() {
        liveModifiers = []
        peakModifiers = []
        carouselIndex = Int.random(in: 0..<Self.sampleCombos.count)
        isRecording = true

        cleanup()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handle(event: event)
            return nil
        }

        carouselTimer = Timer.scheduledTimer(withTimeInterval: 1.05, repeats: true) { _ in
            Task { @MainActor in
                if liveModifiers.isEmpty {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                        carouselIndex += 1
                    }
                }
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        cleanup()
    }

    private func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        carouselTimer?.invalidate()
        carouselTimer = nil
        liveModifiers = []
        peakModifiers = []
    }

    private func handle(event: NSEvent) {
        if event.type == .keyDown && event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let currentMods = modifierNames(from: event.modifierFlags)

        if event.type == .flagsChanged {
            liveModifiers = currentMods
            if currentMods.count >= peakModifiers.count {
                peakModifiers = currentMods
            }
            if modifiersOnly && currentMods.isEmpty && !peakModifiers.isEmpty {
                keys = collapseSuperIfNeeded(peakModifiers)
                stopRecording()
            }
            return
        }

        if event.type == .keyDown {
            guard !modifiersOnly else { return }
            guard let keyName = keyName(from: event) else { return }
            var combined = collapseSuperIfNeeded(currentMods)
            combined.append(keyName)
            keys = combined
            stopRecording()
        }
    }

    private func collapseSuperIfNeeded(_ mods: [String]) -> [String] {
        guard !superModifiers.isEmpty else { return mods }
        let modSet = Set(mods)
        let superSet = Set(superModifiers)
        if superSet.isSubset(of: modSet) {
            let remaining = mods.filter { !superSet.contains($0) }
            return ["Super"] + remaining
        }
        return mods
    }

    private func modifierNames(from flags: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.command) { result.append("Cmd") }
        if flags.contains(.option) { result.append("Alt") }
        if flags.contains(.control) { result.append("Ctrl") }
        if flags.contains(.shift) { result.append("Shift") }
        return result
    }

    /// Maps hardware keyCode to layout-independent English key name so Russian layout still records S/F/Z cleanly.
    private func keyName(from event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Backspace"
        case kVK_LeftArrow: return "Left"
        case kVK_RightArrow: return "Right"
        case kVK_UpArrow: return "Up"
        case kVK_DownArrow: return "Down"
        default:
            guard let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !chars.isEmpty
            else {
                return nil
            }
            return chars.uppercased()
        }
    }

    private func displaySymbol(for token: String) -> String {
        switch token {
        case "Cmd": return "⌘"
        case "Alt": return "⌥"
        case "Ctrl": return "⌃"
        case "Shift": return "⇧"
        default: return token
        }
    }
}

private struct KeycapChip: View {
    let label: String
    var active: Bool = false
    var large: Bool = false
    var muted: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: large ? 15 : 12, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? Color.accentColor : (muted ? Color.secondary.opacity(0.65) : Color.primary))
            .padding(.horizontal, large ? 10 : 7)
            .padding(.vertical, large ? 6 : 3)
            .background(
                RoundedRectangle(cornerRadius: large ? 7 : 5)
                    .fill(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(muted ? 0.045 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: large ? 7 : 5)
                    .strokeBorder(active ? Color.accentColor.opacity(0.45) : Color.primary.opacity(muted ? 0.07 : 0.12), lineWidth: 1)
            )
    }
}
