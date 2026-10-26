import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PulseMonitor()
    private var menuBar: MenuBarController!
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let hosting = NSHostingView(rootView: BrainView(monitor: monitor, dismiss: { [weak self] in
            self?.menuBar.dismiss()
        }))
        hosting.sizingOptions = []
        menuBar = MenuBarController(content: hosting)
        subscription = monitor.$snapshot.sink { [weak self] snapshot in self?.menuBar.update(snapshot) }
        monitor.start()
        if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
            UserDefaults.standard.set(true, forKey: "hasShownWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.menuBar.show() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar.dismiss()
        monitor.stop()
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
