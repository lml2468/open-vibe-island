import SwiftUI

/// Approximate fallback brand colors for the appearance preview's agent rows,
/// used only if `Color(hex: AgentTool.brandColorHex)` ever returns nil. Not the
/// canonical `brandColorHex` palette.
enum BrandPalette {
    static let codexDefault      = Color(red: 0.55, green: 0.72, blue: 1.00)
    static let claudeCodeDefault = Color(red: 0.90, green: 0.55, blue: 0.34)
    static let cursorDefault     = Color(red: 0.62, green: 0.66, blue: 1.00)
    static let geminiCLIDefault  = Color(red: 0.45, green: 0.78, blue: 1.00)
}
