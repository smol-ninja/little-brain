import XCTest
import Foundation
import Darwin
import SQLite3
@testable import LittleBrain

final class SocketContractTests: XCTestCase {
    func testEphemeralChatsJoinFromLiveAnnouncementsAndLeaveWhenTheirLastViewerCloses() async throws {
        let fixture = try SocketFixture()
        defer { fixture.close() }
        let sideID = "00000000-0000-4000-8000-000000000010"
        let excludedID = "00000000-0000-4000-8000-000000000011"
        let serverFinished = expectation(description: "live chat fixture completed")
        DispatchQueue(label: "fixture.live-chats").async {
            defer {
                if fixture.peer >= 0 { Darwin.close(fixture.peer); fixture.peer = -1 }
                serverFinished.fulfill()
            }
            do {
                try fixture.handshake()
                try fixture.expectFollow()
                try fixture.snapshot(revision: 1, runtime: "active", unread: false)
                func announce(_ id: String, viewer: String, following: Bool = true, host: String = "local") throws {
                    try fixture.send(["type":"broadcast", "method":"thread-stream-following-changed", "version":1,
                                      "sourceClientId":viewer, "params":["conversationId":id,"hostId":host,"following":following]])
                }
                func expect(_ id: String, following: Bool = true) throws {
                    let message = try fixture.read()
                    let params = message["params"] as? [String:Any]
                    XCTAssertEqual(message["method"] as? String, "thread-stream-following-changed")
                    XCTAssertEqual(params?["conversationId"] as? String, id)
                    XCTAssertEqual(params?["following"] as? Bool, following)
                }
                func snapshot(_ id: String, revision: Int, runtime: String, unread: Bool, source: String = "user") throws {
                    try fixture.send(["type":"broadcast", "method":"thread-stream-state-changed", "version":11,
                                      "sourceClientId":"fixture-owner", "params":["conversationId":id,"hostId":"local",
                                        "change":["type":"snapshot","revision":revision,"conversationState":[
                                            "title":"Design the icon", "sideConversation":true, "ephemeral":true,
                                            "threadSource":source, "createdAt":0, "hasUnreadTurn":unread,
                                            "sideConversationParentNavigationPath":"/local/\(fixture.chatID)",
                                            "forkedFromId":revision == 1 ? NSNull() : (revision == 2 ? excludedID : fixture.chatID) as Any,
                                            "threadRuntimeStatus":["type":runtime,"activeFlags":[]],
                                            "latestTurnStartMessageId":"side-turn"
                                        ]]]])
                }
                try announce(excludedID, viewer: "remote-viewer", host: "remote")
                try announce(sideID, viewer: "window-1")
                try announce(sideID, viewer: "window-2")
                try expect(sideID)
                // This chat predates the monitor and does not exist in SQLite.
                try snapshot(sideID, revision: 1, runtime: "idle", unread: true)
                // Force the normal database refresh, which must retain the live chat.
                try fixture.send(["type":"broadcast", "method":"thread-unarchived", "version":1,
                                  "sourceClientId":"fixture-owner", "params":["conversationId":fixture.chatID,"hostId":"local"]])
                try announce(sideID, viewer: "window-1", following: false)
                try snapshot(sideID, revision: 2, runtime: "active", unread: false)
                try fixture.send(["type":"broadcast", "method":"thread-read-state-changed", "version":3,
                                  "sourceClientId":"window-2", "params":["conversationId":sideID,"hostId":"local"]])
                try expect(sideID)
                try snapshot(sideID, revision: 3, runtime: "idle", unread: true)
                try announce(excludedID, viewer: "window-2")
                try expect(excludedID)
                try snapshot(excludedID, revision: 1, runtime: "active", unread: false, source: "subagent")
                try expect(excludedID, following: false)
                try announce(sideID, viewer: "window-2", following: false)
                try expect(sideID, following: false)
                Darwin.close(fixture.peer); fixture.peer = -1
            } catch { XCTFail("Live chat fixture failed: \(error)") }
        }
        let source = CodexSource(configuration: .init(codexHome: fixture.home))
        let finished = expectation(description: "live chat source disconnected")
        let collector = Task { () -> ([String], [Observation]) in
            var state = PulseState(now: Date(timeIntervalSince1970: 100))
            var labels: [String] = []
            var observations: [Observation] = []
            for await event in await source.observations() {
                state.apply(event)
                if state.snapshot.isFresh && labels.last != state.snapshot.menuLabel { labels.append(state.snapshot.menuLabel) }
                if case .observed(let value) = event { observations.append(value) }
                if case .health(.unavailable) = event { finished.fulfill(); break }
            }
            return (labels, observations)
        }
        await fulfillment(of: [finished, serverFinished], timeout: 8)
        collector.cancel()
        let (labels, observations) = await collector.value
        XCTAssertEqual(labels, ["0/0", "0/1", "1/2", "0/2", "1/2", "0/1"])
        XCTAssertEqual(observations.filter { $0.id.value == sideID }.map(\.title), Array(repeating: "Design the icon", count: 3))
        XCTAssertFalse(observations.contains { $0.id.value == excludedID })
        let sideObservations = observations.filter { $0.id.value == sideID }
        XCTAssertEqual(sideObservations.map { $0.parentID?.value }, [fixture.chatID, excludedID, fixture.chatID])
        XCTAssertTrue(sideObservations.allSatisfy { $0.isSideChat == true })
    }

