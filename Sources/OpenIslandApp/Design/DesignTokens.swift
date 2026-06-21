import SwiftUI

// Canonical design tokens for Open Island's UI.
//
// These enums are the single vocabulary for spacing, opacity, corner radius,
// motion, shadow, and typography across the app. Sibling polish units (UI
// sweeps) migrate scattered numeric literals onto these tokens; new UI should
// reach for a token before introducing a raw value.
//
// Adding a token: keep each ladder coherent and monotonic. Don't slot a value
// between two existing steps (e.g. 0.05 between `hairline` and `faint`) unless
// it carries a real, distinct semantic meaning — otherwise reuse the nearest
// step. Color stays out of this file; use V6Palette / IslandDesignPalette.

enum IslandSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
}

enum IslandOpacity {
    static let hairline: Double = 0.045
    static let faint: Double = 0.08
    static let dim: Double = 0.22
    static let muted: Double = 0.42
    static let half: Double = 0.55
    static let soft: Double = 0.78
    static let strong: Double = 0.88
    static let full: Double = 1.0
}

enum IslandRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let pill: CGFloat = 999
}

enum IslandMotion {
    static let microSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let popSpring = Animation.spring(response: 0.42, dampingFraction: 0.80)
    static let bouncySpring = Animation.spring(response: 0.30, dampingFraction: 0.50)
    static let standardCurve = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.32)
    static let microCurve = Animation.easeInOut(duration: 0.18)
    static let breathe = Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)
}

struct IslandShadowStyle: Equatable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum IslandShadow {
    static let subtle = IslandShadowStyle(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    static let elevated = IslandShadowStyle(color: .black.opacity(0.36), radius: 22, x: 0, y: 12)

    static func pulse(tint: Color, phase: Double) -> IslandShadowStyle {
        IslandShadowStyle(color: tint.opacity(phase), radius: 5, x: 0, y: 0)
    }
}

enum IslandTypography {
    static let caption = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    static let captionEmphasis = Font.system(size: 10.5, weight: .semibold, design: .monospaced)
    static let body = Font.system(size: 12, weight: .medium)
    static let bodyEmphasis = Font.system(size: 12, weight: .semibold)
    static let headline = Font.system(size: 13, weight: .semibold)
    static let headlineLarge = Font.system(size: 14, weight: .semibold)
    static let pillLabel = Font.system(size: 11.5, weight: .medium, design: .monospaced)
    static let pillCount = Font.system(size: 11, weight: .semibold, design: .monospaced)
}

extension View {
    func islandShadow(_ style: IslandShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
