import Foundation

struct ChatID: Hashable, Codable, Sendable {
    let value: String
    var url: URL? {
        guard UUID(uuidString: value) != nil else { return nil }
        return URL(string: "codex://threads/\(value)")
    }
}

enum Runtime: String, Codable, Sendable {
    case active, idle, waiting, systemError, unavailable
}

struct Observation: Equatable, Codable, Sendable {
    let id: ChatID
    var title: String
    var generation: String?
    var runtime: Runtime
    var unread: Bool
    var createdAt: Date
    var isEphemeral: Bool? = nil
    var parentID: ChatID? = nil
    var isSideChat: Bool? = nil
}

enum SourceHealth: Equatable, Sendable {
    case connecting, live, unavailable(String)
    var message: String {
        switch self {
        case .connecting: return "Connecting to Codex…"
        case .live: return "Live · local chats"
        case .unavailable(let reason): return reason
        }
    }
    var isLive: Bool { self == .live }
}

enum SourceEvent: Sendable {
    case observed(Observation)
    case catalog([ChatID: String])
    case stale(ChatID)
    case health(SourceHealth)
}

enum TrackedPhase: String, Codable, Sendable {
    case working, ready, waiting, error, unknown
    var label: String {
        switch self {
        case .working: return "Active"
        case .ready: return "Unread"
        case .waiting: return "Needs your input"
        case .error: return "Check this chat"
        case .unknown: return "Status unavailable"
        }
    }
}

struct TrackedChat: Identifiable, Equatable, Codable, Sendable {
    let id: ChatID
    var title: String
    var generation: String?
    var phase: TrackedPhase
    var isFresh: Bool
    var changedAt: Date
    var parentID: ChatID? = nil
    var isSideChat: Bool? = nil
}

struct ChatContext: Equatable, Identifiable, Sendable {
    let id: ChatID
    var title: String
    var parentID: ChatID? = nil
    var isSideChat = false
    var displayTitle: String { isSideChat ? "Side chat" : title }
}

struct ChatOutlineRow: Equatable, Identifiable {
    let context: ChatContext
    let chat: TrackedChat?
    let depth: Int
    var id: ChatID { context.id }
}

struct ChatPage {
    var review: [ChatOutlineRow] = []
    var running: [ChatOutlineRow] = []
    var count: Int { review.count + running.count }
}

struct PulseSnapshot: Equatable, Sendable {
    let rows: [TrackedChat]
    let health: SourceHealth
    var contexts: [ChatID: ChatContext] = [:]
    var reviewOutline: [ChatOutlineRow] { outline(for: reviewRows) }
    var runningOutline: [ChatOutlineRow] { outline(for: runningRows) }
    var displayedRowCount: Int { reviewOutline.count + runningOutline.count }
    var reviewRows: [TrackedChat] { rows.filter { $0.phase == .ready || $0.phase == .waiting || $0.phase == .error } }
    var runningRows: [TrackedChat] { rows.filter { $0.phase == .working || $0.phase == .unknown } }
    var readyCount: Int { rows.filter { $0.phase == .ready }.count }
    var workingCount: Int { rows.filter { $0.phase == .working }.count }
    var attentionCount: Int { rows.filter { $0.phase == .waiting || $0.phase == .error }.count }
    var totalCount: Int { rows.count }
    var isFresh: Bool { health.isLive && rows.allSatisfy(\.isFresh) }
    var menuLabel: String { isFresh ? "\(readyCount)/\(totalCount)" : "—/\(totalCount)" }

    func pages(rowLimit: Int) -> [ChatPage] {
        let limit = max(1, rowLimit)
        var result: [ChatPage] = []
        var page = ChatPage()
        for (rows, key) in [(reviewOutline, \ChatPage.review), (runningOutline, \ChatPage.running)] {
            var ancestors: [ChatOutlineRow] = []
            for row in rows {
                ancestors.removeAll { $0.depth >= row.depth }
                if page.count == limit {
                    result.append(page)
                    page = ChatPage()
                    // Repeat parent labels so a continued side chat keeps its context.
                    page[keyPath: key] = ancestors.suffix(limit - 1).map {
                        ChatOutlineRow(context: $0.context, chat: nil, depth: $0.depth)
                    }
                }
                page[keyPath: key].append(row)
                ancestors.append(row)
            }
        }
        if page.count > 0 || result.isEmpty { result.append(page) }
        return result
    }

