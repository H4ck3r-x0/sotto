import AppKit
import SwiftUI

/// Real macOS glass: blurs whatever is behind the window (wallpaper, apps),
/// masked to a capsule.
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active

        let radius: CGFloat = 27
        let diameter = radius * 2 + 1
        let mask = NSImage(size: .init(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        view.maskImage = mask
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A compact, fixed-size pill: center-bloom waveform on the left, the
/// latest words on the right. The pill itself never moves, grows, or glows —
/// only the bars and text are alive.
struct HUDView: View {
    let dictation: DictationController
    @Environment(\.colorScheme) private var colorScheme

    private let contentWidth: CGFloat = 430
    private let coralTop = Color(red: 1.0, green: 0.62, blue: 0.42)
    private let coralBottom = Color(red: 1.0, green: 0.30, blue: 0.44)

    // The pill adapts to the system appearance: dark smoky glass with white
    // text in dark mode, milky glass with dark text in light mode.
    private var pillTint: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.52)
            : Color.white.opacity(0.55)
    }

    private var pillStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.78)
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            pill
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 24)
    }

    private var pill: some View {
        HStack(spacing: 12) {
            CenterBloom(
                level: dictation.audioLevel,
                active: dictation.state == .recording,
                gradient: LinearGradient(
                    colors: [coralTop, coralBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            text
            Spacer(minLength: 0)
        }
        .frame(width: contentWidth, height: 30)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            ZStack {
                GlassBackground()
                Capsule(style: .continuous)
                    .fill(pillTint)
                Capsule(style: .continuous)
                    .strokeBorder(pillStroke, lineWidth: 1)
            }
        )
    }

    private var text: some View {
        Text(displayText)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .truncationMode(.head)
            .animation(.easeOut(duration: 0.1), value: displayText)
    }

    private var displayText: String {
        if !dictation.liveTranscript.isEmpty { return dictation.liveTranscript }
        return switch dictation.state {
        case .recording: "Listening…"
        case .transcribing: "…"
        default: ""
        }
    }
}

/// Bars bloom outward from the center — tallest in the middle, symmetric,
/// with a gentle per-bar shimmer while you speak. No scrolling direction.
private struct CenterBloom: View {
    let level: Float
    let active: Bool
    let gradient: LinearGradient

    private let barCount = 17

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(gradient)
                        .opacity(active ? 0.55 + Double(level) * 0.45 : 0.35)
                        .frame(width: 3, height: barHeight(index: index, time: t))
                }
            }
        }
        .frame(width: CGFloat(barCount) * 5.5, height: 26)
        .animation(.easeOut(duration: 0.09), value: level)
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let weight = 1 - abs(Double(index) - center) / (center + 1)
        let shimmer = 0.6 + 0.4 * (0.5 + 0.5 * sin(time * 11 + Double(index) * 1.7))
        let height = Double(level) * (0.35 + 0.65 * weight) * shimmer
        return 4 + CGFloat(height) * 22
    }
}
