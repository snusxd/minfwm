import AppKit
import SwiftUI

@main
struct MinfwmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = PermissionsMonitor()
    @StateObject private var configStore = ConfigStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("minfWM", id: "onboarding") {
            OnboardingView(monitor: monitor) {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                NSApplication.shared.windows
                    .first(where: { $0.identifier?.rawValue == "onboarding" || $0.title == "minfWM" })?
                    .close()
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .onAppear {
                if let window = NSApplication.shared.windows.first(where: {
                    $0.identifier?.rawValue == "onboarding" || $0.title == "minfWM"
                }) {
                    window.level = .floating
                    window.isMovableByWindowBackground = true
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("minfWM Settings", id: "settings") {
            SettingsView(store: configStore, monitor: monitor) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
        }
        .defaultSize(width: 860, height: 580)
        .defaultPosition(.center)

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                Text("minfWM")
                    .font(.headline)
                Text(configStore.isServiceRunning ? "Service: Running" : "Service: Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Divider()

            Button("Settings...") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .keyboardShortcut(",")

            Button("Open Onboarding...") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }

            Divider()

            Button("Quit minfWM") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: Self.menuBarIcon())
                .accessibilityLabel("minfWM")
        }
    }

    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Geometry derived from assets/minfwm.icon/Assets/{viewport,windows-fill,windows-outline}.svg
            let scale: CGFloat = 16.0 / 656.0
            let ox: CGFloat = 1.0 - 184.0 * scale
            let oy: CGFloat = (18.0 - 456.0 * scale) / 2.0 - 284.0 * scale

            func mapRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: ox + x * scale, y: oy + y * scale, width: w * scale, height: h * scale)
            }

            let viewportRect = mapRect(286, 284, 554, 456)
            let viewportRadius = 76 * scale
            let viewportPath = CGPath(roundedRect: viewportRect, cornerWidth: viewportRadius, cornerHeight: viewportRadius, transform: nil)

            let topLeftWindow = mapRect(184, 346, 242, 162)
            let bottomLeftWindow = mapRect(228, 544, 220, 142)
            let rightWindow = mapRect(484, 372, 194, 284)

            let winRadius = 34 * scale
            let rightRadius = 38 * scale

            let topLeftPath = CGPath(roundedRect: topLeftWindow, cornerWidth: winRadius, cornerHeight: winRadius, transform: nil)
            let bottomLeftPath = CGPath(roundedRect: bottomLeftWindow, cornerWidth: winRadius, cornerHeight: winRadius, transform: nil)
            let rightPath = CGPath(roundedRect: rightWindow, cornerWidth: rightRadius, cornerHeight: rightRadius, transform: nil)

            ctx.setFillColor(NSColor.labelColor.cgColor)
            ctx.setStrokeColor(NSColor.labelColor.cgColor)

            // 1. Filled windows clipped inside the viewport
            ctx.saveGState()
            ctx.addPath(viewportPath)
            ctx.clip()
            ctx.addPath(topLeftPath)
            ctx.addPath(bottomLeftPath)
            ctx.addPath(rightPath)
            ctx.fillPath()
            ctx.restoreGState()

            // 2. Outlined windows outside the viewport (left of x = 286)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: viewportRect.minX, height: size.height))
            ctx.setLineWidth(1.0)
            ctx.addPath(topLeftPath)
            ctx.addPath(bottomLeftPath)
            ctx.strokePath()
            ctx.restoreGState()

            // 3. Viewport frame outline
            ctx.setLineWidth(1.2)
            ctx.addPath(viewportPath)
            ctx.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