    private func outline(for members: [TrackedChat]) -> [ChatOutlineRow] {
        var known = contexts
        for row in rows {
            known[row.id] = ChatContext(id: row.id, title: row.title, parentID: row.parentID, isSideChat: row.isSideChat == true)
        }
        let membersByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        var order: [ChatID] = []
        var included: Set<ChatID> = []
        for member in members {
            var cursor: ChatID? = member.id
            while let id = cursor, included.insert(id).inserted {
                order.append(id)
                cursor = known[id]?.parentID
            }
        }
        var children: [ChatID: [ChatID]] = [:]
        var roots: [ChatID] = []
        for id in order {
            if let parent = known[id]?.parentID, included.contains(parent) {
                children[parent, default: []].append(id)
            } else { roots.append(id) }
        }
        var result: [ChatOutlineRow] = []
        var visited: Set<ChatID> = []
        func append(_ id: ChatID, depth: Int) {
            guard visited.insert(id).inserted else { return }
            let context = known[id] ?? ChatContext(id: id, title: "Main chat")
            result.append(ChatOutlineRow(context: context, chat: membersByID[id], depth: depth))
            for child in children[id] ?? [] { append(child, depth: depth + 1) }
        }
        for id in roots { append(id, depth: 0) }
        // Malformed ancestry must not hide chats or recurse forever.
        for id in order where !visited.contains(id) { append(id, depth: 0) }
        return result
    }
}

struct SavedState: Codable {
    var version = 1
    var monitoringSince: Date
    var rows: [TrackedChat]
    var baselines: [Observation]
}

struct PulseState {
    private var tracked: [ChatID: TrackedChat] = [:]
    private var baselines: [ChatID: Observation] = [:]
    private var catalogTitles: [ChatID: String] = [:]
    private var health: SourceHealth = .connecting
    private let monitoringSince: Date

    init(restoring saved: SavedState? = nil, now: Date = Date()) {
        monitoringSince = saved?.monitoringSince ?? now
        for var row in saved?.rows ?? [] {
            row.isFresh = false
            tracked[row.id] = row
        }
        for baseline in saved?.baselines ?? [] { baselines[baseline.id] = baseline }
    }

    mutating func apply(_ event: SourceEvent, now: Date = Date()) {
        switch event {
        case .health(let value):
            health = value
            if !value.isLive { for id in tracked.keys { tracked[id]?.isFresh = false } }
        case .stale(let id): tracked[id]?.isFresh = false
        case .catalog(let titles):
            catalogTitles = titles
            let ids = Set(titles.keys)
            tracked = tracked.filter { ids.contains($0.key) }
            var retained = ids
            for row in tracked.values {
                var parent = row.parentID
                var visited: Set<ChatID> = []
                while let id = parent, visited.insert(id).inserted {
                    retained.insert(id)
                    parent = baselines[id]?.parentID
                }
            }
            baselines = baselines.filter { retained.contains($0.key) }
        case .observed(let observation):
            let prior = baselines[observation.id]
            let existing = tracked[observation.id]
            let newGeneration = prior != nil && observation.generation != nil && prior?.generation != observation.generation
            let becameUnread = prior?.unread == false && observation.unread
            let newlyCreated = observation.createdAt >= monitoringSince
            let shouldTrack = existing != nil || newGeneration || becameUnread || newlyCreated || observation.isEphemeral == true
            let phase: TrackedPhase
            switch observation.runtime {
            case .active: phase = .working
            case .waiting: phase = .waiting
            case .idle:
                guard shouldTrack && observation.unread else {
                    tracked.removeValue(forKey: observation.id)
                    baselines[observation.id] = observation
                    return
                }
                phase = .ready
            case .systemError:
                guard shouldTrack else { baselines[observation.id] = observation; return }
                phase = .error
            case .unavailable:
                // Lack of authority never becomes completion or a read receipt.
                if existing != nil { tracked[observation.id]?.isFresh = false }
                return
            }
            baselines[observation.id] = observation
            tracked[observation.id] = TrackedChat(
                id: observation.id, title: observation.title, generation: observation.generation,
                phase: phase, isFresh: true,
                changedAt: existing?.phase == phase ? existing!.changedAt : now,
                parentID: observation.parentID, isSideChat: observation.isSideChat
            )
        }
    }

    var snapshot: PulseSnapshot {
        var contexts: [ChatID: ChatContext] = [:]
        for (id, title) in catalogTitles { contexts[id] = ChatContext(id: id, title: title) }
        for observation in baselines.values {
            contexts[observation.id] = ChatContext(id: observation.id, title: observation.title,
                                                  parentID: observation.parentID, isSideChat: observation.isSideChat == true)
        }
        return PulseSnapshot(rows: tracked.values.sorted {
            if $0.phase == .ready && $1.phase != .ready { return true }
            if $1.phase == .ready && $0.phase != .ready { return false }
            if $0.changedAt != $1.changedAt { return $0.changedAt > $1.changedAt }
            return $0.id.value < $1.id.value
        }, health: health, contexts: contexts)
    }

    var saved: SavedState {
        SavedState(monitoringSince: monitoringSince, rows: Array(tracked.values), baselines: Array(baselines.values))
    }
}
