import AppKit
import SwiftUI

// Presents notification pills and the screen-edge glow as borderless, non-activating
// panels on the active screen. Pills auto-dismiss unless marked persistent. The glow is a
// separate click-through window so it never intercepts the cursor.
final class OverlayManager {
    private let config: AppConfig
    private var pillWindows: [NSWindow] = []
    private var glowWindow: NSWindow?
    private var glowTimer: Timer?

    init(config: AppConfig) { self.config = config }

    func show(_ payload: AlertPayload) {
        DispatchQueue.main.async { self.present(payload) }
    }

    private func present(_ payload: AlertPayload) {
        guard let screen = NSScreen.main else { return }
        playSound(payload.sound)
        if payload.glow { flashGlow(color: Color(hex: payload.colorHex), on: screen) }

        let size = NSSize(width: 340 * 1.0, height: 92)
        let content = PillView(payload: payload) { [weak self] window in
            self?.dismiss(window)
        }
        let host = NSHostingView(rootView: content)
        let panel = makePanel(size: size)
        panel.contentView = host

        let frame = pillFrame(for: payload.position, size: size, on: screen)
        panel.setFrame(frame.offsetBy(dx: 0, dy: 12), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        pillWindows.append(panel)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }

        if !payload.persistent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.dismiss(panel) }
        }
    }

    private func dismiss(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            self.pillWindows.removeAll { $0 == window }
        })
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private func pillFrame(for pos: PillPosition, size: NSSize, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        let margin: CGFloat = 20
        var x = v.midX - size.width/2
        var y = v.maxY - size.height - margin
        switch pos {
        case .topLeft: x = v.minX + margin; y = v.maxY - size.height - margin
        case .topCenter: x = v.midX - size.width/2; y = v.maxY - size.height - margin
        case .topRight: x = v.maxX - size.width - margin; y = v.maxY - size.height - margin
        case .midLeft: x = v.minX + margin; y = v.midY - size.height/2
        case .center: x = v.midX - size.width/2; y = v.midY - size.height/2
        case .midRight: x = v.maxX - size.width - margin; y = v.midY - size.height/2
        case .bottomLeft: x = v.minX + margin; y = v.minY + margin
        case .bottomCenter: x = v.midX - size.width/2; y = v.minY + margin
        case .bottomRight: x = v.maxX - size.width - margin; y = v.minY + margin
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: Glow
    private func flashGlow(color: Color, on screen: NSScreen) {
        glowTimer?.invalidate()
        if glowWindow == nil {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .statusBar
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            glowWindow = w
        }
        guard let w = glowWindow else { return }
        w.setFrame(screen.frame, display: false)
        w.contentView = NSHostingView(rootView: GlowView(color: color, intensity: config.glowIntensity))
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.3; w.animator().alphaValue = 1 }
        glowTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
            guard let w = self?.glowWindow else { return }
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.5; w.animator().alphaValue = 0 },
                                                 completionHandler: { w.orderOut(nil) })
        }
    }

    private func playSound(_ name: String) {
        if let s = NSSound(named: NSSound.Name(name)) { s.play(); return }
        // Imported sound file in app support / Sounds
        let url = AppConfig.dir.appendingPathComponent("Sounds/\(name)")
        if FileManager.default.fileExists(atPath: url.path), let s = NSSound(contentsOf: url, byReference: true) { s.play() }
    }
}

// MARK: Pill view
private struct PillView: View {
    let payload: AlertPayload
    let onClose: (NSWindow) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: payload.colorHex).opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: payload.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: payload.colorHex))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(payload.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(payload.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.dim)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 340, height: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.cardBG)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: payload.colorHex).opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: { if let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) { onClose(w) } }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.faint)
                }.buttonStyle(.plain).padding(6)
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: Glow view (edge gradient)
private struct GlowView: View {
    let color: Color
    let intensity: Double
    var body: some View {
        GeometryReader { geo in
            let inset = min(geo.size.width, geo.size.height) * 0.5
            RoundedRectangle(cornerRadius: 0)
                .stroke(color, lineWidth: 6)
                .blur(radius: 40 * intensity + 10)
                .padding(-2)
                .overlay(
                    RadialGradient(colors: [color.opacity(0), color.opacity(0.35 * intensity)],
                                   center: .center, startRadius: inset, endRadius: max(geo.size.width, geo.size.height))
                )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
