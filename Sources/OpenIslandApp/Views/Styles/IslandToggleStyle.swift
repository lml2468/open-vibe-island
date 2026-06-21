import SwiftUI

/// Pill switch that matches Open Island's dark palette, replacing the system
/// `Toggle` chrome in Settings panes. Visual swap only — accessibility and the
/// underlying `isOn` binding are preserved.
struct IslandToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.10))
                    .frame(width: 30, height: 18)
                Circle()
                    .fill(V6Palette.paper)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: configuration.isOn)
        }
    }
}
