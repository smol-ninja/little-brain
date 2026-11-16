// Used by render-demo.sh with the app presentation source and sample data.
import AppKit
import SwiftUI

@MainActor final class PulseMonitor: ObservableObject {
    @Published var snapshot = PulseSnapshot(rows: [], health: .live)
    @Published var actionError: String?
    func start() {}
    func stop() {}
    func open(_ id: ChatID) {}
}

@MainActor final class AppUpdater: ObservableObject {
    @Published var updateAvailable = false
    var canCheckForUpdates = true
    func start() {}
    func checkForUpdates() {}
}

@MainActor private struct DemoScene: View {
    @ObservedObject var monitor: PulseMonitor
    let updater: AppUpdater
    let loginItem: LoginItem
    let time: Double
    var panelVisible: Bool { time < 7.2 || time >= 8.0 }
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.73, green: 0.8, blue: 0.96), Color(red: 0.40, green: 0.48, blue: 0.73), Color(red: 0.19, green: 0.25, blue: 0.44)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 17) {
                    Image(systemName: "apple.logo").font(.system(size: 14))
                    Text("Codex").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    HStack(spacing: 5) {
                        Image(nsImage: AppBrand.logo).resizable().frame(width: 18, height: 18)
                        Text(monitor.snapshot.menuLabel.replacingOccurrences(of: "/", with: " / "))
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    }.padding(.horizontal, 9).frame(height: 26)
                        .background(.white.opacity(panelVisible ? 0.25 : 0), in: RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "wifi").font(.system(size: 12))
                    Text("9:41").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 18).frame(height: 34).background(.white.opacity(0.3))
                Spacer()
            }
            if panelVisible {
                BrainView(monitor: monitor, updater: updater, loginItem: loginItem, dismiss: {})
                    .frame(width: PanelMetrics.width, height: PanelMetrics.height(for: monitor.snapshot.pages[0].rowCount))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 12)
                    .padding(.top, 48)
            }
            if time >= 6.1 && time < 8.4 {
                let progress = min(1, (time - 6.1) / 0.7)
                let reopening = max(0, min(1, (time - 7.3) / 0.6))
                Image(nsImage: NSCursor.arrow.image)
                    .position(x: 420 - 170 * progress + 82 * reopening,
                              y: 440 - 244 * progress - 178 * reopening)
                if time >= 7.0 && time < 7.2 {
                    Circle().stroke(AppBrand.accent.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24).position(x: 250, y: 196)
                }
            }
            VStack {
                Spacer()
                Text(time < 2 ? "4 chats running" : time < 7.2 ? "Replies ready in your menu bar" : "Reviewed chats leave the list")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                    .padding(.bottom, 18)
            }
        }.frame(width: 460, height: 530)
            .environment(\.colorScheme, .light)
    }
}

@main struct RenderDemo {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let monitor = PulseMonitor()
        let updater = AppUpdater()
        let loginItem = LoginItem()
        var state = PulseState(now: Date(timeIntervalSince1970: 0))
        state.apply(.health(.live))
        let titles = ["Build a landing page", "Side chat", "Fix the login bug", "Add dark mode"]
        let ids = (0..<4).map { ChatID(value: "sample-\($0)") }
        func observe(_ index: Int, _ runtime: Runtime, _ unread: Bool) {
            state.apply(.observed(Observation(id: ids[index], title: titles[index], runtime: runtime, unread: unread, createdAt: Date(timeIntervalSince1970: 1), parentID: index == 1 ? ids[0] : nil, isSideChat: index == 1)), now: Date(timeIntervalSince1970: Double(index)))
        }
        for index in 0..<4 { observe(index, .active, false) }
        monitor.snapshot = state.snapshot
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let hosting = NSHostingView(rootView: DemoScene(monitor: monitor, updater: updater, loginItem: loginItem, time: 0))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 460, height: 530), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        let fps = 12
        for frame in 0..<(fps * 11) {
            let time = Double(frame) / Double(fps)
            if frame == fps * 2 { observe(2, .idle, true) }
            if frame == fps * 4 { observe(0, .idle, true); observe(1, .idle, true) }
            if frame == 87 { observe(2, .idle, false) }
            monitor.snapshot = state.snapshot
            hosting.rootView = DemoScene(monitor: monitor, updater: updater, loginItem: loginItem, time: time)
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / Double(fps)))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(String(format: "%04d.png", frame)))
        }
    }
}
