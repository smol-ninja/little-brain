import AppKit

private final class BrainPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

@MainActor final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = BrainPanel(contentRect: .zero,
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var rowCount = 0

    init(content: NSView) {
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown])
            let logo = AppBrand.logo.copy() as? NSImage
            logo?.size = NSSize(width: 18, height: 18)
            button.image = logo
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.setAccessibilityLabel("littlebrain")
        }
        panel.title = "littlebrain"
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.onDismiss = { [weak self] in self?.dismiss() }

        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = PanelMetrics.cornerRadius
        if #available(macOS 27, *) { glass.effectIsInteractive = true }
        glass.contentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        panel.contentView = glass
    }

    func update(_ snapshot: PulseSnapshot) {
        rowCount = snapshot.displayedRowCount
        item.button?.title = snapshot.menuLabel.replacingOccurrences(of: "/", with: " / ")
        item.button?.setAccessibilityValue("\(snapshot.readyCount) ready, \(snapshot.totalCount) tracked. \(snapshot.health.message)")
        if panel.isVisible { positionPanel() }
    }

    @objc private func toggle() {
        if panel.isVisible { dismiss() }
        else { show() }
    }

    func show() {
        guard !panel.isVisible else { return }
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        panel.invalidateShadow()
        item.button?.highlight(true)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissIfOutside(at: NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self.dismissIfOutside(at: point)
            return event
        }
    }

    func dismiss() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil
        localMonitor = nil
        panel.orderOut(nil)
        item.button?.highlight(false)
    }

    private var buttonFrame: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func dismissIfOutside(at point: NSPoint) {
        // macOS may deliver status-item presses through the global monitor.
        // The button owns those presses; treating them as outside would toggle twice.
        guard panel.isVisible, !panel.frame.contains(point), buttonFrame?.contains(point) != true else { return }
        dismiss()
    }

    private func positionPanel() {
        guard let anchor = buttonFrame, let screen = item.button?.window?.screen ?? NSScreen.main else { return }
        let height = min(PanelMetrics.height(for: rowCount), screen.visibleFrame.height - 40)
        let width = PanelMetrics.width
        let x = min(max(anchor.midX - width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - height - 8, width: width, height: height), display: true)
    }
}