    func testFragmentedStreamRevisionGapAndReadInvalidationRecoverThroughOwner() async throws {
        let fixture = try SocketFixture()
        defer { fixture.close() }
        let serverFinished = expectation(description: "fixture completed")
        DispatchQueue(label: "fixture.socket").async {
            defer { serverFinished.fulfill() }
            do { try fixture.serve() }
            catch { XCTFail("Fixture failed: \(error)") }
        }
        let source = CodexSource(configuration: .init(codexHome: fixture.home))
        let finished = expectation(description: "source reports disconnect")
        let collector = Task { () -> ([Observation], Int, Int) in
            let archived = TrackedChat(id: ChatID(value: "00000000-0000-4000-8000-000000000002"), title: "Archived while quit", generation: "old", phase: .working, isFresh: true, changedAt: Date())
            var restored = PulseState(restoring: SavedState(monitoringSince: Date(timeIntervalSince1970: 100), rows: [archived], baselines: []))
            var observations: [Observation] = []
            var stale = 0
            for await event in await source.observations() {
                restored.apply(event)
                switch event {
                case .observed(let value): observations.append(value)
                case .stale: stale += 1
                case .health(.unavailable):
                    finished.fulfill()
                    return (observations, stale, restored.snapshot.totalCount)
                default: break
                }
            }
            return (observations, stale, restored.snapshot.totalCount)
        }
        await fulfillment(of: [finished, serverFinished], timeout: 8)
        collector.cancel()
        let (observations, stale, remaining) = await collector.value
        XCTAssertEqual(remaining, 0, "Initial catalog must retire a restored chat archived while Pulse was quit")
        XCTAssertEqual(observations.map(\.runtime), [.active, .idle, .idle, .idle])
        XCTAssertEqual(observations.map(\.unread), [false, true, true, false])
        XCTAssertEqual(stale, 1, "A revision gap must invalidate before resnapshot")
        var state = PulseState(now: Date(timeIntervalSince1970: 100))
        state.apply(.health(.live))
        for observation in observations { state.apply(.observed(observation)) }
        XCTAssertEqual(state.snapshot.menuLabel, "0/0")
    }
}

