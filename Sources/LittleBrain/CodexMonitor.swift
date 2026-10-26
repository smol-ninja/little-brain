import Foundation
import AppKit
import Combine
import SQLite3
import Darwin

struct SourceConfiguration: Sendable {
    let codexHome: URL
    static var localDefault: Self {
        Self(codexHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
    }
}

actor CodexSource {
    private let configuration: SourceConfiguration
    init(configuration: SourceConfiguration) { self.configuration = configuration }
    func observations() -> AsyncStream<SourceEvent> {
        let config = configuration
        return AsyncStream { continuation in
            let cancellation = Cancellation()
            continuation.onTermination = { _ in cancellation.cancel() }
            DispatchQueue(label: "com.local.littlebrain.socket", qos: .utility).async {
                SocketWorker(configuration: config, cancellation: cancellation, output: continuation).run()
            }
        }
    }
}

private final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private struct CatalogEntry {
    let id: String
    let title: String
    let createdAt: Date
    var isEphemeral = false
}
private struct Replica {
    var owner: String
    var revision: Int
    var fields: [String: Any]
    var observed: Observation
    var refreshed: Date
}
private struct SourceFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private final class SocketWorker {
    let configuration: SourceConfiguration
    let cancellation: Cancellation
    let output: AsyncStream<SourceEvent>.Continuation
    var fd: Int32 = -1
    var client = "initializing-client"
    var buffer = Data()
    var catalog: [String: CatalogEntry] = [:]
    var ephemeralCatalog: [String: CatalogEntry] = [:]
    var liveViewers: [String: Set<String>] = [:]
    var replicas: [String: Replica] = [:]
    var requested: [String: Date] = [:]
    var subscribed: Set<String> = []
    var lastCatalog = Date.distantPast
    var lastRefresh = Date.distantPast
    let fields: Set<String> = ["title", "threadRuntimeStatus", "hasUnreadTurn", "latestTurnStartMessageId"]

    init(configuration: SourceConfiguration, cancellation: Cancellation, output: AsyncStream<SourceEvent>.Continuation) {
        self.configuration = configuration; self.cancellation = cancellation; self.output = output
    }

    func run() {
        defer { disconnect(); output.finish() }
        while !cancellation.isCancelled {
            do {
                output.yield(.health(.connecting))
                try connect()
                let handshakeDeadline = Date().addingTimeInterval(5)
                while !cancellation.isCancelled {
                    if client == "initializing-client" && Date() > handshakeDeadline { throw SourceFailure("Codex connection timed out") }
                    if client != "initializing-client" {
                        if Date().timeIntervalSince(lastCatalog) > 2 { try discover() }
                        if Date().timeIntervalSince(lastRefresh) > 15 {
                            for id in Set(catalog.keys).union(ephemeralCatalog.keys).union(liveViewers.keys).sorted() { try follow(id) }
                            lastRefresh = Date()
                        }
                        for (id, sent) in requested where Date().timeIntervalSince(sent) > 5 {
                            if replicas[id] != nil { output.yield(.stale(ChatID(value: id))) }
                        }
                    }
                    var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    let result = Darwin.poll(&descriptor, 1, 250)
                    if result < 0 { if errno == EINTR { continue }; throw SourceFailure("Codex connection interrupted") }
                    if result == 0 { continue }
                    if descriptor.revents & Int16(POLLIN) == 0 && descriptor.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { throw SourceFailure("Codex is offline · reconnecting") }
                    var bytes = [UInt8](repeating: 0, count: 65536)
                    let count = Darwin.recv(fd, &bytes, bytes.count, 0)
                    guard count > 0 else { throw SourceFailure("Codex is offline · reconnecting") }
                    buffer.append(contentsOf: bytes.prefix(count))
                    try consumeFrames()
                }
            } catch {
                let reason = (error as? SourceFailure)?.message ?? "Could not read Codex · retrying"
                output.yield(.health(.unavailable(reason)))
            }
            disconnect()
            for _ in 0..<12 {
                if cancellation.isCancelled { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }

    func connect() throws {
        let path = configuration.codexHome.appendingPathComponent("ipc/ipc.sock").path
        guard path.utf8.count < 104 else { throw SourceFailure("Codex socket path is too long") }
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SourceFailure("Could not create local connection") }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            path.utf8CString.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw SourceFailure("Open Codex to connect") }
        try send(["type": "request", "requestId": UUID().uuidString, "sourceClientId": client,
                  "version": 0, "method": "initialize", "params": ["clientType": "little-brain"]])
    }

    func disconnect() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        client = "initializing-client"; buffer.removeAll(); replicas.removeAll()
        requested.removeAll(); subscribed.removeAll(); ephemeralCatalog.removeAll(); liveViewers.removeAll(); lastCatalog = .distantPast; lastRefresh = .distantPast
    }

