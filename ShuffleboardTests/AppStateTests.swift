import Foundation
import XCTest
@testable import Shuffleboard

/// `AppState` behaviour against `StubURLProtocol`, with credentials kept in memory.
@MainActor
final class AppStateTests: XCTestCase {
    private var store: InMemoryCredentialStore!
    private nonisolated static let boardsJSON = #"[{"id": 1, "title": "One", "archived": false}, {"id": 2, "title": "Two", "archived": false}]"#

    override func setUp() async throws {
        StubURLProtocol.reset()
        store = .signedIn()
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
    }

    private nonisolated static func stacksJSON(_ ids: [Int], board: Int) -> String {
        "[" + ids.enumerated().map { index, id in
            #"{"id": \#(id), "title": "S\#(id)", "boardId": \#(board), "order": \#(index), "cards": []}"#
        }.joined(separator: ",") + "]"
    }

    private nonisolated static func boardId(fromStacksPath path: String) -> Int? {
        let parts = path.split(separator: "/")
        guard let index = parts.firstIndex(of: "boards"), parts.last == "stacks" else { return nil }
        return Int(parts[parts.index(after: index)])
    }

    /// An `AppState` signed in against the stub, with board 1 selected and its lists loaded.
    private func makeSignedInApp() async -> AppState {
        let app = AppState(credentialStore: store, session: StubURLProtocol.session(), openURL: { _ in })
        await waitUntil { app.selectedBoardId == 1 && !app.isLoading }
        await app.loadStacks(boardId: 1)
        return app
    }

    // MARK: - Lists (#56)

    func testSlowResponseForPreviousBoardDoesNotReplaceCurrentBoard() async {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            guard let board = Self.boardId(fromStacksPath: request.path) else { return .status(404) }
            return .json(Self.stacksJSON([board * 10], board: board), delay: board == 1 ? 0.5 : 0.05)
        }
        let app = await makeSignedInApp()

        let slow = Task { await app.loadStacks(boardId: 1) }
        await sleep(seconds: 0.05)
        app.selectBoard(app.boards[1])
        await app.loadStacks(boardId: 2)
        await slow.value

