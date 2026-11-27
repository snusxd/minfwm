import AppKit
import SwiftUI

@MainActor
final class ScreenDragOverlayState: ObservableObject {
    @Published var startPoint: CGPoint = .zero
    @Published var endPoint: CGPoint = .zero
    @Published var isActive: Bool = false
    @Published var isVisible: Bool = false
}

@MainActor
final class ScreenDragOverlayController {
    static let shared = ScreenDragOverlayController()

    private var overlayWindow: NSWindow?
    private let state = ScreenDragOverlayState()
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func update(startScreenPoint: CGPoint?, endScreenPoint: CGPoint?, active: Bool) {
        guard active,
              let startScreen = startScreenPoint,
              let endScreen = endScreenPoint,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(startScreen) }) ?? NSScreen.main
        else {
            hide()
            return
        }

        hideWorkItem?.cancel()
        hideWorkItem = nil

        ensureWindow(for: screen)

        // Convert AppKit global bottom-left coordinates into SwiftUI view top-left coordinates within the screen
        let screenFrame = screen.frame
        state.startPoint = CGPoint(
            x: startScreen.x - screenFrame.minX,
            y: screenFrame.maxY - startScreen.y
        )
        state.endPoint = CGPoint(
            x: endScreen.x - screenFrame.minX,
            y: screenFrame.maxY - endScreen.y
        )
        state.isActive = true
        state.isVisible = true
        overlayWindow?.orderFrontRegardless()
    }

    func hide() {
        hideWorkItem?.cancel()
        state.isVisible = false

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.state.isVisible else { return }
                self.state.isActive = false
                self.overlayWindow?.orderOut(nil)
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func ensureWindow(for screen: NSScreen) {
        if let window = overlayWindow {
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: false)
            }
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: ScreenDragOverlayView(state: state))
        overlayWindow = window
    }
}

private struct ScreenDragOverlayView: View {
    @ObservedObject var state: ScreenDragOverlayState
    @State private var phase: Double = 0
    @State private var timer: Timer?

    private var appIconImage: NSImage {
        NSApplication.shared.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    private var arrowCursorImage: NSImage {
        NSCursor.arrow.image
    }

    private var closedHandCursorImage: NSImage {
        NSCursor.closedHand.image
    }

    var body: some View {
        GeometryReader { _ in
            if state.isActive {
                animationLayer
                    .opacity(state.isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: state.isVisible)
            }
        }
        .ignoresSafeArea()
        .onAppear { syncTimer() }
        .onChange(of: state.isActive) { _, _ in syncTimer() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func syncTimer() {
        timer?.invalidate()
        timer = nil
        phase = 0

        guard state.isActive else { return }

        let fps = 60.0
        let duration = 2.6
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { _ in
            Task { @MainActor in
                phase += 1.0 / (fps * duration)
                if phase >= 1.0 {
                    phase = 0
                }
            }
        }
    }

    // 0.00 -> 0.16: cursor approaches icon center
    // 0.16 -> 0.24: cursor grabs icon
    // 0.24 -> 0.74: cursor + ghost icon glide in an arc from startPoint into endPoint (Settings list)
    // 0.74 -> 0.90: release & drop ripple at endPoint
    // 0.90 -> 1.00: pause
    private var animationLayer: some View {
        let t = phase
        let start = state.startPoint
        let end = state.endPoint

        let approach: Double = {
            let r = min(1.0, t / 0.16)
            return 1 - pow(1 - r, 3)
        }()

        let drag: Double = {
            guard t > 0.24 else { return 0 }
            let r = min(1.0, (t - 0.24) / 0.50)
            return r < 0.5 ? 4 * r * r * r : 1 - pow(-2 * r + 2, 3) / 2
        }()

        let isGrabbing = t >= 0.16 && t <= 0.76

        let arcLift: CGFloat = CGFloat(sin(drag * .pi)) * 42.0
        let currentX: CGFloat = t < 0.16
            ? start.x - 28 * CGFloat(1 - approach)
            : start.x + (end.x - start.x) * CGFloat(drag)
        let currentY: CGFloat = t < 0.16
            ? start.y + 32 * CGFloat(1 - approach)
            : start.y + (end.y - start.y) * CGFloat(drag) - arcLift

        let cursorOpacity: Double = {
            if t < 0.06 { return t / 0.06 }
            if t > 0.84 { return max(0, (0.94 - t) / 0.10) }
            return 1.0
        }()

        let ghostOpacity: Double = {
            guard t >= 0.20 else { return 0 }
            if t < 0.28 { return (t - 0.20) / 0.08 * 0.78 }
            if t > 0.74 { return max(0, (0.86 - t) / 0.12 * 0.78) }
            return 0.78
        }()

        // Starts at exact 112x112 (matching the real icon) and gently scales down to 0.84 while dragging
        let ghostScale: CGFloat = 1.0 - CGFloat(drag) * 0.16

        let rippleProgress: Double = {
            guard t >= 0.72 && t <= 0.94 else { return 0 }
            return (t - 0.72) / 0.22
        }()

        return ZStack {
            // Drop target ripple inside System Settings list
            if rippleProgress > 0 {
                Circle()
                    .stroke(Color.accentColor.opacity(1 - rippleProgress), lineWidth: 3)
                    .frame(width: 28 + CGFloat(rippleProgress) * 56, height: 28 + CGFloat(rippleProgress) * 56)
                    .position(end)
            }

            // Ghost dragged app icon (centered exactly on the real icon at start)
            if ghostOpacity > 0.01 {
                Image(nsImage: appIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 112, height: 112)
                    .scaleEffect(ghostScale)
                    .opacity(ghostOpacity)
                    .shadow(color: .black.opacity(0.30), radius: 12, y: 6)
                    .position(x: currentX, y: currentY)
            }

            // Native macOS cursor (arrow -> closed hand when grabbing)
            let cursorImg = isGrabbing ? closedHandCursorImage : arrowCursorImage
            Image(nsImage: cursorImg)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .scaleEffect(t >= 0.16 && t < 0.24 ? 0.90 : 1.0)
                .opacity(cursorOpacity)
                .position(x: currentX + 10, y: currentY + 12)
        }
    }
}
