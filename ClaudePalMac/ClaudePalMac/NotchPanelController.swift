import AppKit
import SwiftUI
import Combine
import ClaudePalMacCore

// MARK: - KeyablePanel

/// NSPanel subclass that can become key (needed for SwiftUI button clicks).
/// Overrides constrainFrameRect to prevent macOS from pushing the panel
/// out of the menu bar area — this is how Codync keeps its panel on the notch.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Prevent macOS from constraining the panel below the menu bar.
    /// Without this, orderFront moves the panel down by its height.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect // allow positioning anywhere, including the menu bar
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            NotificationCenter.default.post(name: .claudePalShouldCollapse, object: nil)
        }
    }
}

extension Notification.Name {
    static let claudePalShouldCollapse = Notification.Name("claudePalShouldCollapse")
}

// MARK: - NotchPanelController

/// Owns the floating notch panel, positions it on/near the notch (Codync-style),
/// observes AppState, and manages show/hide/expand/collapse transitions.
///
/// Positioning strategy (from Codync):
/// - Compact icon height = menu bar height (matches notch exactly)
/// - y = screen.frame.maxY - height (anchored to absolute screen top)
/// - x = right edge of notch + small offset
/// - Panel level = .mainMenu + 3 (above everything)
@MainActor
final class NotchPanelController {
    private var panel: NSPanel!
    private var hostingView: NSHostingView<NotchPanelRootView>!
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    private(set) var mode: NotchPanelMode = .hidden {
        didSet { updateHostingView() }
    }

    // MARK: - Dimensions

    private let expandedWidth: CGFloat = 330
    private let maxExpandedHeight: CGFloat = 400

    /// Compact panel size — wider to fit mascot + model name + pending count.
    /// Width/height are the NSPanel frame; SwiftUI content is inset.
    private let compactSize = NSSize(width: 160, height: 28)

    // MARK: - Init

    init(appState: AppState) {
        self.appState = appState
        setupPanel()
        observeAppState()
        observeScreenChanges()
        observeCollapseNotification()
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let size = compactSize
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Codync uses .mainMenu + 3 to float above the menu bar
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary]
        panel.animationBehavior = .utilityWindow

        let rootView = NotchPanelRootView(
            appState: appState,
            mode: mode,
            onExpand: { [weak self] in self?.expand() },
            onCollapse: { [weak self] in self?.collapse() },
            onApprove: { [weak self] decision in self?.appState.approve(decision: decision) },
            onDeny: { [weak self] decision in self?.appState.deny(decision: decision) }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting

        setupClickMonitors()
    }

    // MARK: - Hosting View Update

    private func updateHostingView() {
        hostingView.rootView = NotchPanelRootView(
            appState: appState,
            mode: mode,
            onExpand: { [weak self] in self?.expand() },
            onCollapse: { [weak self] in self?.collapse() },
            onApprove: { [weak self] decision in self?.appState.approve(decision: decision) },
            onDeny: { [weak self] decision in self?.appState.deny(decision: decision) }
        )
    }

    // MARK: - Positioning (Codync-style: anchored to screen.frame.maxY)

    private let attentionSize = NSSize(width: 260, height: 300)

    private func computeFrame(for targetMode: NotchPanelMode) -> NSRect {
        guard let screen = NSScreen.main else { return .zero }

        switch targetMode {
        case .hidden:
            return NSRect(origin: computeCompactOrigin(screen: screen), size: compactSize)

        case .compact:
            return NSRect(origin: computeCompactOrigin(screen: screen), size: compactSize)

        case .attention:
            // Center of screen, slightly above middle
            let x = screen.frame.midX - attentionSize.width / 2
            let y = screen.frame.midY - attentionSize.height / 2 + 60
            return NSRect(origin: NSPoint(x: x, y: y), size: attentionSize)

        case .expanded:
            hostingView.invalidateIntrinsicContentSize()
            let fitting = hostingView.fittingSize
            let height = min(max(fitting.height, 120), maxExpandedHeight)
            let size = NSSize(width: expandedWidth, height: height)

            // Drop from the notch — tuck top edge slightly into menu bar
            let x = screen.frame.midX - expandedWidth / 2
            let y = screen.visibleFrame.maxY - height + 6
            return NSRect(origin: NSPoint(x: x, y: y), size: size)
        }
    }

