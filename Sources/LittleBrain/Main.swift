import AppKit
import Foundation

@main struct LittleBrainMain {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--diagnose") {
            let source = CodexSource(configuration: .localDefault)
            let task = Task {
                for await event in await source.observations() {
                    switch event {
                    case .health(let health): print("connection: \(health.message)")
                    case .observed(let row): print("chat: \(row.id.value) runtime=\(row.runtime.rawValue) unread=\(row.unread)")
                    case .stale(let id): print("stale: \(id.value)")
                    case .catalog: break
                    }
                }
            }
            try? await Task.sleep(for: .seconds(8))
            task.cancel()
            return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.local.littlebrain").count > 1 { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
