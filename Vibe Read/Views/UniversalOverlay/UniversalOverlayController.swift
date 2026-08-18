import SwiftUI
import AppKit
import Combine

/// Manages the Universal Overlay window (NSPanel)
/// Shows context-aware menu near cursor position
class UniversalOverlayController: NSObject, ObservableObject {
    static let shared = UniversalOverlayController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var localKeyMonitor: Any?
    private var dismissTimer: Timer?

    @Published var isVisible = false
    @Published var currentContext: AppContext?

    private let panelWidth: CGFloat = 280
    private let maxPanelHeight: CGFloat = 400
    private let dismissTimeout: TimeInterval = 10.0

    override init() {
        super.init()
    }

    // MARK: - Show/Hide

    func show(with context: AppContext) {
        print("[Overlay] show() called with context: \(context.contextType)")

        // Store context
        currentContext = context

        // Create or update panel
        if panel == nil {
            print("[Overlay] Creating panel...")
            createPanel()
        }

        // Update content
        updateContent(with: context)

        // Position near cursor
        positionPanel()
        print("[Overlay] Panel positioned at: \(panel?.frame.origin ?? .zero)")

        // Show with animation
        showPanel()
        print("[Overlay] Panel should now be visible: \(panel?.isVisible ?? false)")

        // Start dismiss timer
        startDismissTimer()

        // Monitor for clicks outside
        startEventMonitor()
    }

    func hide() {
        stopDismissTimer()
        stopEventMonitor()

        guard let panel = panel, panel.isVisible else {
            isVisible = false
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.isVisible = false
            self?.currentContext = nil
        })
    }

    func toggle(with context: AppContext) {
        if isVisible {
            hide()
        } else {
            show(with: context)
        }
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let contentView = OverlayMenuView(controller: self)

        hostingView = NSHostingView(rootView: AnyView(contentView))
        hostingView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 200)

        panel = NSPanel(
            contentRect: hostingView!.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel?.contentView = hostingView
        panel?.isOpaque = false
        panel?.backgroundColor = .clear
        panel?.level = .floating
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel?.isReleasedWhenClosed = false
        panel?.hasShadow = true
        panel?.hidesOnDeactivate = false

        // Allow the panel to become key for keyboard navigation
        panel?.becomesKeyOnlyIfNeeded = false
    }

    private func updateContent(with context: AppContext) {
        let contentView = OverlayMenuView(controller: self)

        hostingView?.rootView = AnyView(contentView)

        // Resize to fit content
        hostingView?.invalidateIntrinsicContentSize()
        if let size = hostingView?.fittingSize {
            let height = min(size.height, maxPanelHeight)
            hostingView?.frame.size = CGSize(width: panelWidth, height: height)
            panel?.setContentSize(CGSize(width: panelWidth, height: height))
        }
    }

    // MARK: - Positioning

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        guard let panel = panel,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main else { return }
        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame

        // Default: position below and to the right of cursor
        var x = mouseLocation.x + 10
        var y = mouseLocation.y - panelSize.height - 10

        // Adjust if too close to right edge
        if x + panelSize.width > screenFrame.maxX {
            x = mouseLocation.x - panelSize.width - 10
        }

        // Adjust if too close to left edge
        if x < screenFrame.minX {
            x = screenFrame.minX + 10
        }

        // Adjust if too close to bottom
        if y < screenFrame.minY {
            y = mouseLocation.y + 20 // Position above cursor instead
        }

        // Adjust if too close to top
        if y + panelSize.height > screenFrame.maxY {
            y = screenFrame.maxY - panelSize.height - 10
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showPanel() {
        guard let panel = panel else { return }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        isVisible = true
    }

    // MARK: - Event Monitoring

    private func startEventMonitor() {
        stopEventMonitor()

        // Monitor for clicks outside the panel
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }

            // Check if click is outside panel using mouse location
            let screenPoint = NSEvent.mouseLocation

            if !panel.frame.contains(screenPoint) {
                self.hide()
            }
        }

        // Also monitor for escape key
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - Dismiss Timer

    private func startDismissTimer() {
        stopDismissTimer()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissTimeout, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func stopDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    /// Reset timer when user interacts
    func resetDismissTimer() {
        startDismissTimer()
    }
}
