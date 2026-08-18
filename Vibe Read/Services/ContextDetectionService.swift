import Foundation

/// Minimal context passed to the local action palette. No browser automation,
/// AppleScript, document scraping, or email access is performed.
struct AppContext {
    let frontmostApp: AppInfo
    let selectedText: String?
    let browserURL: URL?
    let documentPath: String?
    let emailContent: EmailContent?
    let contextType: ContextType
    let needsPermission: Bool
}

enum ContextType: Equatable {
    case browser(url: URL)
    case pdf(path: String)
    case email(subject: String)
    case textSelection
    case clipboard
    case empty
}

struct AppInfo {
    let name: String
    let bundleId: String
}

struct EmailContent {
    let subject: String
    let sender: String
    let body: String
}
