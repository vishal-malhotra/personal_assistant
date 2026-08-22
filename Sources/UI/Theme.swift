import SwiftUI

/// Minimalist Apple Design System tokens.
/// Adheres strictly to Apple HIG using standard system semantic materials and colors.
public enum AssistantTheme {
    // Dynamic system background and grouping colors
    public static let background = Color(uiColor: .systemGroupedBackground)
    public static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
    public static let tertiaryBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    
    // System standard labels
    public static let label = Color(uiColor: .label)
    public static let secondaryLabel = Color(uiColor: .secondaryLabel)
    public static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
    public static let separator = Color(uiColor: .separator)
    
    // Apple system tints
    public static let systemBlue = Color.blue
    public static let systemRed = Color(red: 0.95, green: 0.23, blue: 0.23)
    public static let systemGreen = Color.green
    public static let systemOrange = Color.orange
}
