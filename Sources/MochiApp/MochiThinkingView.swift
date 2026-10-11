import SwiftUI

/// A squishy mochi that bounces while the AI is looking at files.
struct MochiThinkingView: View {
    let progress: AIProgress
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 14) {
            BouncingMochi(size: compact ? 44 : 72)
            VStack(spacing: 3) {
                Text("Mochi is sorting with AI…")
                    .font(compact ? .headline : .title3.weight(.semibold))
                    .fixedSize()
                Text(progress.total > 1 ? "Looking at file \(progress.current) of \(progress.total)" : "Looking at your file")
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                Text(progress.filename)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: compact ? 280 : 340)
            }
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mochi is sorting with AI, file \(progress.current) of \(progress.total)")
    }
}

struct AISortingOverlay: View {
    let progress: AIProgress

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            MochiThinkingView(progress: progress)
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        }
    }
}

private struct BouncingMochi: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 0.9
    private static let blinkPeriod = 3.1

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = time.truncatingRemainder(dividingBy: Self.period) / Self.period
            let height = reduceMotion ? 0 : sin(.pi * phase)
            let landing = max(0, 1 - height * 4)
            let speed = abs(cos(.pi * phase)) * (1 - landing)
            let scaleX = 1 + 0.22 * landing - 0.05 * speed
            let scaleY = 1 - 0.18 * landing + 0.08 * speed
            let blinking = time.truncatingRemainder(dividingBy: Self.blinkPeriod) < 0.13

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.16 * (1 - 0.6 * height)))
                    .frame(width: size * (0.85 - 0.35 * height), height: size * 0.12)
                    .blur(radius: 1.5)
                MochiBody(blinking: blinking)
                    .frame(width: size, height: size * 0.82)
                    .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
                    .offset(y: -size * 0.04 - height * size * 0.42)
            }
            .frame(width: size * 1.3, height: size * 1.3, alignment: .bottom)
        }
    }
}

private struct MochiBody: View {
    let blinking: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                MochiShape()
                    .fill(LinearGradient(
                        colors: [Color(red: 1, green: 0.97, blue: 0.96), Color(red: 0.98, green: 0.83, blue: 0.81)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                MochiShape()
                    .stroke(Color(red: 0.86, green: 0.6, blue: 0.58).opacity(0.55), lineWidth: max(1, w * 0.025))
                Ellipse()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: w * 0.22, height: h * 0.12)
                    .rotationEffect(.degrees(-20))
                    .position(x: w * 0.3, y: h * 0.24)
                ForEach([0.36, 0.64], id: \.self) { x in
                    Capsule()
                        .fill(Color(red: 0.2, green: 0.16, blue: 0.16))
                        .frame(width: w * 0.075, height: blinking ? w * 0.015 : w * 0.11)
                        .position(x: w * x, y: h * 0.55)
                    Circle()
                        .fill(Color(red: 0.97, green: 0.55, blue: 0.55).opacity(0.45))
                        .frame(width: w * 0.12, height: w * 0.08)
                        .position(x: w * (x < 0.5 ? x - 0.1 : x + 0.1), y: h * 0.68)
                }
                Path { path in
                    path.addArc(center: CGPoint(x: w * 0.5, y: h * 0.62), radius: w * 0.05, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                }
                .stroke(Color(red: 0.2, green: 0.16, blue: 0.16), style: StrokeStyle(lineWidth: max(1, w * 0.025), lineCap: .round))
            }
        }
    }
}

private struct MochiShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * 0.72))
        path.addCurve(to: CGPoint(x: w * 0.5, y: 0), control1: CGPoint(x: 0, y: h * 0.18), control2: CGPoint(x: w * 0.2, y: 0))
        path.addCurve(to: CGPoint(x: w, y: h * 0.72), control1: CGPoint(x: w * 0.8, y: 0), control2: CGPoint(x: w, y: h * 0.18))
        path.addCurve(to: CGPoint(x: w * 0.78, y: h), control1: CGPoint(x: w, y: h * 0.94), control2: CGPoint(x: w * 0.92, y: h))
        path.addLine(to: CGPoint(x: w * 0.22, y: h))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.72), control1: CGPoint(x: w * 0.08, y: h), control2: CGPoint(x: 0, y: h * 0.94))
        path.closeSubpath()
        return path
    }
}
