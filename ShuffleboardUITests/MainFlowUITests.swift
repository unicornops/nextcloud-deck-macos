import XCTest

/// The app's main flows, driven through its UI against a real Nextcloud server with Deck (#119). Each test works
/// on a board of its own and checks the result on the server, not just on screen. Skipped without a test server.
@MainActor
final class MainFlowUITests: XCTestCase {
    private var server: UITestServer!
    private var alice: DeckClient!
    private var app: XCUIApplication!
    private var boards: [Int] = []

    override func setUp() async throws {
        continueAfterFailure = false
        server = try UITestServer.require()
        alice = try await server.client(for: UITestServer.alice)
        app = XCUIApplication()
    }

    override func tearDown() async throws {
        app?.terminate()
        for board in boards {
            await alice?.deleteBoard(board)
        }
    }

    private func makeBoard() async throws -> (id: Int, title: String) {
        let title = uniqueTitle("UI board")
        let id = try await alice.createBoard(title)
        boards.append(id)
        return (id, title)
    }

    // MARK: - Boards, lists and cards

    func testCreatingListsAndACardThenDraggingItToAnotherList() async throws {
        let board = try await makeBoard()
        try await app.launch(on: server, as: [UITestServer.alice])
        app.openBoard(board.title)

        for list in ["To do", "Done"] {
            app.find(.button, "Add list").waitToAppear().click()
            app.find(.textField, "Enter list name").waitToAppear().typeText(list)
            app.find(.button, "Create").click()
            app.list(list).waitToAppear("List \(list) not shown after creating it")
        }

        app.list("To do").buttons["Add card"].click()
        // The field doesn't take focus by itself.
        let cardTitle = app.find(.textField, "Card title").waitToAppear()
        cardTitle.click()
        cardTitle.typeText("Write UI tests\r")
        let card = app.card("Write UI tests").waitToAppear("New card not shown")
        try await eventually("Card not created in To do on the server") {
            try await alice.list(holding: "Write UI tests", board: board.id) == "To do"
        }

        // The #117 regression: the card stays in "Done" after the drop and after a refresh.
        card.click(forDuration: 0.6, thenDragTo: app.list("Done"), withVelocity: .slow, thenHoldForDuration: 0.6)
        try await eventually("Dragged card is not in Done on the server") {
            try await alice.list(holding: "Write UI tests", board: board.id) == "Done"
        }
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(
            app.list("Done").descendants(matching: .any)["card: Write UI tests"].waitForExistence(timeout: 10),
            "Card snapped back out of Done after a refresh"
        )
    }

