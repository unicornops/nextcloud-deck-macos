import Foundation
import XCTest
@testable import Shuffleboard

/// Multiple accounts (#81): what is saved, and switching, adding and signing out of accounts.
@MainActor
final class AccountTests: XCTestCase {
    private nonisolated static let robBoards = #"[{"id": 1, "title": "Rob's", "archived": false}]"#
    private nonisolated static let aliceBoards = #"[{"id": 7, "title": "Alice's", "archived": false}]"#

    override func setUp() async throws {
        StubURLProtocol.reset()
        // Each user's boards, told apart by their Basic auth header; everything else is empty.
        StubURLProtocol.handler = { request in
            guard request.path.hasSuffix("/boards") else { return .json("[]") }
            let isAlice = request.header("Authorization") == Self.basic("alice")
            return .json(isAlice ? Self.aliceBoards : Self.robBoards)
        }
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
    }

    private nonisolated static func basic(_ username: String) -> String {
        "Basic " + Data("\(username):\(username)-app-password".utf8).base64EncodedString()
    }

    private func makeApp(_ store: InMemoryCredentialStore) async -> AppState {
        let app = AppState(credentialStore: store, session: StubURLProtocol.session(), openURL: { _ in })
        await waitUntil { !app.isLoading && !app.boards.isEmpty }
        return app
    }

    private func credentials(_ username: String, server: URL = testServer) -> Credentials {
        Credentials(serverURL: server, username: username, appPassword: "\(username)-app-password")
    }

    // MARK: - Saved accounts

    func testEarlierSingleAccountFormatStillSignsIn() throws {
        let legacy = #"{"serverURL": "https://cloud.example", "username": "rob", "appPassword": "pw"}"#
        let saved = try JSONDecoder().decode(SavedAccounts.self, from: Data(legacy.utf8))
        XCTAssertEqual(saved.accounts.map(\.id), ["rob@cloud.example"])
        XCTAssertEqual(saved.active?.appPassword, "pw")
    }

    func testSavedAccountsRoundTrip() throws {
        var saved = SavedAccounts()
        saved.add(credentials("rob"))
        saved.add(credentials("alice"))
        saved.activate("rob@cloud.example")
        let decoded = try JSONDecoder().decode(SavedAccounts.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)
        XCTAssertEqual(decoded.active?.username, "rob")
    }

    func testAccountIdentity() throws {
        let plain = try credentials("rob", server: XCTUnwrap(URL(string: "http://Cloud.Example/nextcloud/")))
        XCTAssertEqual(plain.serverURL.scheme, "https", "always stored as HTTPS")
        XCTAssertEqual(plain.account.id, "rob@cloud.example/nextcloud")
        let other = try credentials("rob", server: XCTUnwrap(URL(string: "https://other.example:8443")))
        XCTAssertEqual(other.account.id, "rob@other.example:8443")
    }

    func testSigningInAgainReplacesTheAccount() {
        var saved = SavedAccounts()
        saved.add(credentials("rob"))
        let replaced = saved.add(Credentials(serverURL: testServer, username: "rob", appPassword: "new"))
        XCTAssertEqual(replaced?.appPassword, "rob-app-password")
        XCTAssertEqual(saved.all.map(\.appPassword), ["new"])
    }

    func testRemovingTheActiveAccountActivatesTheNext() {
        var saved = SavedAccounts()
        saved.add(credentials("rob"))
        saved.add(credentials("alice"))
        saved.remove("alice@cloud.example")
        XCTAssertEqual(saved.active?.username, "rob")
        saved.remove("rob@cloud.example")
        XCTAssertNil(saved.active)
    }

    // MARK: - App

