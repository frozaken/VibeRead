import SwiftUI

struct AppTheme {
    struct Colors {
        // Semantic colors that adapt to system appearance
        static var sidebarBackground: Color {
            // Warm dark grey for dark mode
            // Using a slightly warmer variant than standard window background
            Color(nsColor: NSColor(name: "WarmSidebar", dynamicProvider: { appearance in
                if appearance.name == .darkAqua {
                    // Slightly warmer dark grey (hint of brown/creme)
                    return NSColor(calibratedRed: 0.13, green: 0.125, blue: 0.12, alpha: 1.0)
                } else {
                    // Slightly warmer light grey (creme tint)
                    return NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.95, alpha: 1.0)
                }
            }))
        }

        static var contentBackground: Color {
            Color(nsColor: NSColor.textBackgroundColor)
        }

        static var secondaryContentBackground: Color {
            Color(nsColor: NSColor.controlBackgroundColor)
        }

        static var sidebarText: Color {
            Color.primary.opacity(0.8)
        }

        static var sidebarTextSelected: Color {
            Color.primary
        }

        static var border: Color {
            Color.primary.opacity(0.1)
        }

        static var brandAccent: Color {
            Color(nsColor: NSColor(name: "VibeReadAccent", dynamicProvider: { appearance in
                if appearance.name == .darkAqua {
                    return NSColor(calibratedRed: 0.74, green: 0.66, blue: 0.96, alpha: 1)
                }
                return NSColor(calibratedRed: 0.43, green: 0.31, blue: 0.70, alpha: 1)
            }))
        }
    }

    struct Dimensions {
        static let sidebarWidth: CGFloat = 200
        static let contentCornerRadius: CGFloat = 12
        static let contentPadding: CGFloat = 12
    }
}
