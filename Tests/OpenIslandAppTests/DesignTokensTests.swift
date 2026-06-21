import Testing
import SwiftUI
@testable import OpenIslandApp

struct DesignTokensTests {
    @Test
    func spacingLadderIsMonotonic() {
        let steps: [CGFloat] = [
            IslandSpacing.xxs, IslandSpacing.xs, IslandSpacing.sm, IslandSpacing.md,
            IslandSpacing.lg, IslandSpacing.xl, IslandSpacing.xxl, IslandSpacing.xxxl,
        ]
        #expect(steps == steps.sorted())
        #expect(IslandSpacing.xxs == 2)
        #expect(IslandSpacing.xxxl == 24)
    }

    @Test
    func opacityLadderIsMonotonicAndBounded() {
        let steps: [Double] = [
            IslandOpacity.hairline, IslandOpacity.faint, IslandOpacity.dim, IslandOpacity.muted,
            IslandOpacity.half, IslandOpacity.soft, IslandOpacity.strong, IslandOpacity.full,
        ]
        #expect(steps == steps.sorted())
        #expect(IslandOpacity.full == 1.0)
    }

    @Test
    func radiusValuesMatchSpec() {
        #expect(IslandRadius.xs == 6)
        #expect(IslandRadius.pill == 999)
    }

    @Test
    func shadowPulseAppliesPhaseToTint() {
        let style = IslandShadow.pulse(tint: .red, phase: 0.5)
        #expect(style.color == Color.red.opacity(0.5))
        #expect(style.radius == 5)
    }
}