    /// Compact origin: right of notch, bottom-aligned with menu bar.
    /// Uses auxiliaryTopRightArea to find the exact notch edge.
    /// Bottom of icon aligns with visibleFrame.maxY (menu bar bottom).
    private func computeCompactOrigin(screen: NSScreen) -> NSPoint {
        let size = compactSize
        // Bottom of icon at menu bar bottom, extends up into menu bar
        let y = screen.visibleFrame.maxY

        // Try to position next to the notch
        if let topRightArea = screen.auxiliaryTopRightArea {
            let x = topRightArea.minX + 2
            return NSPoint(x: x, y: y)
        }

        // Fallback for non-notch Macs: center at top
        let x = screen.frame.midX - size.width / 2
        return NSPoint(x: x, y: y)
    }

    // MARK: - Show / Hide / Expand / Collapse

    func showCompact() {
        guard mode == .hidden else { return }
        mode = .compact
        let frame = computeFrame(for: .compact)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Face ID-style: mascot grows big to center screen.
    /// Stays big until all pending decisions are resolved.
    func popAttention() {
        guard mode == .compact || mode == .hidden else { return }

        // If hidden, show first
        if mode == .hidden {
            mode = .compact
            let compactFrame = computeFrame(for: .compact)
            panel.setFrame(compactFrame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        // Grow to center — stays until approved/denied
        mode = .attention
        let bigFrame = computeFrame(for: .attention)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(bigFrame, display: true)
        }
    }

    /// Collapse attention back to compact (called when pending count hits 0).
    func dismissAttention() {
        guard mode == .attention else { return }
        mode = .compact
        let compactFrame = computeFrame(for: .compact)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(compactFrame, display: true)
        }
    }

    func hide() {
        guard mode != .hidden else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
                self?.mode = .hidden
            }
        }
    }

    func expand() {
        guard mode == .compact || mode == .attention else { return }
        mode = .expanded
        let newFrame = computeFrame(for: .expanded)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    func collapse() {
        guard mode == .expanded else { return }
        mode = .compact
        let newFrame = computeFrame(for: .compact)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    // MARK: - Click Outside

    private func setupClickMonitors() {
        // Global monitor — catches ALL clicks system-wide, including menu bar area.
        // This is critical because our panel sits in the menu bar and macOS
        // won't deliver those clicks to our app via the local monitor.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in
                guard let self = self, self.mode != .hidden else { return }
                let clickLocation = NSEvent.mouseLocation // screen coordinates
                if self.panel.frame.contains(clickLocation) {
                    // Click ON our panel
                    self.panel.makeKey()
                    if self.mode == .compact || self.mode == .attention {
                        self.expand()
                    }
                } else {
                    self.handleClickOutside()
                }
            }
        }

        // Local monitor — catches clicks delivered to our app (expanded panel buttons, etc.)
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                if event.windowNumber == self.panel.windowNumber {
                    self.panel.makeKey()
                    if self.mode == .compact || self.mode == .attention {
                        self.expand()
                    }
                } else {
                    self.handleClickOutside()
                }
            }
            return event
        }
    }

    private func handleClickOutside() {
        if mode == .expanded {
            collapse()
        }
    }

    // MARK: - ESC to collapse

    private func observeCollapseNotification() {
        NotificationCenter.default.addObserver(
            forName: .claudePalShouldCollapse,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapse()
            }
        }
    }

    // MARK: - Observe AppState

    private var previousPendingIds = Set<String>()

    private func observeAppState() {
        appState.$pendingDecisions
            .combineLatest(appState.$sessions, appState.$serverRunning)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] decisions, sessions, serverRunning in
                guard let self = self, serverRunning else {
                    self?.hide()
                    return
                }
                let hasPending = !decisions.isEmpty
                let hasActive = sessions.contains { $0.status == .active || $0.status == .waiting }

                // Detect truly new pending decisions
                let currentIds = Set(decisions.map(\.id))
                let hasNewPending = !currentIds.subtracting(self.previousPendingIds).isEmpty
                    && !self.previousPendingIds.isEmpty // skip first load
                self.previousPendingIds = currentIds

                if hasPending || hasActive {
                    if self.mode == .hidden {
                        if hasPending {
                            self.popAttention()
                        } else {
                            self.showCompact()
                        }
                    } else if hasNewPending && self.mode == .compact {
                        self.popAttention()
                    }
                    if self.mode == .expanded {
                        let newFrame = self.computeFrame(for: .expanded)
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.2
                            self.panel.animator().setFrame(newFrame, display: true)
                        }
                    }
                } else {
                    // No pending, no active — dismiss attention or hide
                    if self.mode == .attention {
                        self.dismissAttention()
                    } else {
                        self.hide()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.mode != .hidden else { return }
                let newFrame = self.computeFrame(for: self.mode)
                self.panel.setFrame(newFrame, display: true)
            }
        }
    }
}
