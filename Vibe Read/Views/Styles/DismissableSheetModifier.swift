import SwiftUI

/// View modifier that enables tap-outside-to-dismiss for macOS sheets
/// Wraps content in a larger container where tapping outside the content dismisses the sheet
struct DismissableSheetModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        ZStack {
            // Full-size background that captures taps to dismiss
            // Using minimal opacity to avoid visual artifacts while remaining tappable
            Color.black.opacity(0.001)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            // Content in center - naturally blocks taps from reaching background
            content
        }
        // Add padding around content to create tappable dismiss area
        .padding(40)
    }
}

extension View {
    /// Makes a sheet dismissable by tapping outside the content area
    /// Apply this modifier to the sheet's content in the .sheet() call
    func dismissableSheet() -> some View {
        modifier(DismissableSheetModifier())
    }
}