private final class SocketFixture: @unchecked Sendable {
    let home = URL(fileURLWithPath: "/tmp/little-brain-\(UUID().uuidString.prefix(8))")
    let chatID = "00000000-0000-4000-8000-000000000001"
    var listener: Int32 = -1
    var peer: Int32 = -1
    init() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent("ipc"), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(home.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK else { throw FixtureError.failed }
        defer { sqlite3_close(db) }
        let sql = "CREATE TABLE threads(id TEXT,name TEXT,created_at INTEGER,updated_at INTEGER,source TEXT,originator TEXT,archived INTEGER); INSERT INTO threads VALUES('\(chatID)','Fixture chat',0,1,'vscode','Codex Desktop',0);"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.failed }
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = home.appendingPathComponent("ipc/ipc.sock").path
        withUnsafeMutableBytes(of: &address.sun_path) { target in path.utf8CString.withUnsafeBytes { target.copyBytes(from: $0) } }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(listener, 1) == 0 else { throw FixtureError.failed }
    }
    func close() {
        if peer >= 0 { Darwin.close(peer); peer = -1 }
        if listener >= 0 { Darwin.close(listener); listener = -1 }
        try? FileManager.default.removeItem(at: home)
    }
    func handshake() throws {
        var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&ready, 1, 5000) > 0 else { throw FixtureError.failed }
        peer = Darwin.accept(listener, nil, nil)
        guard peer >= 0 else { throw FixtureError.failed }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(peer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noPipe: Int32 = 1
        setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout<Int32>.size))
        let initMessage = try read()
        XCTAssertEqual(initMessage["method"] as? String, "initialize")
        try send(["type":"response", "method":"initialize", "result":["clientId":"fixture-follower"]], fragmented: true)
    }
    func serve() throws {
        try handshake()
        try expectFollow()
        try snapshot(revision: 1, runtime: "active", unread: false)
        try change(["type":"patches", "baseRevision":1, "revision":2, "patches":[["op":"add", "path":["turnHistory","unretained"], "value":"discard this body"]]])
        try change(["type":"patches", "baseRevision":2, "revision":3, "patches":[
            ["op":"replace", "path":["threadRuntimeStatus"], "value":["type":"idle"]],
            ["op":"replace", "path":["hasUnreadTurn"], "value":true]
        ]])
        try change(["type":"patches", "baseRevision":999, "revision":4, "patches":[["op":"replace", "path":["hasUnreadTurn"], "value":false]]])
        try expectFollow()
        try snapshot(revision: 4, runtime: "idle", unread: true)
        try send(["type":"broadcast", "method":"thread-read-state-changed", "version":3, "sourceClientId":"different-identity",
                  "params":["conversationId":chatID,"hostId":"local","hasUnreadTurn":false]])
        try expectFollow()
        try snapshot(revision: 5, runtime: "idle", unread: false)
        // Ensure the last frame is consumed before observing socket EOF.
        Thread.sleep(forTimeInterval: 0.1)
        Darwin.close(peer); peer = -1
    }
    func snapshot(revision: Int, runtime: String, unread: Bool) throws {
        try change(["type":"snapshot", "revision":revision, "conversationState":[
            "title":"Fixture chat", "threadRuntimeStatus":["type":runtime, "activeFlags":[]],
            "hasUnreadTurn":unread, "latestTurnStartMessageId":"turn-1",
            "turnHistory":["largeBody":"never retained"]
        ]])
    }
    func change(_ body: [String:Any]) throws {
        try send(["type":"broadcast", "method":"thread-stream-state-changed", "version":11, "sourceClientId":"fixture-owner",
                  "params":["conversationId":chatID,"hostId":"local","change":body]])
    }
    func expectFollow() throws {
        let message = try read()
        XCTAssertEqual(message["method"] as? String, "thread-stream-following-changed")
        XCTAssertEqual((message["params"] as? [String:Any])?["following"] as? Bool, true)
    }
    func send(_ object: [String:Any], fragmented: Bool = false) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var size = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }; frame.append(data)
        let pieces = fragmented ? [frame.prefix(2), frame.dropFirst(2)] : [frame[...]]
        for piece in pieces {
            try piece.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.send(peer, bytes.baseAddress!.advanced(by: offset), bytes.count-offset, 0)
                    guard written > 0 else { throw FixtureError.failed }; offset += written
                }
            }
        }
    }
    func read() throws -> [String:Any] {
        let header = Array(try exact(4))
        let count = Int(UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24)
        guard count < 1000000 else { throw FixtureError.failed }
        return try JSONSerialization.jsonObject(with: exact(count)) as! [String:Any]
    }
    func exact(_ count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            var bytes = [UInt8](repeating: 0, count: count-result.count)
            let received = Darwin.recv(peer, &bytes, bytes.count, 0)
            guard received > 0 else { throw FixtureError.failed }
            result.append(contentsOf: bytes.prefix(received))
        }
        return result
    }
    enum FixtureError: Error { case failed }
}
