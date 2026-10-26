import XCTest
@testable import LittleBrain

final class PulseStateTests: XCTestCase {
    let epoch = Date(timeIntervalSince1970: 1000)
    func chat(_ number: Int, runtime: Runtime = .active, unread: Bool = false, generation: String = "first", created: Double = 0) -> Observation {
        Observation(id: ChatID(value: String(format: "00000000-0000-4000-8000-%012d", number)), title: "Chat \(number)",
                    generation: generation, runtime: runtime, unread: unread, createdAt: Date(timeIntervalSince1970: created))
    }
    func testFiveChatsFinishAndViewingOneShrinksBothCounts() {
        var state = PulseState(now: epoch)
        state.apply(.health(.live))
        for n in 1...5 { state.apply(.observed(chat(n))) }
        XCTAssertEqual(state.snapshot.menuLabel, "0/5")
        state.apply(.observed(chat(1, runtime: .idle, unread: true)))
        XCTAssertEqual(state.snapshot.menuLabel, "1/5")
        XCTAssertEqual(state.snapshot.reviewRows.map(\.id), [chat(1).id])
        XCTAssertEqual(Set(state.snapshot.runningRows.map(\.id)), Set((2...5).map { chat($0).id }))
        for n in 1...5 { state.apply(.observed(chat(n, runtime: .idle, unread: true))) }
        XCTAssertEqual(state.snapshot.menuLabel, "5/5")
        XCTAssertTrue(state.snapshot.runningRows.isEmpty)
        state.apply(.observed(chat(1, runtime: .idle, unread: false)))
        XCTAssertEqual(state.snapshot.menuLabel, "4/4")
        // Replayed read events cannot remove another chat.
        state.apply(.observed(chat(1, runtime: .idle, unread: false)))
        XCTAssertEqual(state.snapshot.menuLabel, "4/4")
    }
    func testViewingRunningChatAndRerunningReadyChatKeepOneEntry() {
        var state = PulseState(now: epoch)
        state.apply(.observed(chat(1, unread: true)))
        state.apply(.observed(chat(1, unread: false)))
        XCTAssertEqual(state.snapshot.totalCount, 1)
        state.apply(.observed(chat(1, runtime: .idle, unread: true)))
        XCTAssertEqual(state.snapshot.readyCount, 1)
        state.apply(.observed(chat(1, generation: "second")))
        XCTAssertEqual(state.snapshot.totalCount, 1)
        XCTAssertEqual(state.snapshot.readyCount, 0)
        XCTAssertEqual(state.snapshot.workingCount, 1)
    }
    func testHistoricalBacklogExcludedButFastNewActivityAdmitted() {
        var state = PulseState(now: epoch)
        state.apply(.observed(chat(1, runtime: .idle, unread: true)))
        XCTAssertEqual(state.snapshot.totalCount, 0)
        state.apply(.observed(chat(1, runtime: .idle, unread: true, generation: "new")))
        XCTAssertEqual(state.snapshot.readyCount, 1)
        state.apply(.observed(chat(2, runtime: .idle, unread: true, created: 1001)))
        XCTAssertEqual(state.snapshot.readyCount, 2)
    }
    func testRestartRetainsUnreadAndWaitsForFreshReadEvidence() throws {
        var state = PulseState(now: epoch)
        state.apply(.observed(chat(1)))
        state.apply(.observed(chat(1, runtime: .idle, unread: true)))
        let data = try JSONEncoder().encode(state.saved)
        var restored = PulseState(restoring: try JSONDecoder().decode(SavedState.self, from: data))
        XCTAssertEqual(restored.snapshot.menuLabel, "—/1")
        restored.apply(.health(.live))
        XCTAssertEqual(restored.snapshot.menuLabel, "—/1")
        restored.apply(.observed(chat(1, runtime: .idle, unread: true)))
        XCTAssertEqual(restored.snapshot.menuLabel, "1/1")
        restored.apply(.observed(chat(1, runtime: .idle, unread: false)))
        XCTAssertEqual(restored.snapshot.menuLabel, "0/0")
    }
    func testDisconnectAndNotLoadedNeverInventCompletion() {
        var state = PulseState(now: epoch)
        state.apply(.health(.live))
        state.apply(.observed(chat(1)))
        state.apply(.health(.unavailable("offline")))
        XCTAssertEqual(state.snapshot.menuLabel, "—/1")
        XCTAssertEqual(state.snapshot.readyCount, 0)
        state.apply(.health(.live))
        state.apply(.observed(chat(1, runtime: .unavailable)))
        XCTAssertEqual(state.snapshot.menuLabel, "—/1")
        state.apply(.observed(chat(1, runtime: .idle, unread: true)))
        XCTAssertEqual(state.snapshot.menuLabel, "1/1")
        state.apply(.catalog([]))
        XCTAssertEqual(state.snapshot.menuLabel, "0/0")
    }
    func testApprovalAndErrorsAreNotSuccessfulCompletions() {
        var state = PulseState(now: epoch)
        state.apply(.observed(chat(2)))
        state.apply(.observed(chat(1, runtime: .waiting)))
        XCTAssertEqual(state.snapshot.reviewRows.map(\.id), [chat(1).id])
        XCTAssertEqual(state.snapshot.runningRows.map(\.id), [chat(2).id])
        XCTAssertEqual(state.snapshot.attentionCount, 1)
        XCTAssertEqual(state.snapshot.readyCount, 0)
        state.apply(.observed(chat(1, runtime: .systemError, unread: true)))
        XCTAssertEqual(state.snapshot.reviewRows.map(\.id), [chat(1).id])
        XCTAssertEqual(state.snapshot.attentionCount, 1)
        XCTAssertEqual(state.snapshot.readyCount, 0)
    }
}
