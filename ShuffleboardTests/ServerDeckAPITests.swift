import Foundation
import XCTest
@testable import Shuffleboard

/// `DeckAPI` against a real Nextcloud server with Deck (#119): every endpoint the app uses, so a server release
/// that changes them fails here rather than in the app. Skipped without a test server (see `TestServer`).
final class ServerDeckAPITests: XCTestCase {
    private var server: TestServer!
    private var api: DeckAPI!

    override func setUp() async throws {
        server = try TestServer.require()
        api = try await server.api(for: TestServer.alice)
    }

    // MARK: - Boards

    func testBoardLifecycle() async throws {
        let title = uniqueTitle("E2E lifecycle")
        let created = try await api.createBoard(title: title, color: "31CC7C")
        XCTAssertEqual(created.title, title)
        XCTAssertEqual(created.owner?.uid, TestServer.alice)
        var boards = try await api.getBoards()
        XCTAssertTrue(boards.contains { $0.id == created.id }, "New board missing from the board list")

        let renamed = title + " renamed"
        let archived = try await api.updateBoard(id: created.id, title: renamed, color: "E9322D", archived: true)
        XCTAssertEqual(archived.title, renamed)
        XCTAssertTrue(archived.archived)
        // Deck has no partial update: leaving `archived` out unarchives the board, so the app always sends it (#133).
        let edited = try await api.updateBoard(id: created.id, title: renamed, color: "9C59B6", archived: true)
        XCTAssertTrue(edited.archived, "Editing an archived board unarchived it")
        let color = try await api.getBoard(id: created.id).color
        XCTAssertEqual(color?.lowercased(), "9c59b6")
        let unarchived = try await api.updateBoard(id: created.id, title: renamed, color: "E9322D", archived: false)
        XCTAssertFalse(unarchived.archived)

        try await api.deleteBoard(id: created.id)
        boards = try await api.getBoards()
        let deleted = boards.first { $0.id == created.id }
        XCTAssertGreaterThan(deleted?.deletedAt ?? 0, 0, "Deleted board should be soft-deleted, not gone")

        guard server.deck(atLeast: "1.17") else {
            // Deck 1.16 refuses to restore a deleted board (fixed in 1.17.0), so the app's "Restore" fails there.
            do {
                try await api.undoDeleteBoard(id: created.id)
                XCTFail("Deck \(server.deckVersion) restored a deleted board: drop this exception")
            } catch DeckAPIError.permissionDenied {
                // Expected.
            }
            return
        }
        try await api.undoDeleteBoard(id: created.id)
        let restored = try await api.getBoard(id: created.id)
        XCTAssertEqual(restored.deletedAt ?? 0, 0)
        try await api.deleteBoard(id: created.id)
    }

    // MARK: - Stacks and cards

    func testStacksAndCardEditing() async throws {
        try await withTemporaryBoard(api) { board in
            let first = try await api.createStack(boardId: board.id, title: "To do", order: 0)
            let second = try await api.createStack(boardId: board.id, title: "Done", order: 1)
            let renamed = try await api.updateStack(boardId: board.id, stackId: second.id, title: "Finished", order: 5)
            XCTAssertEqual(renamed.title, "Finished")
            XCTAssertEqual(renamed.order, 5)

            let card = try await api.createCard(
                boardId: board.id,
                stackId: first.id,
                title: "Write tests",
                description: "Against a **real** server"
            )
            XCTAssertEqual(card.stackId, first.id)

            var edited = try await api.getCard(boardId: board.id, stackId: first.id, cardId: card.id)
            XCTAssertEqual(edited.description, "Against a **real** server")
            let due = Date(timeIntervalSince1970: 1_900_000_000)
            edited = edited.withSchedule(dueDate: due, isDone: true)
            edited.title = "Write more tests"
            _ = try await api.updateCard(boardId: board.id, stackId: first.id, card: edited)

            let saved = try await api.getCard(boardId: board.id, stackId: first.id, cardId: card.id)
            XCTAssertEqual(saved.title, "Write more tests")
            XCTAssertEqual(saved.description, "Against a **real** server", "Saving the title must keep the description")
            XCTAssertEqual(saved.dueDate.map { Int($0.timeIntervalSince1970) }, 1_900_000_000)
            XCTAssertTrue(saved.isDone)

            let undone = try await api.updateCard(
                boardId: board.id,
                stackId: first.id,
                card: saved.withSchedule(dueDate: nil, isDone: false)
            )
            XCTAssertFalse(undone.isDone)
            XCTAssertNil(undone.dueDate)

            try await api.deleteCard(boardId: board.id, stackId: first.id, cardId: card.id)
            let stacks = try await api.getStacks(boardId: board.id)
            XCTAssertNil(stacks.stack(holding: card.id), "Deleted card still on the board")

            try await api.deleteStack(boardId: board.id, stackId: second.id)
            let remaining = try await api.getStacks(boardId: board.id)
            XCTAssertEqual(remaining.map(\.id), [first.id])
        }
    }

