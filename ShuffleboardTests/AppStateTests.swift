import Foundation
@testable import Shuffleboard
import XCTest

/// `AppState` behaviour against `StubURLProtocol`, with credentials kept in memory.
@MainActor
final class AppStateTests: XCTestCase {
    private var store: InMemoryCredentialStore!
    private let boardsJSON = #"[{"id": 1, "title": "One", "archived": false}, {"id": 2, "title": "Two", "archived": false}]"#

    override func setUp() async throws {
        StubURLProtocol.reset()
        store = .signedIn()
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
    }

    private static func stacksJSON(_ ids: [Int], board: Int) -> String {
        "[" + ids.enumerated().map { index, id in
            #"{"id": \#(id), "title": "S\#(id)", "boardId": \#(board), "order": \#(index), "cards": []}"#
        }.joined(separator: ",") + "]"
    }

    private static func boardId(fromStacksPath path: String) -> Int? {
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
            if request.path.hasSuffix("/boards") { return .json(self.boardsJSON) }
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
            if request.path.hasSuffix("/boards") { return .json(self.boardsJSON) }
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
            request.path.hasSuffix("/boards") ? .json(self.boardsJSON) : .status(401)
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
            if request.path.hasSuffix("/boards") { return .json(self.boardsJSON) }
            if request.method == "DELETE" { return .status(403) }
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
            if request.path.hasSuffix("/boards") { return .json(self.boardsJSON) }
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
            if request.path.hasSuffix("/apppassword") { return StubResponse(error: URLError(.notConnectedToInternet)) }
            if request.path.hasSuffix("/boards") { return .json(self.boardsJSON) }
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
        let lock = NSLock()
        nonisolated(unsafe) var serverOrder = [10, 20, 30, 40]
        StubURLProtocol.handler = { request in
            if request.path.hasSuffix("/boards") { return .json(self.boardsJSON) }
            if request.method == "PUT" {
                guard let id = Int(request.path.split(separator: "/").last ?? ""), id != 10 else { return .status(500) }
                let order = request.json?["order"] as? Int ?? 0
                lock.withLock {
                    serverOrder.removeAll { $0 == id }
                    serverOrder.insert(id, at: min(order, serverOrder.count))
                }
                return .json(#"{"id": \#(id), "title": "S", "boardId": 1, "order": \#(order)}"#)
            }
            return .json(Self.stacksJSON(lock.withLock { serverOrder }, board: 1))
        }
        let app = await makeSignedInApp()
        XCTAssertEqual(app.stacks.map(\.id), [10, 20, 30, 40])

        // Move the last list to the front: 40 is saved, then 10's update fails.
        await app.reorderStacks(boardId: 1, fromIndex: 3, toIndex: 0)

        let puts = StubURLProtocol.requests.filter { $0.method == "PUT" }.map { $0.path.split(separator: "/").last }
        XCTAssertEqual(puts, ["40", "10"], "stops after the failed update")
        XCTAssertNotNil(app.actionError)
        XCTAssertEqual(app.stacks.map(\.id), lock.withLock { serverOrder }, "the board shows what the server saved")
    }
}
