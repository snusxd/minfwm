import AppKit
import SwiftUI

enum OnboardingPhase: Equatable {
    case welcome
    case granting(RequiredPermission)
    case completed
}

struct OnboardingView: View {
    @ObservedObject var monitor: PermissionsMonitor
    let onFinish: () -> Void

    @State private var phase: OnboardingPhase = .welcome
    @State private var showingCheckmark = false
    @State private var isHoveringIcon = false
    @State private var isAnimatingWindowMove = false
    @State private var didPositionNextToSettings = false
    @State private var iconScreenCenter: CGPoint? = nil

    private let onboardingInProgressKey = "onboardingInProgress"

    var body: some View {
        Group {
            switch phase {
            case .welcome:
                welcomeCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            case .granting(let permission):
                grantingCard(for: permission)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .completed:
                completedCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background(.ultraThinMaterial)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: phase)
        .onAppear {
            monitor.startPolling()
            restoreSavedProgressIfNeeded()
        }
        .onDisappear {
            monitor.stopPolling()
            ScreenDragOverlayController.shared.hide()
        }
        .onChange(of: monitor.isAccessibilityTrusted) { _, _ in
            handlePermissionUpdate()
        }
        .onChange(of: monitor.isScreenRecordingGranted) { _, _ in
            handlePermissionUpdate()
        }
        .onChange(of: monitor.settingsWindowFrame) { _, newFrame in
            if let settingsFrame = newFrame, case .granting = phase, !didPositionNextToSettings {
                didPositionNextToSettings = true
                positionWindowBesideSettings(settingsFrame)
            } else {
                syncOverlay()
            }
        }
        .onChange(of: isHoveringIcon) { _, _ in
            syncOverlay()
        }
        .onChange(of: showingCheckmark) { _, _ in
            syncOverlay()
        }
        .onChange(of: iconScreenCenter) { _, _ in
            syncOverlay()
        }
    }

    // Screen 1: Compact welcome card
    private var welcomeCard: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 108, height: 108)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)

            Text("minfWM")
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            Button {
                startGrantFlow()
            } label: {
                Text("Grant Permissions")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(width: 280)
    }

    // Screen 2: Draggable icon + single sliding permission title
    private func grantingCard(for permission: RequiredPermission) -> some View {
        VStack(spacing: 18) {
            DraggableAppIconView(
                isGranted: showingCheckmark,
                isHovering: $isHoveringIcon
            ) { center in
                iconScreenCenter = center
            }

            // Permission title container with left-out / right-in slide transition
            ZStack {
                HStack(spacing: 8) {
                    if showingCheckmark {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(permission.rawValue)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                .id(permission)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
            }
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .clipped()
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: permission)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingCheckmark)

            Text(showingCheckmark ? "Granted" : "Drag icon into System Settings")
                .font(.caption)
                .foregroundStyle(showingCheckmark ? .green : .secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
        .frame(width: 280)
    }

    // Screen 3: All permissions granted — auto-closes after 2 seconds
    private var completedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: phase)

            Text("All done")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .frame(width: 280)
        .onAppear {
            UserDefaults.standard.set(false, forKey: onboardingInProgressKey)
            ScreenDragOverlayController.shared.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if phase == .completed {
                    onFinish()
                }
            }
        }
    }

    /// Checks permission state on appear:
    /// - If returning from a restart during onboarding and all permissions are now granted:
    ///   play the Screen Recording checkmark celebration -> "All done" -> auto-open Settings.
    /// - If all permissions are already granted on a normal launch:
    ///   skip onboarding immediately and open Settings.
    private func restoreSavedProgressIfNeeded() {
        monitor.refresh()
        let wasInProgress = UserDefaults.standard.bool(forKey: onboardingInProgressKey)

        if monitor.allGranted {
            if wasInProgress {
                phase = .granting(.screenRecording)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showingCheckmark = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showingCheckmark = false
                        UserDefaults.standard.set(false, forKey: onboardingInProgressKey)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            phase = .completed
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    onFinish()
                }
            }
        } else if wasInProgress, let next = nextPendingPermission() {
            phase = .granting(next)
            monitor.openSettings(for: next)
        }
    }

    private func startGrantFlow() {
        UserDefaults.standard.set(true, forKey: onboardingInProgressKey)

        guard let permission = nextPendingPermission() else {
            UserDefaults.standard.set(false, forKey: onboardingInProgressKey)
            phase = .completed
            return
        }

        didPositionNextToSettings = false
        phase = .granting(permission)
        monitor.openSettings(for: permission)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            monitor.refresh()
            if let settingsFrame = monitor.settingsWindowFrame, !didPositionNextToSettings {
                didPositionNextToSettings = true
                positionWindowBesideSettings(settingsFrame)
            } else {
                syncOverlay()
            }
        }
    }

    private func nextPendingPermission() -> RequiredPermission? {
        if !monitor.isAccessibilityTrusted { return .accessibility }
        if !monitor.isScreenRecordingGranted { return .screenRecording }
        return nil
    }

    private func handlePermissionUpdate() {
        guard case .granting(let current) = phase,
              !showingCheckmark,
              monitor.isGranted(current)
        else {
            return
        }

        // 1. Show checkmark celebration
        showingCheckmark = true
        ScreenDragOverlayController.shared.hide()

        // 2. Slide to next permission (or completed) after brief pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showingCheckmark = false
            if let next = nextPendingPermission() {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    phase = .granting(next)
                }
                monitor.openSettings(for: next)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    monitor.refresh()
                    syncOverlay()
                }
            } else {
                UserDefaults.standard.set(false, forKey: onboardingInProgressKey)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    phase = .completed
                }
            }
        }
    }

    private func onboardingWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.identifier?.rawValue == "onboarding" || $0.title == "minfWM"
        }
    }

    private func positionWindowBesideSettings(_ settingsFrame: CGRect) {
        guard let window = onboardingWindow(),
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(settingsFrame) }) ?? NSScreen.main
        else {
            return
        }

        let gap: CGFloat = 24
        let winSize = window.frame.size
        let visible = screen.visibleFrame

        // Prefer placing our card to the left of System Settings; fall back to the right
        var targetX = settingsFrame.minX - winSize.width - gap
        if targetX < visible.minX + 12 {
            targetX = min(settingsFrame.maxX + gap, visible.maxX - winSize.width - 12)
        }
        let targetY = min(
            max(settingsFrame.midY - winSize.height / 2, visible.minY + 12),
            visible.maxY - winSize.height - 12
        )

        let oldOrigin = window.frame.origin
        let targetFrame = CGRect(origin: CGPoint(x: targetX, y: targetY), size: winSize)

        isAnimatingWindowMove = true
        ScreenDragOverlayController.shared.hide()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                isAnimatingWindowMove = false
                if let current = iconScreenCenter {
                    iconScreenCenter = CGPoint(
                        x: current.x + (targetFrame.origin.x - oldOrigin.x),
                        y: current.y + (targetFrame.origin.y - oldOrigin.y)
                    )
                }
                syncOverlay()
            }
        }
    }

    private func syncOverlay() {
        guard case .granting = phase,
              !showingCheckmark,
              !isHoveringIcon,
              !isAnimatingWindowMove,
              let window = onboardingWindow(),
              let settingsFrame = monitor.settingsWindowFrame
        else {
            ScreenDragOverlayController.shared.hide()
            return
        }

        let startScreen = iconScreenCenter ?? CGPoint(
            x: window.frame.midX,
            y: window.frame.maxY - 90
        )

        // Target point inside System Settings' right-hand permission list
        let endScreen = CGPoint(
            x: settingsFrame.minX + settingsFrame.width * 0.65,
            y: settingsFrame.minY + settingsFrame.height * 0.52
        )

        ScreenDragOverlayController.shared.update(
            startScreenPoint: startScreen,
            endScreenPoint: endScreen,
            active: true
        )
    }
}
