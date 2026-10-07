import Foundation
import XCTest

// MARK: - Test server

/// The test server from `scripts/e2e/start-server.sh`, as `TestServer` in the unit tests (UI tests can't import
/// the app, so this is a small copy). The tests are skipped without it.
struct UITestServer: Sendable {
    let url: URL
    private let passwords: [String: String]

    static let alice = "alice"
    static let bob = "bob"

    static func require() throws -> UITestServer {
        let env = ProcessInfo.processInfo.environment
        guard let value = env["E2E_SERVER_URL"], let url = URL(string: value),
              let alice = env["E2E_ALICE_PASSWORD"], let bob = env["E2E_BOB_PASSWORD"] else {
            throw XCTSkip("No test server: run scripts/e2e/start-server.sh and pass E2E_SERVER_URL (see README)")
        }
        return UITestServer(url: url, passwords: [Self.alice: alice, Self.bob: bob])
    }

    /// The account id the app shows, e.g. `alice@localhost:8443`.
    func accountId(_ user: String) -> String {
        "\(user)@\(url.host ?? "")" + (url.port.map { ":\($0)" } ?? "")
    }

    /// A new app password for `user`, as a client gets one after signing in.
    func appPassword(for user: String) async throws -> String {
        let json = try await request(
            "GET",
            "ocs/v2.php/core/getapppassword?format=json",
            user: user,
            secret: passwords[user] ?? ""
        )
        guard let password = ((json as? [String: Any])?["ocs"] as? [String: Any])
            .flatMap({ $0["data"] as? [String: Any] })?["apppassword"] as? String else {
            throw UITestError("No app password for \(user)")
        }
        return password
    }

    /// A Deck API client for `user` with its own app password, for setting up and checking what the UI did.
    func client(for user: String) async throws -> DeckClient {
        try await DeckClient(server: self, user: user, appPassword: appPassword(for: user))
    }

    /// Sends a request and returns the decoded JSON (nil for an empty body); throws for any status but 2xx.
    func request(
        _ method: String,
        _ path: String,
        user: String,
        secret: String,
        body: Any? = nil
    ) async throws
        -> Any? {
        guard let requestURL = URL(string: path, relativeTo: url.appendingPathComponent("/")) else {
            throw UITestError("Bad path \(path)")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Basic " + Data("\(user):\(secret)".utf8).base64EncodedString(),
            forHTTPHeaderField: "Authorization"
        )
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw UITestError("\(method) \(path): HTTP \(status)", status: status)
        }
        return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data)
    }
}

struct UITestError: Error, CustomStringConvertible {
    let description: String
    var status = 0

    init(_ description: String, status: Int = 0) {
        self.description = description
        self.status = status
    }
}

/// The few Deck API calls the UI tests need to set up boards and check the server afterwards.
struct DeckClient: Sendable {
    let server: UITestServer
    let user: String
    let appPassword: String

    private func call(_ method: String, _ path: String, _ body: Any? = nil) async throws -> Any? {
        try await server.request(
            method,
            "index.php/apps/deck/api/v1.0/" + path,
            user: user,
            secret: appPassword,
            body: body
        )
    }

    func createBoard(_ title: String) async throws -> Int {
        try await Self.id(call("POST", "boards", ["title": title, "color": "2E8B57"]))
    }

    func createStack(board: Int, _ title: String, order: Int) async throws -> Int {
        try await Self.id(call("POST", "boards/\(board)/stacks", ["title": title, "order": order]))
    }

    func createCard(board: Int, stack: Int, _ title: String) async throws -> Int {
        try await Self.id(call(
            "POST",
            "boards/\(board)/stacks/\(stack)/cards",
            ["title": title, "type": "plain", "order": 0]
        ))
    }

    func deleteBoard(_ id: Int) async {
        _ = try? await call("DELETE", "boards/\(id)")
    }

    func board(_ id: Int) async throws -> [String: Any] {
        try await call("GET", "boards/\(id)") as? [String: Any] ?? [:]
    }

