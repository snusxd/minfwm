import AppKit
import SwiftUI

/// Reports the exact global AppKit screen center of the view it is attached to.
struct ScreenCenterReader: NSViewRepresentable {
    let onCenterChange: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onCenterChange = onCenterChange
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onCenterChange = onCenterChange
        nsView.reportCenter()
    }

    final class TrackingNSView: NSView {
        var onCenterChange: ((CGPoint) -> Void)?
        private var lastReported: CGPoint = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportCenter()
        }

        override func layout() {
            super.layout()
            reportCenter()
        }

        func reportCenter() {
            guard let window = self.window else { return }
            let localCenter = CGPoint(x: bounds.midX, y: bounds.midY)
            let windowPoint = convert(localCenter, to: nil)
            let screenPoint = window.convertPoint(toScreen: windowPoint)
            if abs(screenPoint.x - lastReported.x) > 0.5 || abs(screenPoint.y - lastReported.y) > 0.5 {
                lastReported = screenPoint
                DispatchQueue.main.async { [weak self] in
                    self?.onCenterChange?(screenPoint)
                }
            }
        }
    }
}

struct DraggableAppIconView: View {
    let isGranted: Bool
    @Binding var isHovering: Bool
    let onScreenCenterChange: (CGPoint) -> Void

    private var appIconImage: NSImage {
        NSApplication.shared.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    var body: some View {
        ZStack {
            Image(nsImage: appIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .background(ScreenCenterReader(onCenterChange: onScreenCenterChange))
                .shadow(
                    color: .black.opacity(isHovering ? 0.34 : 0.20),
                    radius: isHovering ? 14 : 8,
                    y: isHovering ? 7 : 4
                )
                .scaleEffect(isHovering && !isGranted ? 1.06 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
                .overlay(alignment: .bottomTrailing) {
                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white, .green)
                            .shadow(radius: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .onDrag {
                    NSItemProvider(object: Bundle.main.bundleURL as NSURL)
                } preview: {
                    Image(nsImage: appIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                }
                .onHover { hovering in
                    isHovering = hovering
                    if !isGranted {
                        if hovering {
                            NSCursor.openHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
        }
        .frame(width: 124, height: 124)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isGranted)
    }
}
