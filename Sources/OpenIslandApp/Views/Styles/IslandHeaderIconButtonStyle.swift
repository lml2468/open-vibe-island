import SwiftUI

struct IslandHeaderIconButtonStyle: ButtonStyle {
    var isMuted: Bool = false
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 22, height: 22)
            .foregroundStyle(tint(hovered: isHovered))
            .background {
                Circle().fill(
                    Color.white.opacity(
                        configuration.isPressed ? 0.22 : (isHovered ? 0.08 : 0)
                    )
                )
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.18), value: isHovered)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: configuration.isPressed)
    }

    private func tint(hovered: Bool) -> Color {
        if isMuted {
            return Color.orange.opacity(hovered ? 1.0 : 0.92)
        }
        return V6Palette.paper.opacity(hovered ? 0.92 : 0.62)
    }
}
