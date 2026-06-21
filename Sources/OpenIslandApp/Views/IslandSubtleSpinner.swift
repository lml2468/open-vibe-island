import SwiftUI

/// Three dots pulsing in a staggered wave — brand-aligned loading indicator
/// that shares the rhythmic vocabulary of UnifiedBars instead of the generic
/// circular `ProgressView`.
struct IslandSubtleSpinner: View {
    private let dotCount = 3
    var size: CGFloat = 4
    var spacing: CGFloat = 5
    var tint: Color = V6Palette.paper

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<dotCount, id: \.self) { i in
                    Circle()
                        .fill(tint)
                        .frame(width: size, height: size)
                        .opacity(dotOpacity(at: t, index: i))
                        .scaleEffect(dotScale(at: t, index: i))
                }
            }
        }
    }

    private func eased(at t: TimeInterval, index: Int) -> Double {
        let period: Double = 1.2
        let phase = t.truncatingRemainder(dividingBy: period) / period
        let stagger = Double(index) * 0.18
        let local = (phase - stagger).truncatingRemainder(dividingBy: 1.0)
        return (1 - cos(local * 2 * .pi)) / 2
    }

    private func dotOpacity(at t: TimeInterval, index: Int) -> Double {
        0.25 + 0.6 * eased(at: t, index: index)
    }

    private func dotScale(at t: TimeInterval, index: Int) -> Double {
        0.85 + 0.25 * eased(at: t, index: index)
    }
}
