import XCTest
@testable import LittleBrain

final class PulseStateTests: XCTestCase {
    let epoch = Date(timeIntervalSince1970: 1000)
    func chat(_ number: Int, runtime: Runtime = .active, unread: Bool = false, generation: String = "first", created: Double = 0) -> Observation {
        Observation(id: ChatID(value: String(format: "00000000-0000-4000-8000-%012d", number)), title: "Chat \(number)",
                    generation: generation, runtime: runtime, unread: unread, createdAt: Date(timeIntervalSince1970: created))
    }
    func testNestedChatsKeepTheirParentsAcrossSectionsAndRestartWithoutInflatingCounts() throws {
        var state = PulseState(now: epoch)
        state.apply(.health(.live))
        var main = chat(1)
        var side = chat(2, runtime: .idle, unread: true)
        side.title = main.title
        side.parentID = main.id; side.isSideChat = true; side.isEphemeral = true
        var nested = chat(3)
        nested.title = main.title
        nested.parentID = side.id; nested.isSideChat = true; nested.isEphemeral = true
        for observation in [main, side, nested] { state.apply(.observed(observation)) }
        XCTAssertEqual(state.snapshot.menuLabel, "1/3")
        XCTAssertEqual(state.snapshot.reviewOutline.map(\.id), [main.id, side.id])
        XCTAssertEqual(state.snapshot.reviewOutline.compactMap(\.chat).map(\.id), [side.id])
        XCTAssertEqual(state.snapshot.runningOutline.map(\.id), [main.id, side.id, nested.id])
        XCTAssertEqual(state.snapshot.runningOutline.map(\.depth), [0, 1, 2])
        XCTAssertEqual(state.snapshot.runningOutline.map { $0.context.displayTitle }, ["Chat 1", "Side chat", "Side chat"])
        XCTAssertEqual(state.snapshot.runningOutline.compactMap(\.chat).map(\.id), [main.id, nested.id])
        XCTAssertEqual(state.snapshot.displayedRowCount, 5)

        main.runtime = .idle
        side.unread = false
        state.apply(.observed(main)); state.apply(.observed(side))
        XCTAssertEqual(state.snapshot.menuLabel, "0/1")
        XCTAssertEqual(state.snapshot.runningOutline.compactMap(\.chat).map(\.id), [nested.id])
        let saved = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state.saved))
        var restored = PulseState(restoring: saved)
        // Closed ancestors remain labels while a descendant is still tracked.
        restored.apply(.catalog([nested.id: nested.title]))
        XCTAssertEqual(restored.snapshot.runningOutline.map(\.depth), [0, 1, 2])
        XCTAssertEqual(restored.snapshot.runningOutline.map { $0.context.displayTitle }, ["Chat 1", "Side chat", "Side chat"])
        XCTAssertEqual(restored.snapshot.totalCount, 1)
        restored.apply(.catalog([:]))
        XCTAssertTrue(restored.snapshot.runningOutline.isEmpty)
    }

    func testHierarchyUsesCatalogTitlesAndDoesNotLoseChatsWithBrokenAncestry() {
        var state = PulseState(now: epoch)
        let main = chat(1)
        var side = chat(2)
        side.parentID = main.id; side.isSideChat = true
        state.apply(.catalog([main.id: "Saved main chat", side.id: side.title]))
        state.apply(.observed(side))
        XCTAssertEqual(state.snapshot.runningOutline.map { $0.context.displayTitle }, ["Saved main chat", "Side chat"])
        XCTAssertNil(state.snapshot.runningOutline.first?.chat)
        XCTAssertEqual(state.snapshot.totalCount, 1)
        state.apply(.catalog([side.id: side.title]))
        XCTAssertEqual(state.snapshot.runningOutline.map { $0.context.displayTitle }, ["Main chat", "Side chat"])

        var parent = main
        parent.parentID = side.id; parent.isSideChat = true
        state.apply(.observed(parent))
        let outline = state.snapshot.runningOutline
        XCTAssertEqual(Set(outline.map(\.id)), Set([main.id, side.id]))
        XCTAssertEqual(outline.count, 2)
        XCTAssertEqual(outline.compactMap(\.chat).count, 2)
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

    func testOverflowPagesKeepEveryChatAndRepeatParentContext() {
        var state = PulseState(now: epoch)
        let main = chat(1)
        state.apply(.observed(main))
        for number in 2...10 {
            var side = chat(number)
            side.parentID = main.id; side.isSideChat = true
            state.apply(.observed(side))
        }
        state.apply(.observed(chat(11, runtime: .waiting)))
        let expected = Set((1...11).map { chat($0).id })
        for limit in 1...15 {
            let pages = state.snapshot.pages(rowLimit: limit)
            XCTAssertTrue(pages.allSatisfy { $0.count <= limit && $0.count > 0 })
            let actual = pages.flatMap { ($0.review + $0.running).compactMap(\.chat).map(\.id) }
            XCTAssertEqual(Set(actual), expected)
            XCTAssertEqual(actual.count, 11, "Repeated parent labels must not become tracked rows")
            for page in pages.dropFirst() where limit > 1 {
                XCTAssertEqual(page.running.first?.id, main.id)
                XCTAssertNil(page.running.first?.chat)
                XCTAssertTrue(page.running.dropFirst().allSatisfy { $0.depth == 1 && $0.chat != nil })
            }
        }
        XCTAssertEqual(state.snapshot.pages(rowLimit: 20).count, 1)
        let empty = PulseSnapshot(rows: [], health: .live).pages(rowLimit: 10)
        XCTAssertEqual(empty.count, 1)
        XCTAssertEqual(empty[0].count, 0)
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
        state.apply(.catalog([:]))
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