    /// The #117 regression at the API level: a card moved to another list stays there.
    func testMovingCardsBetweenAndWithinLists() async throws {
        try await withTemporaryBoard(api) { board in
            let todo = try await api.createStack(boardId: board.id, title: "To do", order: 0)
            let doing = try await api.createStack(boardId: board.id, title: "Doing", order: 1)
            var cards: [Card] = []
            for title in ["One", "Two", "Three"] {
                try await cards.append(api.createCard(boardId: board.id, stackId: todo.id, title: title))
            }

            try await api.reorderCard(
                boardId: board.id,
                cardId: cards[0].id,
                order: 0,
                newStackId: doing.id
            )
            var stacks = try await api.getStacks(boardId: board.id)
            XCTAssertEqual(stacks.stack(holding: cards[0].id)?.id, doing.id, "Moved card went back to its old list")

            // Within a list: "Three" to the top.
            try await api.reorderCard(
                boardId: board.id,
                cardId: cards[2].id,
                order: 0,
                newStackId: todo.id
            )
            stacks = try await api.getStacks(boardId: board.id)
            let todoTitles = stacks.first { $0.id == todo.id }?.activeCards.map(\.title)
            XCTAssertEqual(todoTitles, ["Three", "Two"])
        }
    }

    func testArchivingCards() async throws {
        try await withTemporaryBoard(api) { board in
            let stack = try await api.createStack(boardId: board.id, title: "To do")
            let card = try await api.createCard(boardId: board.id, stackId: stack.id, title: "Old news")

            try await api.archiveCard(boardId: board.id, stackId: stack.id, cardId: card.id)
            var stacks = try await api.getStacks(boardId: board.id)
            XCTAssertNil(stacks.stack(holding: card.id), "Archived card still in the board's lists")
            let archived = try await api.getArchivedStacks(boardId: board.id)
            XCTAssertTrue(archived.contains { $0.cards?.contains { $0.id == card.id } == true })

            try await api.unarchiveCard(boardId: board.id, stackId: stack.id, cardId: card.id)
            stacks = try await api.getStacks(boardId: board.id)
            XCTAssertEqual(stacks.stack(holding: card.id)?.id, stack.id)
        }
    }

    // MARK: - Labels and assignees

    func testLabelsAndAssignees() async throws {
        try await withTemporaryBoard(api) { board in
            let stack = try await api.createStack(boardId: board.id, title: "To do")
            let card = try await api.createCard(boardId: board.id, stackId: stack.id, title: "Label me")
            let label = try await api.createLabel(boardId: board.id, title: "Urgent", color: "E9322D")
            XCTAssertEqual(label.title, "Urgent")
            let boardLabels = try await api.getBoard(id: board.id).labels
            XCTAssertTrue(boardLabels.contains { $0.id == label.id })

            try await api.assignLabel(boardId: board.id, stackId: stack.id, cardId: card.id, labelId: label.id)
            var saved = try await api.getCard(boardId: board.id, stackId: stack.id, cardId: card.id)
            XCTAssertEqual(saved.labels?.map(\.id), [label.id])
            try await api.removeLabel(boardId: board.id, stackId: stack.id, cardId: card.id, labelId: label.id)
            saved = try await api.getCard(boardId: board.id, stackId: stack.id, cardId: card.id)
            XCTAssertEqual(saved.labels?.count ?? 0, 0)

            // Bob can only be assigned once the board is shared with him.
            try await api.addShare(
                boardId: board.id,
                type: .user,
                participant: TestServer.bob,
                permissions: SharePermissions()
            )
            try await api.assignUser(boardId: board.id, stackId: stack.id, cardId: card.id, userId: TestServer.bob)
            try await api.assignUser(boardId: board.id, stackId: stack.id, cardId: card.id, userId: TestServer.alice)
            saved = try await api.getCard(boardId: board.id, stackId: stack.id, cardId: card.id)
            XCTAssertEqual(Set(saved.assignedUsers?.map(\.participant.uid) ?? []), [TestServer.alice, TestServer.bob])

            try await api.unassignUser(boardId: board.id, stackId: stack.id, cardId: card.id, userId: TestServer.bob)
            saved = try await api.getCard(boardId: board.id, stackId: stack.id, cardId: card.id)
            XCTAssertEqual(saved.assignedUsers?.map(\.participant.uid), [TestServer.alice])
        }
    }

