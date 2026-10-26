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

enum PanelMetrics {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 26
    static let headerHeight: CGFloat = 88
    static let footerHeight: CGFloat = 52
    static let rowHeight: CGFloat = 52
    static let listInset: CGFloat = 6
    static let sectionHeaderHeight: CGFloat = 28
    static let sectionSpacing: CGFloat = 8

    static func height(for count: Int) -> CGFloat {
        headerHeight + footerHeight + sectionHeaderHeight * 2 + sectionSpacing + listInset * 2 + CGFloat(count) * rowHeight
    }

    static func rowCapacity(for height: CGFloat) -> Int {
        max(1, Int(floor((height - self.height(for: 0)) / rowHeight)))
    }
}

enum AppBrand {
    static let accent = Color(red: 0.32, green: 0.47, blue: 0.98)
    static let logo = Bundle.main.url(forResource: "Logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 48, height: 48))
    static let wordmark = Bundle.main.url(forResource: "Wordmark", withExtension: "pdf")
        .flatMap { NSImage(contentsOf: $0) }
}

private struct BrainView: View {
    @ObservedObject var monitor: PulseMonitor
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var pageIndex = 0

    var body: some View {
        GeometryReader { geometry in
            let pages = monitor.snapshot.pages(rowLimit: PanelMetrics.rowCapacity(for: geometry.size.height))
            let current = min(pageIndex, pages.count - 1)
            panel(page: pages[current], index: current, pageCount: pages.count)
                .onChange(of: pages.count) { _, count in pageIndex = min(pageIndex, count - 1) }
        }
    }

    private func panel(page: ChatPage, index: Int, pageCount: Int) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .frame(height: PanelMetrics.headerHeight)

            VStack(spacing: PanelMetrics.sectionSpacing) {
                ChatSection(title: "Ready for review", count: monitor.snapshot.reviewRows.count, rows: page.review) { id in
                    monitor.open(id); dismiss()
                }
                ChatSection(title: "Running", count: monitor.snapshot.runningRows.count, rows: page.running) { id in
                    monitor.open(id); dismiss()
                }
            }.padding(PanelMetrics.listInset)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 12)

            footer(index: index, pageCount: pageCount)
                .padding(.horizontal, 20)
                .frame(height: PanelMetrics.footerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Color(nsColor: .windowBackgroundColor).opacity(0.28)
                RadialGradient(colors: [AppBrand.accent.opacity(0.14), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 270)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .white.opacity(0.22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: monitor.snapshot)
        .alert("littlebrain", isPresented: Binding(get: { monitor.actionError != nil }, set: { if !$0 { monitor.actionError = nil } })) {
            Button("OK") { monitor.actionError = nil }
        } message: { Text(monitor.actionError ?? "") }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: AppBrand.logo)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 48, height: 48)
                .shadow(color: AppBrand.accent.opacity(0.24), radius: 9, y: 4)
                .accessibilityHidden(true)
            if let wordmark = AppBrand.wordmark {
                Image(nsImage: wordmark)
                    .resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 140, height: 18)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("littlebrain")
            } else {
                Text("littlebrain")
                    .font(.system(size: 15, weight: .semibold)).tracking(-0.35)
            }
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(monitor.snapshot.isFresh ? "\(monitor.snapshot.readyCount)" : "—")
                    .font(.system(size: 31, weight: .medium, design: .rounded))
                    .foregroundStyle(monitor.snapshot.readyCount > 0 && monitor.snapshot.isFresh ? AppBrand.accent : Color.primary)
                    .contentTransition(.numericText())
                Text("/ \(monitor.snapshot.totalCount)")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(monitor.snapshot.isFresh
                                ? "\(monitor.snapshot.readyCount) unread, \(monitor.snapshot.totalCount) tracked"
                                : "Status unavailable, \(monitor.snapshot.totalCount) tracked")
            .help("Finished unread chats / tracked chats")
        }
    }

    private func footer(index: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            Text("Launch at login")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(AppBrand.accent)
            Spacer()
            if pageCount > 1 {
                Button { pageIndex = index - 1 } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 28)
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous chats")
                Text("\(index + 1) / \(pageCount)")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("Page \(index + 1) of \(pageCount)")
                Button { pageIndex = index + 1 } label: {
                    Image(systemName: "chevron.right").frame(width: 24, height: 28)
                }
                .disabled(index == pageCount - 1)
                .accessibilityLabel("Next chats")
            }
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.045), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PanelControlStyle())
            .keyboardShortcut("q")
            .accessibilityLabel("Quit littlebrain")
            .help("Quit littlebrain")
        }
        .buttonStyle(PanelControlStyle())
        .font(.system(size: 11, weight: .medium))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                monitor.actionError = "Enable littlebrain in System Settings > General > Login Items."
            }
        } catch { monitor.actionError = "Could not change launch at login. \(error.localizedDescription)" }
    }
}

private struct ChatSection: View {
    let title: String
    let count: Int
    let rows: [ChatOutlineRow]
    let open: (ChatID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: PanelMetrics.sectionHeaderHeight)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in ChatRow(entry: row) { open(row.id) } }
        }
    }
}

private struct ChatRow: View {
    let entry: ChatOutlineRow
    private var row: TrackedChat? { entry.chat }
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                statusMark.frame(width: 18, height: 18).accessibilityHidden(true)
                Text(entry.context.displayTitle)
                    .font(.system(size: entry.depth == 0 ? 13 : 12, weight: row?.phase == .ready || row == nil ? .medium : .regular))
                    .foregroundStyle(row?.isFresh == true ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? AppBrand.accent : Color.secondary.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12).frame(height: PanelMetrics.rowHeight)
            .background(hovering ? AppBrand.accent.opacity(0.09) : Color.primary.opacity(entry.depth > 0 ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .padding(.leading, CGFloat(min(entry.depth, 6)) * 18)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<min(entry.depth, 6), id: \.self) { _ in
                        Rectangle().fill(AppBrand.accent.opacity(0.18)).frame(width: 1).frame(width: 18)
                    }
                }.allowsHitTesting(false)
            }
        }
        .buttonStyle(PanelControlStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        .accessibilityLabel("\(entry.context.displayTitle), level \(entry.depth + 1), \(row.map { $0.isFresh ? $0.phase.label : "status unavailable" } ?? "Parent chat"). Open in Codex")
    }

    @ViewBuilder private var statusMark: some View {
        if let row {
            if !row.isFresh || row.phase == .unknown {
                Image(systemName: "circle.dashed").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                switch row.phase {
                case .working:
                    if reduceMotion {
                        Circle().strokeBorder(AppBrand.accent, lineWidth: 1.8).frame(width: 11, height: 11)
                    } else {
                        ProgressView().controlSize(.mini).tint(AppBrand.accent)
                    }
                case .ready:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(AppBrand.accent)
                case .waiting:
                    Image(systemName: "pause.circle").font(.system(size: 15)).foregroundStyle(.orange)
                case .error:
                    Image(systemName: "exclamationmark.circle").font(.system(size: 15)).foregroundStyle(.orange)
                case .unknown:
                    EmptyView()
                }
            }
        } else {
            Image(systemName: "bubble.left").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

private struct PanelControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