    func send(_ object: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(body.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(body)
        try frame.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw SourceFailure("Codex connection interrupted") }
                offset += written
            }
        }
    }

    func follow(_ id: String, following: Bool = true) throws {
        try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
                  "sourceClientId": client, "params": ["conversationId": id, "hostId": "local", "following": following]])
        if following {
            subscribed.insert(id)
            if requested[id] == nil { requested[id] = Date() }
        } else { subscribed.remove(id); requested.removeValue(forKey: id) }
    }

    func discover() throws {
        let next = try readCatalog()
        for id in catalog.keys where next[id] == nil {
            try follow(id, following: false)
            replicas.removeValue(forKey: id)
        }
        catalog = next
        publishCatalog()
        for id in Set(catalog.keys).union(ephemeralCatalog.keys).union(liveViewers.keys).sorted() where !subscribed.contains(id) { try follow(id) }
        lastCatalog = Date()
        output.yield(.health(.live))
    }

    func publishCatalog() {
        let ids = Set(catalog.keys).union(ephemeralCatalog.keys)
        output.yield(.catalog(Set(ids.map { ChatID(value: $0) })))
    }

    func removeLiveViewer(_ viewer: String, from id: String) throws {
        guard liveViewers[id] != nil else { return }
        liveViewers[id]?.remove(viewer)
        guard liveViewers[id]?.isEmpty == true else { return }
        liveViewers.removeValue(forKey: id)
        let wasTracked = ephemeralCatalog.removeValue(forKey: id) != nil
        if catalog[id] == nil {
            replicas.removeValue(forKey: id)
            if subscribed.contains(id) { try follow(id, following: false) }
        }
        if wasTracked { publishCatalog() }
    }

    func observeFollowing(_ params: [String: Any], sender: String) throws {
        guard sender != client, let id = params["conversationId"] as? String, UUID(uuidString: id) != nil,
              let following = params["following"] as? Bool else { return }
        if !following { try removeLiveViewer(sender, from: id); return }
        guard catalog[id] == nil else { return }
        liveViewers[id, default: []].insert(sender)
        if client != "initializing-client" && !subscribed.contains(id) { try follow(id) }
    }

    func admitEphemeralSnapshot(_ state: [String: Any], id: String) throws -> Bool {
        guard liveViewers[id]?.isEmpty == false else { return false }
        guard state["sideConversation"] as? Bool == true, state["ephemeral"] as? Bool == true,
              state["threadSource"] as? String == "user",
              let createdAt = state["createdAt"] as? Double, createdAt.isFinite else {
            liveViewers.removeValue(forKey: id)
            try follow(id, following: false)
            return false
        }
        ephemeralCatalog[id] = CatalogEntry(id: id, title: "Untitled chat",
                                           createdAt: Date(timeIntervalSince1970: createdAt / 1000), isEphemeral: true)
        publishCatalog()
        return true
    }

    func readCatalog() throws -> [String: CatalogEntry] {
        let url = configuration.codexHome.appendingPathComponent("state_5.sqlite")
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            throw SourceFailure("Codex catalog unavailable · retrying")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        let sql = "SELECT id, COALESCE(NULLIF(name,''),'Untitled chat'), created_at FROM threads WHERE archived=0 AND source IN ('vscode','cli','appServer') AND originator='Codex Desktop' ORDER BY updated_at DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw SourceFailure("Codex catalog changed · update needed") }
        defer { sqlite3_finalize(statement) }
        var result: [String: CatalogEntry] = [:]
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let rawID = sqlite3_column_text(statement, 0), let rawTitle = sqlite3_column_text(statement, 1) {
                let id = String(cString: rawID)
                if UUID(uuidString: id) != nil {
                    result[id] = CatalogEntry(id: id, title: String(cString: rawTitle), createdAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2))))
                }
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw SourceFailure("Codex catalog is busy · retrying") }
        return result
    }

    func consumeFrames() throws {
        while buffer.count >= 4 {
            let prefix = Array(buffer.prefix(4))
            let size = Int(UInt32(prefix[0]) | UInt32(prefix[1]) << 8 | UInt32(prefix[2]) << 16 | UInt32(prefix[3]) << 24)
            guard size > 0 && size <= 64 * 1024 * 1024 else { throw SourceFailure("Codex data format changed · update needed") }
            guard buffer.count >= size + 4 else { return }
            let payload = buffer.subdata(in: 4..<(size + 4))
            buffer.removeSubrange(0..<(size + 4))
            try autoreleasepool {
                guard let message = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw SourceFailure("Invalid Codex response") }
                try receive(message)
            }
        }
    }

    func receive(_ message: [String: Any]) throws {
        if message["type"] as? String == "client-discovery-request", let id = message["requestId"] {
            try send(["type": "client-discovery-response", "requestId": id, "response": ["canHandle": false]])
            return
        }
        let method = message["method"] as? String ?? ""
        if method == "initialize" {
            guard let result = message["result"] as? [String: Any], let assigned = result["clientId"] as? String else { throw SourceFailure("Codex handshake changed · update needed") }
            client = assigned
            try discover()
            lastRefresh = Date()
            return
        }
        guard message["type"] as? String == "broadcast", let params = message["params"] as? [String: Any] else { return }
        if method == "ipc-connection-reset" { throw SourceFailure("Codex restarted · reconnecting") }
        if method == "client-status-changed" {
            guard let owner = params["clientId"] as? String else { return }
            if params["status"] as? String == "disconnected" {
                for id in Array(liveViewers.keys) { try removeLiveViewer(owner, from: id) }
                for (id, replica) in replicas where replica.owner == owner {
                    output.yield(.stale(ChatID(value: id)))
                    replicas.removeValue(forKey: id)
                    requested.removeValue(forKey: id)
                }
            } else { lastRefresh = .distantPast }
            return
        }
        guard params["hostId"] as? String == "local", let id = params["conversationId"] as? String else { return }
        if method == "thread-stream-following-changed", message["version"] as? Int == 1,
           let sender = message["sourceClientId"] as? String {
            try observeFollowing(params, sender: sender)
            return
        }
        if method == "thread-archived" || method == "thread-unarchived" { lastCatalog = .distantPast; return }
        guard catalog[id] != nil || ephemeralCatalog[id] != nil || liveViewers[id] != nil else { lastCatalog = .distantPast; return }
        if method == "thread-read-state-changed" {
            // Identity-bearing broadcasts only invalidate; the owner remains the authority.
            try follow(id)
            return
        }
        guard method == "thread-stream-state-changed" else { return }
        guard message["version"] as? Int == 11 else { throw SourceFailure("Codex protocol changed · update needed") }
        guard let owner = message["sourceClientId"] as? String,
              let change = params["change"] as? [String: Any], let revision = change["revision"] as? Int else {
            throw SourceFailure("Codex state format changed · update needed")
        }
        if change["type"] as? String == "snapshot" {
            guard let state = change["conversationState"] as? [String: Any] else { throw SourceFailure("Invalid Codex snapshot") }
            if catalog[id] == nil && ephemeralCatalog[id] == nil {
                guard try admitEphemeralSnapshot(state, id: id) else { return }
            }
            let projected = state.filter { fields.contains($0.key) }
            try accept(projected, id: id, owner: owner, revision: revision)
        } else if change["type"] as? String == "patches" {
            guard var replica = replicas[id], replica.owner == owner,
                  change["baseRevision"] as? Int == replica.revision,
                  revision > replica.revision,
                  let patches = change["patches"] as? [[String: Any]] else {
                output.yield(.stale(ChatID(value: id))); try follow(id); return
            }
            do {
                for patch in patches {
                    guard let path = patch["path"] as? [Any], let operation = patch["op"] as? String else { throw SourceFailure("Invalid patch") }
                    if path.isEmpty {
                        guard operation != "remove", let root = patch["value"] as? [String: Any] else { throw SourceFailure("Invalid root patch") }
                        replica.fields = root.filter { fields.contains($0.key) }
                    } else if let first = path[0] as? String, fields.contains(first) {
                        replica.fields = try patched(replica.fields, path: path, operation: operation, value: patch["value"]) as! [String: Any]
                    }
                }
                try accept(replica.fields, id: id, owner: owner, revision: revision)
            } catch {
                replicas.removeValue(forKey: id)
                output.yield(.stale(ChatID(value: id)))
                try follow(id)
            }
        } else { throw SourceFailure("Unknown Codex update · update needed") }
    }

    func accept(_ projection: [String: Any], id: String, owner: String, revision: Int) throws {
        guard let entry = catalog[id] ?? ephemeralCatalog[id], let runtime = projection["threadRuntimeStatus"] as? [String: Any],
              let kind = runtime["type"] as? String, let unread = projection["hasUnreadTurn"] as? Bool else {
            throw SourceFailure("Codex status format changed · update needed")
        }
        let status: Runtime
        switch kind {
        case "active":
            guard let flags = runtime["activeFlags"] as? [String] else { throw SourceFailure("Codex activity format changed · update needed") }
            if flags.isEmpty { status = .active }
            else if flags.allSatisfy({ $0 == "waitingOnUserInput" || $0 == "waitingOnApproval" }) { status = .waiting }
            else { status = .unavailable }
        case "idle": status = .idle
        case "systemError": status = .systemError
        case "notLoaded": status = .unavailable
        default: throw SourceFailure("Unknown Codex status · update needed")
        }
        let title = (projection["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? entry.title
        let observation = Observation(id: ChatID(value: id), title: String(title.prefix(240)),
                                      generation: projection["latestTurnStartMessageId"] as? String,
                                      runtime: status, unread: unread, createdAt: entry.createdAt,
                                      isEphemeral: entry.isEphemeral ? true : nil)
        let previous = replicas[id]
        let refreshWasRequested = requested[id] != nil
        replicas[id] = Replica(owner: owner, revision: revision, fields: projection, observed: observation, refreshed: Date())
        requested.removeValue(forKey: id)
        // Fresh snapshots restore freshness even when metadata is unchanged.
        if previous?.observed != observation || refreshWasRequested {
            output.yield(.observed(observation))
        }
    }

    func patched(_ node: Any, path: [Any], operation: String, value: Any?) throws -> Any {
        guard ["add", "replace", "remove"].contains(operation), let head = path.first else { throw SourceFailure("Unsupported patch") }
        let tail = Array(path.dropFirst())
        if var dictionary = node as? [String: Any], let key = head as? String {
            if tail.isEmpty {
                if operation == "remove" { dictionary.removeValue(forKey: key) }
                else if let value { dictionary[key] = value }
                else { throw SourceFailure("Missing patch value") }
            } else {
                guard let child = dictionary[key] else { throw SourceFailure("Missing patch parent") }
                dictionary[key] = try patched(child, path: tail, operation: operation, value: value)
            }
            return dictionary
        }
        if var array = node as? [Any], let index = head as? Int, index >= 0 {
            if tail.isEmpty {
                switch operation {
                case "add": guard index <= array.count, let value else { throw SourceFailure("Invalid array patch") }; array.insert(value, at: index)
                case "replace": guard index < array.count, let value else { throw SourceFailure("Invalid array patch") }; array[index] = value
                default: guard index < array.count else { throw SourceFailure("Invalid array patch") }; array.remove(at: index)
                }
            } else {
                guard index < array.count else { throw SourceFailure("Missing array parent") }
                array[index] = try patched(array[index], path: tail, operation: operation, value: value)
            }
            return array
        }
        throw SourceFailure("Unsupported metadata patch")
    }
}

@MainActor final class PulseMonitor: ObservableObject {
    @Published private(set) var snapshot: PulseSnapshot
    @Published var actionError: String?
    private var state: PulseState
    private let configuration: SourceConfiguration
    private let storageURL: URL
    private var task: Task<Void, Never>?
    private var lastSaved: Data?

    init(configuration: SourceConfiguration = .localDefault) {
        self.configuration = configuration
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = support.appendingPathComponent("little-brain/tracking.json")
        let previousStorageURL = support.appendingPathComponent("Codex Pulse/tracking.json")
        var saved: SavedState?
        let existingStorageURL = FileManager.default.fileExists(atPath: storageURL.path) ? storageURL : previousStorageURL
        if let data = try? Data(contentsOf: existingStorageURL) {
            do {
                let decoded = try JSONDecoder().decode(SavedState.self, from: data)
                if decoded.version == 1 { saved = decoded }
                else { actionError = "Saved tracking uses a newer version." }
            } catch { actionError = "Saved tracking could not be restored. Tracking current activity." }
        }
        state = PulseState(restoring: saved)
        snapshot = state.snapshot
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            let source = CodexSource(configuration: configuration)
            for await event in await source.observations() {
                if Task.isCancelled { break }
                state.apply(event)
                let next = state.snapshot
                if next != snapshot { snapshot = next }
                persist()
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
    func open(_ chat: ChatID) {
        guard let url = chat.url, NSWorkspace.shared.open(url) else { actionError = "Could not open this chat in Codex."; return }
    }
    private func persist() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            var saved = state.saved
            saved.rows.sort { $0.id.value < $1.id.value }
            saved.baselines.sort { $0.id.value < $1.id.value }
            let data = try encoder.encode(saved)
            guard data != lastSaved else { return }
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: storageURL, options: .atomic)
            lastSaved = data
        } catch { actionError = "Could not save tracking for restart." }
    }
}
