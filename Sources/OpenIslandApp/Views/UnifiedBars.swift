import SwiftUI

/// v6 `UnifiedBars` glyph — three vertical bars that share the same geometry
/// across all three notch states (idle / running / waiting), so transitions
/// animate bar heights smoothly instead of swapping glyphs.
///
/// Canonical geometry (from the design handoff): 24×24 box, 3 bars of width
/// 2.5 centered on columns x = 5.25 / 10.75 / 16.25, rounded to a pill.
struct UnifiedBars: View {
    enum Mode: Equatable {
        case idle       // rest — 3 short bars, middle breathes
        case running    // wave — heights 4→12→4, stagger 0.07s
        case waiting    // pause — outer bars tall, middle hidden, cross-pulse
    }

    var mode: Mode
    var size: CGFloat = 24
    /// Ink color for bars / tick. Defaults to the v6 paper ink.
    var tint: Color = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)

    private static let box: CGFloat = 24
    private static let barWidth: CGFloat = 2.5
    private static let center: CGFloat = 12

    private static let columns: [Column] = [
        Column(x: 5.25,  idleH: 3, waveCycle: [4, 12, 4], waveDelay: 0.00, waitH: 10),
        Column(x: 10.75, idleH: 5, waveCycle: [6, 14, 6], waveDelay: 0.07, waitH: 0),
        Column(x: 16.25, idleH: 3, waveCycle: [4, 10, 4], waveDelay: 0.14, waitH: 10),
    ]

    /// Shared waiting-pulse clock. Returns a cosine-eased 0→1 phase that both
    /// the glyph's outer bars and the right-slot agent tiles read from, so they
    /// breathe in lockstep instead of drifting on independent animations.
    static func islandWaitingPhase(
        at date: Date,
        period: Double = 1.2,
        offset: Double = 0
    ) -> Double {
        let time = date.timeIntervalSinceReferenceDate
        let raw = ((time + offset).truncatingRemainder(dividingBy: period)) / period
        let progress = raw < 0 ? raw + 1 : raw
        return 0.5 - 0.5 * cos(progress * 2 * .pi)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                withScaledContext(context, canvasSize) { ctx in
                    drawBars(context: ctx, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Drawing

    private func withScaledContext(
        _ context: GraphicsContext,
        _ canvasSize: CGSize,
        body: (GraphicsContext) -> Void
    ) {
        var ctx = context
        let side = min(canvasSize.width, canvasSize.height)
        let scale = side / Self.box
        let dx = (canvasSize.width - side) / 2
        let dy = (canvasSize.height - side) / 2
        ctx.translateBy(x: dx, y: dy)
        ctx.scaleBy(x: scale, y: scale)
        body(ctx)
    }

    private func drawBars(context: GraphicsContext, time: TimeInterval) {
        for column in Self.columns {
            let (height, y, opacity) = barGeometry(for: column, time: time)
            guard opacity > 0, height > 0 else { continue }
            let rect = CGRect(
                x: column.x,
                y: y,
                width: Self.barWidth,
                height: height
            )
            let path = Path(
                roundedRect: rect,
                cornerSize: CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2)
            )
            context.fill(path, with: .color(tint.opacity(opacity)))
        }
    }

    private func barGeometry(
        for column: Column,
        time: TimeInterval
    ) -> (height: CGFloat, y: CGFloat, opacity: Double) {
        switch mode {
        case .idle:
            let h = column.idleH
            let isMiddle = column.x == Self.columns[1].x
            let t = (1 - cos(time * 2 * .pi / 2.8)) / 2
            let breath = isMiddle
                ? 0.7 + (1.0 - 0.7) * t
                : 1.0
            return (h, Self.center - h / 2, breath)
        case .running:
            let cycle = column.waveCycle
            let period: TimeInterval = 0.8
            let raw = (time - column.waveDelay)
                .truncatingRemainder(dividingBy: period) / period
            let phase = raw < 0 ? raw + 1 : raw
            let h: CGFloat
            if phase < 0.5 {
                let t = phase / 0.5
                h = cycle[0] + (cycle[1] - cycle[0]) * t
            } else {
                let t = (phase - 0.5) / 0.5
                h = cycle[1] + (cycle[2] - cycle[1]) * t
            }
            return (h, Self.center - h / 2, 1.0)
        case .waiting:
            let h = column.waitH
            guard h > 0 else { return (0, Self.center, 0) }
            let isLeading = column.x < Self.center
            let period: TimeInterval = 1.2
            let offset = isLeading ? 0.0 : period / 2
            let wave = Self.islandWaitingPhase(
                at: Date(timeIntervalSinceReferenceDate: time),
                period: period,
                offset: offset
            )
            let opacity = 0.40 + 0.60 * wave
            return (h, Self.center - h / 2, opacity)
        }
    }

    private struct Column: Equatable {
        let x: CGFloat
        let idleH: CGFloat
        let waveCycle: [CGFloat]
        let waveDelay: TimeInterval
        let waitH: CGFloat
    }
}
