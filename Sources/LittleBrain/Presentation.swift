import AppKit
import SwiftUI
import Combine
import ServiceManagement

private final class BrainPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = PulseMonitor()
    private var item: NSStatusItem!
    private var panel: BrainPanel!
    private var subscription: AnyCancellable?
    private var outsideMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self; button.action = #selector(togglePanel)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.setAccessibilityLabel("little-brain")
        }
        panel = BrainPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 98),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "little-brain"
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: BrainView(monitor: monitor, dismiss: { [weak self] in self?.panel.orderOut(nil) }))
        hosting.sizingOptions = []
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 18
        if #available(macOS 27, *) { glass.effectIsInteractive = true }
        glass.contentView = hosting
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glass.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        panel.contentView = glass
        subscription = monitor.$snapshot.sink { [weak self] snapshot in self?.render(snapshot) }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.panel.orderOut(nil); return nil }
            if event.type != .keyDown && event.window !== self.panel && event.window !== self.item.button?.window { self.panel.orderOut(nil) }
            return event
        }
        monitor.start()
        if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
            UserDefaults.standard.set(true, forKey: "hasShownWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.togglePanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { togglePanel() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    @objc func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) }
        else {
            positionPanel(monitor.snapshot)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(nil)
            panel.invalidateShadow()
        }
    }
    private func render(_ snapshot: PulseSnapshot) {
        item.button?.title = snapshot.menuLabel.replacingOccurrences(of: "/", with: " / ")
        item.button?.setAccessibilityValue("\(snapshot.readyCount) ready, \(snapshot.totalCount) tracked. \(snapshot.health.message)")
        if panel.isVisible { positionPanel(snapshot) }
    }
    private func positionPanel(_ snapshot: PulseSnapshot) {
        guard let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main!
        let height = min(62 + CGFloat(min(snapshot.totalCount, 8)) * 36, screen.visibleFrame.height - 40)
        let x = min(max(anchor.midX - 160, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - 328)
        panel.setFrame(NSRect(x: x, y: anchor.minY - height - 8, width: 320, height: height), display: true)
    }
}

private struct BrainView: View {
    @ObservedObject var monitor: PulseMonitor
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("little-brain").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text(monitor.snapshot.menuLabel.replacingOccurrences(of: "/", with: " / "))
                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(monitor.snapshot.readyCount) unread, \(monitor.snapshot.totalCount) tracked")
                Menu {
                    Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            if enabled && !launchAtLogin {
                                monitor.actionError = "Enable little-brain in System Settings > General > Login Items."
                            }
                        } catch { monitor.actionError = "Could not change launch at login. \(error.localizedDescription)" }
                    }))
                    Button("Quit little-brain") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 16)
                .accessibilityLabel("Options")
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            if !monitor.snapshot.rows.isEmpty {
                Divider().padding(.horizontal, 16)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.snapshot.rows) { row in
                            ChatRow(row: row) { monitor.open(row.id); dismiss() }
                        }
                    }.padding(.horizontal, 8).padding(.vertical, 6)
                }.scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: monitor.snapshot)
        .alert("little-brain", isPresented: Binding(get: { monitor.actionError != nil }, set: { if !$0 { monitor.actionError = nil } })) {
            Button("OK") { monitor.actionError = nil }
        } message: { Text(monitor.actionError ?? "") }
    }
}

private struct ChatRow: View {
    let row: TrackedChat
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            Text(row.title)
                .font(.system(size: 13, weight: row.phase == .ready ? .medium : .regular))
                .foregroundStyle(row.isFresh ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).frame(height: 36)
                .background(hovering ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel("\(row.title), \(row.isFresh ? row.phase.label : "status unavailable"). Open in Codex")
    }
}
