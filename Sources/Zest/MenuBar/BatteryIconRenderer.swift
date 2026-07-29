import AppKit

// Draws a compact, iPhone-style battery pill for the menu bar with the percent (or time
// remaining) inside. Smart colors reflect level and charge state. Options come from
// MenuBarStyle so the icon can be light or dark, colored or monochrome, with or without
// the number.
enum BatteryIconRenderer {
    static func image(snapshot: BatterySnapshot, style: MenuBarStyle) -> NSImage {
        let height: CGFloat = 15
        let plugged = snapshot.isACPower
        let boltSlot: CGFloat = plugged ? 10 : 0        // left slot for the charging bolt
        let baseW: CGFloat = style.hideNumber ? 28 : 44 // battery pill area
        let width = boltSlot + baseW
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        defer { img.unlockFocus() }

        let baseGlyph: NSColor = style.darkGlyph ? .black : .white
        let level = Double(snapshot.percent)
        let fillColor: NSColor
        if style.statusColors {
            if snapshot.isCharging || (snapshot.isACPower && snapshot.percent >= 80) {
                fillColor = nsColor(0x32D74B)
            } else if snapshot.percent <= 10 {
                fillColor = nsColor(0xEF4444)
            } else if snapshot.percent <= 20 {
                fillColor = nsColor(0xF59E0B)
            } else {
                fillColor = baseGlyph
            }
        } else {
            fillColor = baseGlyph
        }

        // Charging bolt in the left slot whenever plugged in (matches macOS, which shows the
        // bolt when on power even while holding at the 80% limit).
        if plugged {
            let boltColor = style.statusColors ? nsColor(0x32D74B) : baseGlyph
            drawBolt(centerX: boltSlot/2, centerY: height/2, color: boltColor)
        }

        // Battery body geometry, shifted right past the bolt slot.
        let bodyW = baseW - 6
        let bodyRect = NSRect(x: boltSlot + 1, y: 2, width: bodyW, height: height - 4)
        let radius: CGFloat = 3.5
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
        baseGlyph.withAlphaComponent(0.9).setStroke()
        bodyPath.lineWidth = 1.2
        bodyPath.stroke()

        // Nub
        let nub = NSBezierPath(roundedRect: NSRect(x: bodyRect.maxX + 0.5, y: height/2 - 2.5, width: 2.4, height: 5), xRadius: 1, yRadius: 1)
        baseGlyph.withAlphaComponent(0.9).setFill()
        nub.fill()

        // Fill proportional to level
        let inset: CGFloat = 2
        let maxFill = bodyW - inset*2
        let fillW = max(1, maxFill * CGFloat(min(100, max(0, level)) / 100))
        let fillRect = NSRect(x: bodyRect.minX + inset, y: bodyRect.minY + inset, width: fillW, height: bodyRect.height - inset*2)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        fillColor.withAlphaComponent(style.hideNumber ? 0.9 : 0.55).setFill()
        fillPath.fill()

        // Number / time
        if !style.hideNumber {
            let text: String
            if style.showTimeRemaining, let m = snapshot.timeRemainingMinutes, m > 0 {
                text = "\(m/60):\(String(format: "%02d", m%60))"
            } else {
                text = "\(snapshot.percent)"
            }
            let font = NSFont.systemFont(ofSize: 9, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: baseGlyph]
            let str = NSAttributedString(string: text, attributes: attrs)
            let size = str.size()
            str.draw(at: NSPoint(x: bodyRect.midX - size.width/2, y: bodyRect.midY - size.height/2))
        }

        img.isTemplate = false
        return img
    }

    // A small lightning bolt centered at (centerX, centerY).
    private static func drawBolt(centerX cx: CGFloat, centerY cy: CGFloat, color: NSColor) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx + 1.5, y: cy + 5))
        p.line(to: NSPoint(x: cx - 2.5, y: cy - 0.5))
        p.line(to: NSPoint(x: cx - 0.2, y: cy - 0.5))
        p.line(to: NSPoint(x: cx - 1.5, y: cy - 5))
        p.line(to: NSPoint(x: cx + 2.5, y: cy + 0.5))
        p.line(to: NSPoint(x: cx + 0.2, y: cy + 0.5))
        p.close()
        color.withAlphaComponent(0.95).setFill()
        p.fill()
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF)/255, green: CGFloat((hex >> 8) & 0xFF)/255, blue: CGFloat(hex & 0xFF)/255, alpha: 1)
    }
}
