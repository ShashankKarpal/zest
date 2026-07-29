import SwiftUI

// Reusable pieces styled to match the widgets: half-circle arc gauge, thin bars, tiles,
// section headers, glass card. Kept generic so all panels share one visual language.

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.cardBG)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardBorder, lineWidth: 1))
            )
    }
}

struct ArcGauge: View {
    var pct: Double
    var color: Color
    var big: String
    var small: String
    // Fixed, bounded geometry so the arc never bleeds past the frame into the next section.
    private let gaugeHeight: CGFloat = 128
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cx = w / 2
            let cy: CGFloat = 108                     // arc endpoints sit here, well inside 128
            let r = min((w - 32) / 2, 84)             // apex at cy - r = 24, endpoints at 108
            ZStack {
                Path { p in
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                }.stroke(Theme.cardBorder, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Path { p in
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(180), endAngle: .degrees(180 + 180 * min(1, max(0, pct/100))), clockwise: false)
                }.stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .shadow(color: color.opacity(0.35), radius: 6)
                VStack(spacing: 6) {
                    Text(big).font(.system(size: 34, weight: .semibold)).foregroundColor(color)
                    Text(small).font(.system(size: 9, weight: .regular)).tracking(1.5).foregroundColor(Theme.faint)
                }
                .position(x: cx, y: cy - r * 0.40)
            }
        }
        .frame(height: gaugeHeight)
        .clipped()
    }
}

struct Tile: View {
    var label: String
    var value: String
    var color: Color = Theme.text
    var sub: String? = nil
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundColor(color)
            Text(label).font(.system(size: 9)).tracking(1.5).foregroundColor(Theme.faint)
            if let sub { Text(sub).font(.system(size: 10)).foregroundColor(Theme.ghost) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileBG)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1)))
    }
}

struct MeterBar: View {
    var pct: Double
    var color: Color
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height/2).fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: height/2).fill(color)
                    .frame(width: max(2, geo.size.width * min(1, max(0, pct/100))))
            }
        }.frame(height: height)
    }
}

struct BarRow: View {
    var label: String
    var right: String
    var pct: Double
    var color: Color
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.system(size: 10)).foregroundColor(Theme.dim)
                Spacer()
                Text(right).font(.system(size: 10)).foregroundColor(Theme.dim)
            }
            MeterBar(pct: pct, color: color)
        }
    }
}

struct SectionHead: View {
    var label: String
    var right: String? = nil
    var rightColor: Color = Theme.faint
    var body: some View {
        HStack {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundColor(Theme.dim)
            Spacer()
            if let right { Text(right).font(.system(size: 12, weight: .bold)).foregroundColor(rightColor) }
        }
    }
}

struct Divider1: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

struct Badge: View {
    var text: String
    var color: Color
    var filled: Bool = true
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold)).tracking(0.5)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundColor(color)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(filled ? 0.15 : 0))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.3), lineWidth: 1)))
    }
}

struct LegendDot: View {
    var color: Color
    var label: String
    var value: String
    var square: Bool = false
    var body: some View {
        HStack(spacing: 5) {
            Group {
                if square { RoundedRectangle(cornerRadius: 2).fill(color) }
                else { Circle().fill(color) }
            }.frame(width: 8, height: 8)
            Text(label).font(.system(size: 10)).foregroundColor(Theme.dim)
            Text(value).font(.system(size: 10)).foregroundColor(Theme.faint)
        }
    }
}
