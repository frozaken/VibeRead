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
                    return NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.93, alpha: 1.0)
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
                    return NSColor(calibratedWhite: 0.72, alpha: 1)
                }
                return NSColor(calibratedWhite: 0.42, alpha: 1)
            }))
        }

        static var brandGreen: Color {
            brandAccent
        }

        static var brandWarm: Color {
            brandAccent
        }

        static var creamSurface: Color {
            Color(nsColor: NSColor(name: "VibeReadCream", dynamicProvider: { appearance in
                if appearance.name == .darkAqua {
                    return NSColor(calibratedRed: 0.19, green: 0.18, blue: 0.16, alpha: 1)
                }
                return NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.88, alpha: 1)
            }))
        }
    }

    struct Dimensions {
        static let sidebarWidth: CGFloat = 200
        static let contentCornerRadius: CGFloat = 12
        static let contentPadding: CGFloat = 12
        static let titlebarHeight: CGFloat = 40
    }
}
