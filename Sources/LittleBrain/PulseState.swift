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
    case catalog(Set<ChatID>)
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
}

struct PulseSnapshot: Equatable, Sendable {
    let rows: [TrackedChat]
    let health: SourceHealth
    var readyCount: Int { rows.filter { $0.phase == .ready }.count }
    var workingCount: Int { rows.filter { $0.phase == .working }.count }
    var attentionCount: Int { rows.filter { $0.phase == .waiting || $0.phase == .error }.count }
    var totalCount: Int { rows.count }
    var isFresh: Bool { health.isLive && rows.allSatisfy(\.isFresh) }
    var menuLabel: String { isFresh ? "\(readyCount)/\(totalCount)" : "—/\(totalCount)" }
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
        case .catalog(let ids):
            tracked = tracked.filter { ids.contains($0.key) }
            baselines = baselines.filter { ids.contains($0.key) }
        case .observed(let observation):
            let prior = baselines[observation.id]
            let existing = tracked[observation.id]
            let newGeneration = prior != nil && observation.generation != nil && prior?.generation != observation.generation
            let becameUnread = prior?.unread == false && observation.unread
            let newlyCreated = observation.createdAt >= monitoringSince
            let shouldTrack = existing != nil || newGeneration || becameUnread || newlyCreated
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
                changedAt: existing?.phase == phase ? existing!.changedAt : now
            )
        }
    }

    var snapshot: PulseSnapshot {
        PulseSnapshot(rows: tracked.values.sorted {
            if $0.phase == .ready && $1.phase != .ready { return true }
            if $1.phase == .ready && $0.phase != .ready { return false }
            if $0.changedAt != $1.changedAt { return $0.changedAt > $1.changedAt }
            return $0.id.value < $1.id.value
        }, health: health)
    }

    var saved: SavedState {
        SavedState(monitoringSince: monitoringSince, rows: Array(tracked.values), baselines: Array(baselines.values))
    }
}
