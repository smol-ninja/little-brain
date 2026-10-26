import AppKit
import SwiftUI
import Combine
import ServiceManagement

private final class PulsePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = PulseMonitor()
    private var item: NSStatusItem!
    private var panel: PulsePanel!
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
            button.setAccessibilityLabel("Codex Pulse")
        }
        panel = PulsePanel(contentRect: NSRect(x: 0, y: 0, width: 392, height: 420),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Codex Pulse"
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: PulseView(monitor: monitor, dismiss: { [weak self] in self?.panel.orderOut(nil) }))
        hosting.sizingOptions = []
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 28
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
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(nil)
            panel.invalidateShadow()
        }
    }
    private func render(_ snapshot: PulseSnapshot) {
        item.button?.title = " " + snapshot.menuLabel
        item.button?.image = statusImage(snapshot)
        item.button?.toolTip = "Codex Pulse · \(snapshot.readyCount) ready of \(snapshot.totalCount) tracked\n\(snapshot.health.message)"
        item.button?.setAccessibilityValue("\(snapshot.readyCount) ready, \(snapshot.totalCount) tracked. \(snapshot.health.message)")
        if panel.isVisible { positionPanel() }
    }
    private func positionPanel() {
        guard let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main!
        let height: CGFloat = 306 + CGFloat(min(max(monitor.snapshot.totalCount, 1), 5)) * 56
        let x = min(max(anchor.midX - 196, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - 400)
        panel.setFrame(NSRect(x: x, y: anchor.minY - height - 8, width: 392, height: height), display: true)
    }
    private func statusImage(_ snapshot: PulseSnapshot) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            NSColor.labelColor.withAlphaComponent(0.25).setStroke(); ring.lineWidth = 1.6; ring.stroke()
            let fraction = snapshot.totalCount > 0 ? Double(snapshot.readyCount) / Double(snapshot.totalCount) : 0
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6, startAngle: 90,
                          endAngle: 90 - CGFloat(max(fraction, snapshot.totalCount > 0 ? 0.12 : 0)) * 360, clockwise: true)
            NSColor.labelColor.setStroke(); arc.lineWidth = 1.8; arc.lineCapStyle = .round; arc.stroke()
            if snapshot.attentionCount > 0 {
                NSBezierPath(ovalIn: NSRect(x: 7.5, y: 7.5, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct PulseView: View {
    @ObservedObject var monitor: PulseMonitor
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var snapshot: PulseSnapshot { monitor.snapshot }
    private var accent: Color { snapshot.attentionCount > 0 ? .orange : snapshot.readyCount > 0 ? .mint : .blue }
    private var headline: String {
        if !snapshot.isFresh { return "Waiting for Codex" }
        if snapshot.totalCount == 0 { return "A little room to focus." }
        if snapshot.attentionCount > 0 { return "Your input is needed." }
        if snapshot.readyCount == snapshot.totalCount { return "Ready when you are." }
        return snapshot.readyCount > 0 ? "Something’s ready." : "Good things in progress."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(accent)
                Text("Codex Pulse").font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(snapshot.isFresh ? Color.mint : Color.orange).frame(width: 5, height: 5)
                    Text(snapshot.isFresh ? "LIVE" : "SYNCING").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1)
                }.padding(.horizontal, 9).padding(.vertical, 6).background(.primary.opacity(0.045), in: Capsule())
            }.padding(.bottom, 24)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(snapshot.isFresh ? "\(snapshot.readyCount)" : "—")
                            .font(.system(size: 49, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("/ \(snapshot.totalCount)")
                            .font(.system(size: 30, weight: .regular, design: .rounded)).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }.monospacedDigit()
                    Text("ready to view").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(.primary.opacity(0.07), lineWidth: 6)
                    Circle().trim(from: 0, to: progress)
                        .stroke(accent.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: centerSymbol)
                        .font(.system(size: 23, weight: .light)).foregroundStyle(accent)
                        .contentTransition(.symbolEffect(.replace))
                }.frame(width: 67, height: 67).padding(.trailing, 4)
                    .accessibilityLabel("\(snapshot.readyCount) of \(snapshot.totalCount) ready")
            }.padding(.bottom, 17)
            Text(headline).font(.system(size: 16, weight: .medium)).padding(.bottom, 16)
            HStack(spacing: 8) {
                metric("Working", value: snapshot.workingCount, color: .blue)
                metric("Ready", value: snapshot.readyCount, color: .mint)
                if snapshot.attentionCount > 0 { metric("Attention", value: snapshot.attentionCount, color: .orange) }
                Spacer(minLength: 0)
            }.padding(.bottom, 16)
            Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
            if snapshot.rows.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: snapshot.isFresh ? "sparkle" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 19, weight: .light)).foregroundStyle(.secondary)
                    Text(snapshot.isFresh ? "Start a chat in Codex. I’ll follow along." : snapshot.health.message)
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).frame(height: 64)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(snapshot.rows) { row in
                            ChatRow(row: row) { monitor.open(row.id); dismiss() }
                        }
                    }.padding(.vertical, 6)
                }.scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
            Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
            HStack(alignment: .center, spacing: 8) {
                Text(snapshot.isFresh ? "Viewed chats clear automatically." : snapshot.health.message)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button { monitor.openCodex(); dismiss() } label: {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 14))
                }.buttonStyle(.plain).help("Open Codex").accessibilityLabel("Open Codex")
                Menu {
                    Text("Tracks local Codex chats on this Mac")
                    Text("Ready means finished and unread")
                    Divider()
                    Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            if enabled && !launchAtLogin { monitor.actionError = "Allow Codex Pulse in System Settings → General → Login Items." }
                        } catch { monitor.actionError = "Couldn’t change launch at login: \(error.localizedDescription)" }
                    }))
                    Divider()
                    Button("Quit Codex Pulse") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis").font(.system(size: 14)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).help("Options")
            }.padding(.top, 12)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: snapshot)
        .alert("Codex Pulse", isPresented: Binding(get: { monitor.actionError != nil }, set: { if !$0 { monitor.actionError = nil } })) {
            Button("OK") { monitor.actionError = nil }
        } message: { Text(monitor.actionError ?? "") }
    }
    private var progress: CGFloat {
        snapshot.totalCount == 0 ? 0 : CGFloat(snapshot.readyCount) / CGFloat(snapshot.totalCount)
    }
    private var centerSymbol: String {
        if !snapshot.isFresh { return "wifi.slash" }
        if snapshot.attentionCount > 0 { return "hand.raised" }
        if snapshot.totalCount == 0 { return "sparkle" }
        return snapshot.readyCount == snapshot.totalCount ? "checkmark" : "ellipsis"
    }
    private func metric(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(value)").fontWeight(.semibold).monospacedDigit().contentTransition(.numericText())
            Text(title).foregroundStyle(.secondary)
        }.font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(.primary.opacity(0.035), in: Capsule())
    }
}

private struct ChatRow: View {
    let row: TrackedChat
    let open: () -> Void
    @State private var hovering = false
    private var tint: Color {
        if !row.isFresh { return .secondary }
        switch row.phase {
        case .ready: return .mint
        case .working: return .blue
        case .waiting, .error: return .orange
        case .unknown: return .secondary
        }
    }
    private var symbol: String {
        guard row.isFresh else { return "antenna.radiowaves.left.and.right.slash" }
        switch row.phase {
        case .ready: return "checkmark"
        case .working: return "ellipsis"
        case .waiting: return "hand.raised"
        case .error: return "exclamationmark"
        case .unknown: return "questionmark"
        }
    }
    var body: some View {
        Button(action: open) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(tint.opacity(0.1))
                    Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(tint)
                }.frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                    Text(row.isFresh ? row.phase.label : "Reconnecting…").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).opacity(hovering ? 1 : 0.35)
            }.padding(.horizontal, 8).padding(.vertical, 8)
                .background(hovering ? Color.primary.opacity(0.055) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .help("Open \(row.title) in Codex")
            .accessibilityLabel("\(row.title), \(row.isFresh ? row.phase.label : "status unavailable"). Open in Codex")
    }
}