    func testSwitchingAccountsShowsTheirBoards() async throws {
        let store = InMemoryCredentialStore.signedIn("rob", "alice")
        let app = await makeApp(store)
        XCTAssertEqual(app.accounts.map(\.username), ["rob", "alice"])
        XCTAssertEqual(app.boards.map(\.id), [1])

        try await app.switchAccount(to: XCTUnwrap(app.accounts.last))

        XCTAssertEqual(app.activeAccount?.username, "alice")
        XCTAssertEqual(app.boards.map(\.id), [7])
        XCTAssertEqual(app.selectedBoardId, 7)
        XCTAssertEqual(store.saved.active?.username, "alice", "remembered for next launch")
    }

    func testAddingAnAccountKeepsTheOthers() async throws {
        let store = InMemoryCredentialStore.signedIn("rob")
        let app = await makeApp(store)

        app.addAccount()
        XCTAssertTrue(app.showingLogin)
        try await app.finishSignIn(credentials("alice"))

        XCTAssertFalse(app.showingLogin)
        XCTAssertEqual(app.accounts.map(\.username), ["rob", "alice"])
        XCTAssertEqual(app.activeAccount?.username, "alice")
        XCTAssertEqual(app.boards.map(\.id), [7])
        XCTAssertEqual(store.saved.accounts.count, 2)
    }

    func testCancellingAddAccountReturnsToBoards() async {
        let app = await makeApp(.signedIn("rob"))
        app.addAccount()
        app.cancelAddingAccount()
        XCTAssertFalse(app.showingLogin)
        XCTAssertEqual(app.activeAccount?.username, "rob")
    }

    func testSigningInAgainRevokesTheOldAppPassword() async throws {
        let app = await makeApp(.signedIn("rob"))

        try await app.finishSignIn(Credentials(serverURL: testServer, username: "rob", appPassword: "new"))

        XCTAssertEqual(app.accounts.count, 1)
        await waitUntil {
            StubURLProtocol.requests.contains {
                $0.line == "DELETE /ocs/v2.php/core/apppassword" && $0.header("Authorization") == Self.basic("rob")
            }
        }
    }

    func testSignOutSwitchesToTheNextAccount() async throws {
        let store = InMemoryCredentialStore.signedIn("rob", "alice")
        let app = await makeApp(store)

        await app.signOut()

        XCTAssertTrue(app.isLoggedIn)
        XCTAssertFalse(app.showingLogin)
        XCTAssertEqual(app.accounts.map(\.username), ["alice"])
        XCTAssertEqual(store.saved.accounts.map(\.username), ["alice"])
        await waitUntil { app.boards.map(\.id) == [7] }
        let revoke = try XCTUnwrap(StubURLProtocol.requests.first { $0.path == "/ocs/v2.php/core/apppassword" })
        XCTAssertEqual(revoke.header("Authorization"), Self.basic("rob"), "only the signed-out account is revoked")
    }

    func testRevokedAccountIsDroppedAndTheNextOneShown() async {
        let store = InMemoryCredentialStore.signedIn("rob", "alice")
        let app = await makeApp(store)

        app.endSessionIfUnauthorized(DeckAPIError.unauthorized)

        XCTAssertEqual(app.activeAccount?.username, "alice")
        XCTAssertFalse(app.showingLogin)
        XCTAssertEqual(app.actionError?.hasPrefix("Signed out of rob@cloud.example"), true)
        XCTAssertNil(app.errorMessage)
    }

    func testBoardsFromThePreviousAccountAreIgnored() async throws {
        let store = InMemoryCredentialStore.signedIn("rob", "alice")
        let app = await makeApp(store)
        StubURLProtocol.handler = { request in
            guard request.path.hasSuffix("/boards") else { return .json("[]") }
            let isAlice = request.header("Authorization") == Self.basic("alice")
            return .json(isAlice ? Self.aliceBoards : Self.robBoards, delay: isAlice ? 0 : 0.3)
        }

        let slow = Task { await app.refresh() }
        await sleep(seconds: 0.05)
        try await app.switchAccount(to: XCTUnwrap(app.accounts.last))
        await slow.value

        XCTAssertEqual(app.boards.map(\.id), [7])
    }
}