    /// Moving cards into a list that already has cards (#117): dropped onto a card, and dropped between two cards.
    func testDraggingCardsIntoAListThatHasCards() async throws {
        let board = try await makeBoard()
        let todo = try await alice.createStack(board: board.id, "To do", order: 0)
        let doing = try await alice.createStack(board: board.id, "Doing", order: 1)
        for (order, title) in ["One", "Two", "Three"].enumerated() {
            _ = try await alice.createCard(board: board.id, stack: todo, title, order: order)
        }
        for (order, title) in ["Alpha", "Beta"].enumerated() {
            _ = try await alice.createCard(board: board.id, stack: doing, title, order: order)
        }
        try await app.launch(on: server, as: [UITestServer.alice])
        app.openBoard(board.title)
        app.card("Beta").waitToAppear()

        // Onto a card: the card goes to the end of that card's list.
        app.card("One").click(
            forDuration: 0.6,
            thenDragTo: app.card("Beta"),
            withVelocity: .slow,
            thenHoldForDuration: 0.6
        )
        try await eventually("Card dropped onto a card in Doing is not in Doing on the server") {
            try await alice.list(holding: "One", board: board.id) == "Doing"
        }

        // Between two cards: onto the gap just above Beta.
        let gap = app.card("Beta").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(
            dx: 0,
            dy: -5
        ))
        app.card("Two").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.6, thenDragTo: gap, withVelocity: .slow, thenHoldForDuration: 0.6)
        try await eventually("Card dropped between two cards in Doing is not in Doing on the server") {
            try await alice.list(holding: "Two", board: board.id) == "Doing"
        }
        let doingTitles = try await alice.titles(inList: "Doing", board: board.id)
        XCTAssertEqual(doingTitles, ["Alpha", "Two", "Beta", "One"])

        // Just inside the list's left edge, next to the gap between lists: that gap must not take the card.
        let edge = app.list("Doing").coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
        app.card("Three").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.6, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 0.6)
        try await eventually("Card dropped at the edge of Doing is not in Doing on the server") {
            try await alice.list(holding: "Three", board: board.id) == "Doing"
        }

        app.typeKey("r", modifierFlags: .command)
        for title in ["One", "Two", "Three"] {
            XCTAssertTrue(
                app.list("Doing").descendants(matching: .any)["card: \(title)"].waitForExistence(timeout: 10),
                "\(title) snapped back out of Doing after a refresh"
            )
        }
    }

    func testEditingACardAndCommenting() async throws {
        let board = try await makeBoard()
        let stack = try await alice.createStack(board: board.id, "To do", order: 0)
        _ = try await alice.createCard(board: board.id, stack: stack, "Draft title")
        try await app.launch(on: server, as: [UITestServer.alice])
        app.openBoard(board.title)

        app.card("Draft title").waitToAppear().click()
        let title = app.find(.textField, "card title").waitToAppear("Card sheet did not open")
        title.replaceText(with: "Final title")
        app.find(.button, "Save").click()
        app.card("Final title").waitToAppear("Edited title not shown on the board")
        try await eventually("Edited title not saved on the server") {
            try await alice.list(holding: "Final title", board: board.id) == "To do"
        }

        app.card("Final title").click()
        let composer = app.find(.textField, "new comment").waitToAppear("No comment field on the card")
        composer.click()
        composer.typeText("Looks good to me")
        app.find(.button, "Comment").click()
        app.staticTexts["Looks good to me"].waitToAppear("Posted comment not shown")
        app.find(.button, "Cancel").click()
    }

    // MARK: - Sharing

    func testSharingABoard() async throws {
        let board = try await makeBoard()
        try await app.launch(on: server, as: [UITestServer.alice])
        app.openBoard(board.title)

        app.find(.button, "Sharing").waitToAppear().click()
        let search = app.find(.textField, "Search people, groups and teams").waitToAppear("Sharing sheet did not open")
        search.click()
        search.typeText("bob")
        app.find(.button, "Share with Bob Example").waitToAppear("Bob not found in the share search").click()
        try await eventually("Board not shared with Bob on the server") {
            let acl = try await alice.board(board.id)["acl"] as? [[String: Any]] ?? []
            return acl.contains { ($0["participant"] as? [String: Any])?["uid"] as? String == UITestServer.bob }
        }
        app.staticTexts["Bob Example"].waitToAppear("Bob not listed as having access")
        app.find(.button, "Done").click()
    }

    // MARK: - Accounts

    func testSwitchingAccountsAndSigningOut() async throws {
        let board = try await makeBoard()
        let bob = try await server.client(for: UITestServer.bob)
        let bobsTitle = uniqueTitle("UI Bob's board")
        let bobsBoard = try await bob.createBoard(bobsTitle)
        defer { Task { await bob.deleteBoard(bobsBoard) } }

        let accounts = try await app.launch(on: server, as: [UITestServer.alice, UITestServer.bob])
        app.element("board: \(board.title)").waitToAppear("Alice's board not shown")

        accountMenu().click()
        app.menuItems[server.accountId(UITestServer.bob)].waitToAppear("Bob's account not in the account menu").click()
        app.element("board: \(bobsTitle)").waitToAppear("Bob's board not shown after switching")
        XCTAssertFalse(app.element("board: \(board.title)").exists, "Alice's board still shown for Bob")

        // Signing out of Bob goes back to Alice; signing out of her too shows the sign-in screen.
        accountMenu().click()
        app.menuItems["Sign Out of \(server.accountId(UITestServer.bob))"].waitToAppear().click()
        app.element("board: \(board.title)").waitToAppear("Not back on Alice's account after signing Bob out")
        accountMenu().click()
        app.menuItems["Sign Out of \(server.accountId(UITestServer.alice))"].waitToAppear().click()
        app.find(.button, "Sign in with browser").waitToAppear("Sign-in screen not shown after signing out")

        for account in accounts {
            let client = DeckClient(server: server, user: account.user, appPassword: account.appPassword)
            try await eventually("Signing out did not revoke \(account.user)'s app password") {
                try await !client.isValid()
            }
        }
    }

    private func accountMenu() -> XCUIElement {
        let menu = app.find(.menuButton, "Account menu")
        return menu.waitForExistence(timeout: 5) ? menu : app.find(.popUpButton, "Account menu").waitToAppear()
    }
}