        XCTAssertEqual(app.stacks.map(\.boardId), [2])
        XCTAssertFalse(app.isLoadingStacks)
    }

    func testRefreshingSameBoardKeepsListsVisible() async {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            return .json(Self.stacksJSON([10, 20], board: 1), delay: 0.3)
        }
        let app = await makeSignedInApp()

        let refresh = Task { await app.loadStacks(boardId: 1) }
        await sleep(seconds: 0.1)
        XCTAssertTrue(app.isLoadingStacks)
        XCTAssertEqual(app.stacks.map(\.id), [10, 20], "lists must not flash empty while refreshing")
        await refresh.value
    }

    // MARK: - Ended session (#57)

    func testUnauthorizedSignsOutAndClearsCredentials() async {
        StubURLProtocol.handler = { request in
            request.path.hasSuffix("/boards") ? .json(Self.boardsJSON) : .status(401)
        }
        let app = await makeSignedInApp()

        await app.deleteCard(boardId: 1, stackId: 10, cardId: 5)

        XCTAssertFalse(app.isLoggedIn)
        XCTAssertTrue(app.showingLogin)
        XCTAssertNil(store.credentials)
        XCTAssertNil(app.actionError)
        XCTAssertNotNil(app.errorMessage, "the login screen explains why")
    }

    func testForbiddenShowsBannerAndStaysSignedIn() async {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            if request.method == "DELETE" {
                return .status(403)
            }
            return .json(Self.stacksJSON([10], board: 1))
        }
        let app = await makeSignedInApp()

        await app.deleteCard(boardId: 1, stackId: 10, cardId: 5)

        XCTAssertTrue(app.isLoggedIn)
        XCTAssertEqual(app.actionError, DeckAPIError.permissionDenied.localizedDescription)
    }

    // MARK: - Sign out (#58)

    func testSignOutRevokesAppPassword() async {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            return .json(Self.stacksJSON([10], board: 1))
        }
        let app = await makeSignedInApp()

        await app.signOut()

        XCTAssertFalse(app.isLoggedIn)
        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertTrue(StubURLProtocol.requests.contains { $0.line == "DELETE /ocs/v2.php/core/apppassword" })
    }

    func testSignOutSucceedsOffline() async {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/apppassword") {
                return StubResponse(error: URLError(.notConnectedToInternet))
            }
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            return .json(Self.stacksJSON([10], board: 1))
        }
        let app = await makeSignedInApp()

        await app.signOut()

        XCTAssertFalse(app.isLoggedIn)
        XCTAssertNil(app.actionError)
        XCTAssertNil(app.errorMessage)
    }

    // MARK: - List reorder (#60)

    func testFailedReorderStopsAndReloads() async {
        let serverOrder = Locked([10, 20, 30, 40])
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            if request.method == "PUT" {
                guard let id = Int(request.path.split(separator: "/").last ?? ""), id != 10 else { return .status(500) }
                let order = request.json?["order"] as? Int ?? 0
                serverOrder.withLock { ids in
                    ids.removeAll { $0 == id }
                    ids.insert(id, at: min(order, ids.count))
                }
                return .json(#"{"id": \#(id), "title": "S", "boardId": 1, "order": \#(order)}"#)
            }
            return .json(Self.stacksJSON(serverOrder.withLock { $0 }, board: 1))
        }
        let app = await makeSignedInApp()
        XCTAssertEqual(app.stacks.map(\.id), [10, 20, 30, 40])

        // Move the last list to the front: 40 is saved, then 10's update fails.
        await app.reorderStacks(boardId: 1, fromIndex: 3, toIndex: 0)

        let puts = StubURLProtocol.requests.filter { $0.method == "PUT" }.map { $0.path.split(separator: "/").last }
        XCTAssertEqual(puts, ["40", "10"], "stops after the failed update")
        XCTAssertNotNil(app.actionError)
        XCTAssertEqual(app.stacks.map(\.id), serverOrder.withLock { $0 }, "the board shows what the server saved")
    }

    // MARK: - Due dates and done state (#73)

    private nonisolated static let cardJSON = """
    {"id": 5, "title": "Card", "stackId": 10, "order": 0, "archived": false, "owner": "rob"}
    """

    func testSavingTheSheetSendsDueDateAndDone() async throws {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            if request.method == "PUT" {
                return .json(Self.cardJSON)
            }
            return .json(Self.stacksJSON([10], board: 1))
        }
        let app = await makeSignedInApp()
        let card = try JSONDecoder().decode(Card.self, from: Data(Self.cardJSON.utf8))
        let due = try XCTUnwrap(DeckDate.parse("2026-10-10T12:00:00+00:00"))

        let saved = await app.updateCard(
            boardId: 1,
            stackId: 10,
            card: card,
            edits: CardEdits(title: "Card", description: "", dueDate: due, isDone: true)
        )

        XCTAssertTrue(saved)
        let put = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "PUT" })
        XCTAssertEqual(put.path, "/index.php/apps/deck/api/v1.0/boards/1/stacks/10/cards/5")
        XCTAssertEqual(DeckDate.parse(put.json?["duedate"] as? String), due)
        XCTAssertNotNil(DeckDate.parse(put.json?["done"] as? String))
    }

    func testMarkingDoneFromTheBoard() async throws {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            if request.method == "PUT" {
                return .json(Self.cardJSON)
            }
            return .json(Self.stacksJSON([10], board: 1))
        }
        let app = await makeSignedInApp()
        let card = try JSONDecoder().decode(Card.self, from: Data(Self.cardJSON.utf8))

        await app.setCardDone(boardId: 1, card: card, done: true)

        let put = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "PUT" })
        XCTAssertNotNil(DeckDate.parse(put.json?["done"] as? String))
        XCTAssertNil(app.actionError)
    }

    // MARK: - Assignments (#74)

    func testAssigningReportsErrorsInTheBanner() async throws {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            if request.path.hasSuffix("/assignUser") {
                return .json(#"{"status": 400, "message": "The user is not part of the board"}"#, status: 400)
            }
            return .json(Self.stacksJSON([10], board: 1))
        }
        let app = await makeSignedInApp()
        let card = try JSONDecoder().decode(Card.self, from: Data(Self.cardJSON.utf8))

        await app.assignUser(DeckUser(uid: "mallory"), boardId: 1, card: card)

        XCTAssertEqual(app.actionError, "The user is not part of the board")
    }

    // MARK: - Automatic refresh (#79)

    /// A fake Deck server whose ETags change whenever its data does.
    private final class FakeDeck: Sendable {
        struct State {
            var boardIds = [1, 2]
            var stackIds = [10, 20]
            var version = 1
            var stacksStatus = 200
        }

        let state = Locked(State())

        func handle(_ request: RecordedRequest) -> StubResponse {
            let current = state.withLock { $0 }
            let etag = "\"v\(current.version)\""
            if request.path.hasSuffix("/boards") {
                if request.header("If-None-Match") == etag {
                    return .status(304)
                }
                let boards = current.boardIds.map { #"{"id": \#($0), "title": "B\#($0)", "archived": false}"# }
                return StubResponse(body: Data("[\(boards.joined(separator: ","))]".utf8), headers: ["ETag": etag])
            }
            if current.stacksStatus != 200 {
                return .status(current.stacksStatus)
            }
            if request.header("If-None-Match") == etag {
                return .status(304)
            }
            return StubResponse(
                body: Data(AppStateTests.stacksJSON(current.stackIds, board: 1).utf8),
                headers: ["ETag": etag]
            )
        }
    }

    private func makeFakeDeckApp() async -> (AppState, FakeDeck) {
        let deck = FakeDeck()
        StubURLProtocol.handler = { deck.handle($0) }
        return await (makeSignedInApp(), deck)
    }

    func testRefreshPicksUpChangesMadeElsewhere() async {
        let (app, deck) = await makeFakeDeckApp()
        XCTAssertEqual(app.stacks.map(\.id), [10, 20])

        deck.state.withLock { $0.stackIds = [10, 20, 30]
            $0.version = 2
        }
        await app.refreshIfChanged()

        XCTAssertEqual(app.stacks.map(\.id), [10, 20, 30])
        XCTAssertFalse(app.isLoadingStacks)
    }

    func testUnchangedRefreshIsAConditionalNoOp() async {
        let (app, _) = await makeFakeDeckApp()
        let before = StubURLProtocol.requests.count

        await app.refreshIfChanged()

        let refreshRequests = StubURLProtocol.requests.dropFirst(before)
        XCTAssertEqual(refreshRequests.count, 2, "one conditional request for boards, one for lists")
        XCTAssertTrue(refreshRequests.allSatisfy { $0.header("If-None-Match") == "\"v1\"" })
        XCTAssertEqual(app.stacks.map(\.id), [10, 20])
    }

    func testRefreshErrorsAreSilent() async {
        let (app, deck) = await makeFakeDeckApp()
        deck.state.withLock { $0.stacksStatus = 500 }

        await app.refreshIfChanged()

        XCTAssertNil(app.actionError)
        XCTAssertNil(app.stacksError)
        XCTAssertEqual(app.stacks.map(\.id), [10, 20], "keeps the lists it has")
    }

    func testRefreshMovesOffABoardDeletedElsewhere() async {
        let (app, deck) = await makeFakeDeckApp()
        deck.state.withLock { $0.boardIds = [2]
            $0.version = 2
        }

        await app.refreshIfChanged()

        XCTAssertEqual(app.selectedBoardId, 2)
    }

    func testRefreshSignsOutWhenThePasswordIsRevoked() async {
        let (app, _) = await makeFakeDeckApp()
        StubURLProtocol.handler = { _ in .status(401) }

        await app.refreshIfChanged()

        XCTAssertFalse(app.isLoggedIn)
        XCTAssertNil(store.credentials)
    }

    // MARK: - Comments (#75)

    func testCommentFailuresGoToTheBanner() async throws {
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") {
                return .json(Self.boardsJSON)
            }
            if request.path.contains("/comments") {
                return .json(#"{"ocs": {"meta": {"message": "Comment too long"}, "data": []}}"#, status: 400)
            }
            return .json(Self.stacksJSON([10], board: 1))
        }
        let app = await makeSignedInApp()
        let card = try JSONDecoder().decode(Card.self, from: Data(Self.cardJSON.utf8))

        let comment = await app.addComment("x", to: card)

        XCTAssertNil(comment)
        XCTAssertEqual(app.actionError, "Comment too long")
        XCTAssertEqual(app.currentUserId, "rob", "edit/delete are offered on the signed-in user's own comments")
    }
}
