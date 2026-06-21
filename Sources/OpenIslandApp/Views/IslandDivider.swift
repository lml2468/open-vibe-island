import SwiftUI

/// Canonical 1pt hairline divider used throughout the island UI.
///
/// Centralizing the opacity keeps section / footer / row dividers visually
/// uniform. Use this in `.overlay(alignment: .top)` or `.overlay(alignment:
/// .bottom)` blocks instead of an inline `Rectangle().fill(...).frame(height: 1)`.
struct IslandDivider: View {
    var opacity: Double = IslandOpacity.hairline

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(opacity))
            .frame(height: 1)
    }
}