    /// The board's lists, each with its cards.
    func stacks(board: Int) async throws -> [[String: Any]] {
        try await call("GET", "boards/\(board)/stacks") as? [[String: Any]] ?? []
    }

    /// The title of the list holding the card titled `card`, if any.
    func list(holding card: String, board: Int) async throws -> String? {
        try await stacks(board: board).first { stack in
            (stack["cards"] as? [[String: Any]] ?? []).contains { $0["title"] as? String == card }
        }?["title"] as? String
    }

    /// True if the app password still works, false once it has been revoked.
    func isValid() async throws -> Bool {
        do {
            _ = try await call("GET", "boards")
            return true
        } catch let error as UITestError where error.status == 401 {
            return false
        }
    }

    private static func id(_ json: Any?) throws -> Int {
        guard let id = (json as? [String: Any])?["id"] as? Int else { throw UITestError("No id in \(String(describing: json))") }
        return id
    }
}

func uniqueTitle(_ prefix: String) -> String {
    "\(prefix) \(UUID().uuidString.prefix(6))"
}

// MARK: - Launching the app

/// What a UI test signed the app in with, to check on the server afterwards.
struct LaunchedAccount {
    let user: String
    let appPassword: String
}

@MainActor
extension XCUIApplication {
    /// Launches the app signed in to `server` as `users` (the first is active), with credentials kept in memory
    /// (see `UITestLaunch` in the app). No users shows the sign-in screen.
    @discardableResult
    func launch(
        on server: UITestServer,
        as users: [String],
        appearance: String? = nil
    ) async throws
        -> [LaunchedAccount] {
        var accounts: [LaunchedAccount] = []
        for user in users {
            try await accounts.append(LaunchedAccount(user: user, appPassword: server.appPassword(for: user)))
        }
        let credentials = accounts.map {
            ["serverURL": server.url.absoluteString, "username": $0.user, "appPassword": $0.appPassword]
        }
        let json = try JSONSerialization.data(withJSONObject: credentials)
        launchEnvironment["SHUFFLEBOARD_UITEST_ACCOUNTS"] = String(decoding: json, as: UTF8.self)
        if let appearance {
            launchEnvironment["SHUFFLEBOARD_UITEST_APPEARANCE"] = appearance
        }
        launch()
        XCTAssertTrue(windows.firstMatch.waitForExistence(timeout: 20), "The app's window did not open")
        return accounts
    }

    /// Any element with this accessibility identifier or label.
    func element(_ name: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: name).firstMatch
    }

    /// The first element of `type` whose identifier, label, title or placeholder is `name`.
    func find(_ type: XCUIElement.ElementType, _ name: String) -> XCUIElement {
        descendants(matching: type).matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR title == %@ OR placeholderValue == %@",
                name,
                name,
                name,
                name
            )
        ).firstMatch
    }

    /// Opens a board from the sidebar.
    func openBoard(_ title: String) {
        element("board: \(title)").waitToAppear("Board \(title) not in the sidebar", timeout: 20).click()
    }

    func card(_ title: String) -> XCUIElement {
        element("card: \(title)")
    }

    func list(_ title: String) -> XCUIElement {
        element("list: \(title)")
    }
}

extension XCUIElement {
    /// Waits for the element and fails the test if it doesn't appear.
    @MainActor
    @discardableResult
    func waitToAppear(
        _ message: String = "",
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    )
        -> XCUIElement {
        XCTAssertTrue(
            waitForExistence(timeout: timeout),
            message.isEmpty ? "\(self) did not appear" : message,
            file: file,
            line: line
        )
        return self
    }

    /// Replaces a text field's contents.
    @MainActor
    func replaceText(with text: String) {
        click()
        typeKey("a", modifierFlags: .command)
        typeText(text)
    }
}

/// Polls `condition` until it holds or `timeout` passes; for checking the server after a UI action.
func eventually(
    timeout: TimeInterval = 15,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () async throws -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    XCTFail(message, file: file, line: line)
}