    // MARK: - Attachments

    func testAttachments() async throws {
        try await withTemporaryBoard(api) { board in
            let stack = try await api.createStack(boardId: board.id, title: "To do")
            let card = try await api.createCard(boardId: board.id, stackId: stack.id, title: "With a file")
            let contents = Data("Shuffleboard end-to-end attachment \(UUID())\n".utf8)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID().uuidString).txt")
            try contents.write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }

            try await api.uploadAttachment(
                boardId: board.id,
                stackId: stack.id,
                cardId: card.id,
                fileURL: file,
                filename: file.lastPathComponent
            )
            let attachments = try await api.getAttachments(boardId: board.id, stackId: stack.id, cardId: card.id)
            let attachment = try XCTUnwrap(attachments.first, "Uploaded attachment not listed")
            XCTAssertEqual(attachments.count, 1)
            XCTAssertEqual(attachment.type, "file")

            let downloaded = try await api.downloadAttachment(
                boardId: board.id,
                stackId: stack.id,
                cardId: card.id,
                attachmentId: attachment.id,
                type: attachment.type
            )
            XCTAssertEqual(downloaded, contents)

            try await api.deleteAttachment(
                boardId: board.id,
                stackId: stack.id,
                cardId: card.id,
                attachmentId: attachment.id,
                type: attachment.type
            )
            let remaining = try await api.getAttachments(boardId: board.id, stackId: stack.id, cardId: card.id)
            XCTAssertTrue(remaining.allSatisfy { ($0.deletedAt ?? 0) > 0 }, "Deleted attachment still listed")
        }
    }

    // MARK: - Comments

    func testComments() async throws {
        try await withTemporaryBoard(api) { board in
            let stack = try await api.createStack(boardId: board.id, title: "To do")
            let card = try await api.createCard(boardId: board.id, stackId: stack.id, title: "Discuss")

            let first = try await api.addComment(cardId: card.id, message: "First!")
            XCTAssertEqual(first.actorId, TestServer.alice)
            _ = try await api.addComment(cardId: card.id, message: "Second")
            var comments = try await api.getComments(cardId: card.id)
            XCTAssertEqual(comments.map(\.message), ["Second", "First!"], "Comments should come newest first")

            let updated = try await api.updateComment(cardId: card.id, commentId: first.id, message: "First, edited")
            XCTAssertEqual(updated.message, "First, edited")
            try await api.deleteComment(cardId: card.id, commentId: first.id)
            comments = try await api.getComments(cardId: card.id)
            XCTAssertEqual(comments.map(\.message), ["Second"])
        }
    }

    // MARK: - Sharing

    func testSharingWithAPersonAndAGroup() async throws {
        let bobAPI = try await server.api(for: TestServer.bob)
        try await withTemporaryBoard(api) { board in
            let sharees = try await api.searchSharees("bob")
            let bob = try XCTUnwrap(sharees.first { $0.participantId == TestServer.bob }, "Bob not found: \(sharees)")
            XCTAssertEqual(bob.shareType, .user)
            let groups = try await api.searchSharees("famil")
            XCTAssertTrue(groups.contains { $0.participantId == "family" && $0.shareType == .group }, "\(groups)")

            try await api.addShare(
                boardId: board.id,
                type: .user,
                participant: TestServer.bob,
                permissions: SharePermissions()
            )
            var shared = try await api.getBoard(id: board.id)
            let entry = try XCTUnwrap(shared.acl.first { $0.participant?.uid == TestServer.bob })
            XCTAssertFalse(entry.permissionEdit)
            var bobsBoards = try await bobAPI.getBoards()
            XCTAssertTrue(bobsBoards.contains { $0.id == board.id }, "Bob can't see the board shared with him")

            let aclId = try XCTUnwrap(entry.id)
            try await api.updateShare(boardId: board.id, aclId: aclId, permissions: SharePermissions(edit: true))
            shared = try await api.getBoard(id: board.id)
            XCTAssertEqual(shared.acl.first { $0.id == aclId }?.permissionEdit, true)
            let asBob = try await bobAPI.getBoard(id: board.id)
            XCTAssertEqual(asBob.permissions?.permissionEdit, true)
            XCTAssertEqual(asBob.permissions?.permissionManage, false)

            try await api.addShare(
                boardId: board.id,
                type: .group,
                participant: "family",
                permissions: SharePermissions()
            )
            shared = try await api.getBoard(id: board.id)
            XCTAssertTrue(shared.acl
                .contains { $0.type == ShareType.group.rawValue && $0.participant?.uid == "family" })

            try await api.removeShare(boardId: board.id, aclId: aclId)
            shared = try await api.getBoard(id: board.id)
            XCTAssertFalse(shared.acl.contains { $0.id == aclId })
            for group in shared.acl.filter({ $0.type == ShareType.group.rawValue }) {
                if let id = group.id {
                    try await api.removeShare(boardId: board.id, aclId: id)
                }
            }
            bobsBoards = try await bobAPI.getBoards()
            XCTAssertFalse(
                bobsBoards.contains { $0.id == board.id && ($0.deletedAt ?? 0) == 0 },
                "Bob still sees the board"
            )
        }
    }

    // MARK: - ETags

    /// `refreshIfChanged()` relies on the board list's ETag: Deck changes it when anything on any board changes.
    func testBoardListETagAnswersNotModifiedUntilSomethingChanges() async throws {
        try await withTemporaryBoard(api) { board in
            let stack = try await api.createStack(boardId: board.id, title: "To do")
            let boards = try await api.fetchBoards(ifNoneMatch: nil)
            let etag = try XCTUnwrap(boards?.etag, "Board list has no ETag")

            let unchanged = try await api.fetchBoards(ifNoneMatch: etag)
            XCTAssertNil(unchanged, "Expected 304 for an unchanged board list")

            // Deck's ETags come from modification times in whole seconds: a change within the same second
            // as the last fetch keeps the old ETag.
            await sleep(seconds: 1.1)
            _ = try await api.createCard(boardId: board.id, stackId: stack.id, title: "Something changed")
            let changed = try await api.fetchBoards(ifNoneMatch: etag)
            XCTAssertNotNil(changed, "A new card should change the board list's ETag")
            XCTAssertNotEqual(changed?.etag, etag)
        }
    }

    /// Deck's list endpoint (`GET /boards/{id}/stacks`) sends no ETag, so the lists are always fetched in full.
    /// If a release adds one, it must still answer 304 only while nothing changed.
    func testListsETagIfTheServerSendsOne() async throws {
        try await withTemporaryBoard(api) { board in
            let stack = try await api.createStack(boardId: board.id, title: "To do")
            guard let etag = try await api.fetchStacks(boardId: board.id, ifNoneMatch: nil)?.etag else { return }
            let unchanged = try await api.fetchStacks(boardId: board.id, ifNoneMatch: etag)
            XCTAssertNil(unchanged, "Expected 304 for unchanged lists")
            await sleep(seconds: 1.1)
            _ = try await api.createCard(boardId: board.id, stackId: stack.id, title: "Something changed")
            let changed = try await api.fetchStacks(boardId: board.id, ifNoneMatch: etag)
            XCTAssertNotNil(changed, "A new card should change the lists' ETag")
        }
    }

    // MARK: - App passwords

    func testRevokedAppPasswordIsUnauthorized() async throws {
        // One session for both requests, as in the app: a session cookie must not outlive the app password.
        let revoked = try await server.api(for: TestServer.alice, session: URLSession(configuration: .ephemeral))
        _ = try await revoked.getBoards()
        try await revoked.revokeAppPassword()
        do {
            _ = try await revoked.getBoards()
            XCTFail("A revoked app password still works")
        } catch DeckAPIError.unauthorized {
            // Expected.
        }
    }
}
