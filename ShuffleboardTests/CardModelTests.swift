import Foundation
import XCTest
@testable import Shuffleboard

/// Card decoding and the body sent when saving a card (#53).
final class CardModelTests: XCTestCase {
    private func decodeCard(_ json: String) throws -> Card {
        try JSONDecoder().decode(Card.self, from: Data(json.utf8))
    }

    private func body(_ request: UpdateCardRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testOwnerDecodesFromUserObject() throws {
        let card = try decodeCard("""
        {"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false,
         "owner": {"primaryKey": "rob", "uid": "rob", "displayname": "Rob"}}
        """)
        XCTAssertEqual(card.owner, "rob")
    }

    func testOwnerDecodesFromString() throws {
        let card =
            try decodeCard(#"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false, "owner": "alice"}"#)
        XCTAssertEqual(card.owner, "alice")
    }

    func testIntegersMayBeStrings() throws {
        let card = try decodeCard(#"{"id": "7", "title": "t", "stackId": "2", "order": "5", "archived": false}"#)
        XCTAssertEqual(card.id, 7)
        XCTAssertEqual(card.stackId, 2)
        XCTAssertEqual(card.order, 5)
    }

    func testUpdateKeepsEveryFieldTheServerWouldOtherwiseReset() throws {
        var card = try decodeCard("""
        {"id": 42, "title": "Old", "description": "old", "stackId": 7, "type": "plain",
         "owner": {"uid": "rob"}, "order": 3, "archived": false,
         "duedate": "2026-10-10T12:00:00+00:00", "startdate": "2026-10-01T09:00:00+00:00",
         "done": "2026-10-02T08:00:00+00:00"}
        """)
        card.title = "New"
        card.description = "new"

        let sent = try body(UpdateCardRequest(card: card, fallbackOwner: "fallback"))

        XCTAssertEqual(sent["title"] as? String, "New")
        XCTAssertEqual(sent["description"] as? String, "new")
        XCTAssertEqual(sent["owner"] as? String, "rob")
        XCTAssertEqual(sent["order"] as? Int, 3)
        XCTAssertEqual(sent["duedate"] as? String, "2026-10-10T12:00:00+00:00")
        XCTAssertEqual(sent["startdate"] as? String, "2026-10-01T09:00:00+00:00")
        XCTAssertEqual(sent["done"] as? String, "2026-10-02T08:00:00+00:00")
        XCTAssertEqual(sent["type"] as? String, "plain")
        XCTAssertNil(sent["archived"], "archived is left to the server: it rejects true for an archived card")
    }

    func testUnsetDatesAreSentAsNull() throws {
        let card =
            try decodeCard(#"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false, "owner": "a"}"#)
        let sent = try body(UpdateCardRequest(card: card, fallbackOwner: "me"))
        XCTAssertTrue(sent["duedate"] is NSNull)
        XCTAssertTrue(sent["done"] is NSNull)
        XCTAssertEqual(sent["description"] as? String, "")
    }

    func testMissingOwnerFallsBackToSignedInUser() throws {
        let card = try decodeCard(#"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false}"#)
        let sent = try body(UpdateCardRequest(card: card, fallbackOwner: "me"))
        XCTAssertEqual(sent["owner"] as? String, "me")
    }

    // MARK: - Due dates and done state (#73)

    func testDeckDateParsesDeckFormats() throws {
        let plain = try XCTUnwrap(DeckDate.parse("2026-10-10T12:00:00+00:00"))
        let fractional = try XCTUnwrap(DeckDate.parse("2026-10-10T12:00:00.250Z"))
        XCTAssertEqual(fractional.timeIntervalSince(plain), 0.25, accuracy: 0.001)
        XCTAssertNil(DeckDate.parse(""))
        XCTAssertNil(DeckDate.parse(nil))
        XCTAssertNil(DeckDate.parse("not a date"))
    }

    func testDeckDateRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_791_201_600)
        XCTAssertEqual(DeckDate.parse(DeckDate.string(from: date)), date)
    }

    func testOverdueAndDone() throws {
        let now = try XCTUnwrap(DeckDate.parse("2026-10-04T12:00:00+00:00"))
        let past =
            try decodeCard(
                #"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false, "duedate": "2026-10-01T09:00:00+00:00"}"#
            )
        XCTAssertTrue(past.isOverdue(at: now))
        XCTAssertFalse(past.isDone)

        let pastDone = try decodeCard("""
        {"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false,
         "duedate": "2026-10-01T09:00:00+00:00", "done": "2026-10-02T08:00:00+00:00"}
        """)
        XCTAssertTrue(pastDone.isDone)
        XCTAssertFalse(pastDone.isOverdue(at: now), "a done card is never overdue")

        let future =
            try decodeCard(
                #"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false, "duedate": "2026-11-01T09:00:00+00:00"}"#
            )
        XCTAssertFalse(future.isOverdue(at: now))
        let undated = try decodeCard(#"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false}"#)
        XCTAssertNil(undated.dueDate)
        XCTAssertFalse(undated.isOverdue(at: now))
    }

    func testMarkingDoneStampsNowButKeepsAnExistingDoneDate() throws {
        let now = try XCTUnwrap(DeckDate.parse("2026-10-04T12:00:00+00:00"))
        let open = try decodeCard(#"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false}"#)
        XCTAssertEqual(DeckDate.parse(open.withSchedule(dueDate: nil, isDone: true, now: now).done), now)

        let done =
            try decodeCard(
                #"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false, "done": "2026-10-02T08:00:00+00:00"}"#
            )
        XCTAssertEqual(done.withSchedule(dueDate: nil, isDone: true, now: now).done, "2026-10-02T08:00:00+00:00")
        XCTAssertNil(done.withSchedule(dueDate: nil, isDone: false, now: now).done)
    }

    func testScheduleIsSentInTheUpdateBody() throws {
        let due = try XCTUnwrap(DeckDate.parse("2026-10-10T12:00:00+00:00"))
        let card =
            try decodeCard(
                #"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false, "owner": "a", "duedate": "2026-01-01T00:00:00+00:00"}"#
            )

        let scheduled = try body(UpdateCardRequest(
            card: card.withSchedule(dueDate: due, isDone: true),
            fallbackOwner: "me"
        ))
        XCTAssertEqual(DeckDate.parse(scheduled["duedate"] as? String), due)
        XCTAssertNotNil(DeckDate.parse(scheduled["done"] as? String))

        let cleared = try body(UpdateCardRequest(
            card: card.withSchedule(dueDate: nil, isDone: false),
            fallbackOwner: "me"
        ))
        XCTAssertTrue(cleared["duedate"] is NSNull, "removing the due date clears it on the server")
        XCTAssertTrue(cleared["done"] is NSNull)
    }

    // MARK: - Restoring attachments (#139)

    func testOnlyDeckFileAttachmentsCanBeRestored() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Attachment.self, from: Data(json.utf8)) }
        let deleted = try decode(#"{"id": 1, "type": "deck_file", "deletedAt": 1791479969}"#)
        XCTAssertTrue(deleted.isDeleted)
        XCTAssertTrue(deleted.canBeRestored)
        let file = try decode(#"{"id": 2, "type": "file", "deletedAt": 0}"#)
        XCTAssertFalse(file.isDeleted)
        XCTAssertFalse(file.canBeRestored, "Deck refuses to restore file attachments")
    }

    // MARK: - Assignments (#74)

    func testAssignmentsDecodeFromParticipants() throws {
        let card = try decodeCard("""
        {"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false,
         "assignedUsers": [
           {"id": 3, "participant": {"primaryKey": "alice", "uid": "alice", "displayname": "Alice Smith"},
            "cardId": 1, "type": 0},
           {"id": "4", "participant": {"primaryKey": "staff", "uid": "staff", "displayname": "Staff"},
            "cardId": 1, "type": 1}
         ]}
        """)
        XCTAssertEqual(card.assignments.map(\.participant.uid), ["alice", "staff"])
        XCTAssertEqual(card.assignments.map(\.id), [3, 4])
        XCTAssertEqual(card.assignments.map(\.type), [0, 1])
        XCTAssertEqual(card.assignments.first?.participant.displayName, "Alice Smith")
    }

    func testInitials() {
        XCTAssertEqual(DeckUser(uid: "rob", displayname: "Rob Lazzurs").initials, "RL")
        XCTAssertEqual(DeckUser(uid: "admin", displayname: "admin").initials, "A")
        XCTAssertEqual(DeckUser(uid: "jane.doe", displayname: "").initials, "JD")
        XCTAssertEqual(DeckUser(uid: "bob", displayname: nil).displayName, "bob")
    }

    func testAssignableUsersAreMembersOwnerAndSharedUsersOnce() throws {
        let board = try JSONDecoder().decode(Board.self, from: Data("""
        {"id": 1, "title": "B", "archived": false, "labels": [],
         "owner": {"primaryKey": "rob", "uid": "rob", "displayname": "Rob"},
         "users": [{"primaryKey": "alice", "uid": "alice", "displayname": "Alice"}],
         "acl": [
           {"id": 1, "participant": {"primaryKey": "bob", "uid": "bob", "displayname": "Bob"}, "type": 0,
            "permissionEdit": true, "permissionShare": false, "permissionManage": false},
           {"id": 2, "participant": {"primaryKey": "staff", "uid": "staff", "displayname": "Staff"}, "type": 1,
            "permissionEdit": true, "permissionShare": false, "permissionManage": false},
           {"id": 3, "participant": {"primaryKey": "alice", "uid": "alice", "displayname": "Alice"}, "type": 0,
            "permissionEdit": true, "permissionShare": false, "permissionManage": false}
         ]}
        """.utf8))
        XCTAssertEqual(board.assignableUsers.map(\.uid), ["alice", "bob", "rob"], "sorted, unique, no groups")
    }

    // MARK: - Comments (#75)

    func testCommentsDecodeFromTheOCSEnvelope() throws {
        let json = """
        {"ocs": {"meta": {"status": "ok", "statuscode": 200, "message": "OK"}, "data": [
          {"id": "177", "objectId": "13", "message": "My message to @bob", "actorId": "admin", "actorType": "users",
           "actorDisplayName": "Administrator", "creationDateTime": "2020-03-10T10:30:17+00:00", "mentions": []}
        ]}}
        """
        let comments = try JSONDecoder().decode(OCSResponse<[CardComment]>.self, from: Data(json.utf8)).ocs.data
        let comment = try XCTUnwrap(comments.first)
        XCTAssertEqual(comment.id, 177)
        XCTAssertEqual(comment.message, "My message to @bob")
        XCTAssertEqual(comment.author.uid, "admin")
        XCTAssertEqual(comment.author.displayName, "Administrator")
        XCTAssertEqual(comment.createdAt, DeckDate.parse("2020-03-10T10:30:17+00:00"))
    }

    func testCommentLengthAndBlankRules() {
        XCTAssertFalse(CardComment.isPostable("   \n "))
        XCTAssertTrue(CardComment.isPostable("  hi  "))
        XCTAssertTrue(CardComment.isPostable(String(repeating: "a", count: CardComment.maximumLength)))
        XCTAssertFalse(CardComment.isPostable(String(repeating: "a", count: CardComment.maximumLength + 1)))
    }

    func testCardDecodesCommentCount() throws {
        let card =
            try decodeCard(#"{"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false, "commentsCount": 3}"#)
        XCTAssertEqual(card.commentsCount, 3)
    }

    // MARK: - Archived cards (#76)

    func testStackSplitsActiveAndArchivedCards() throws {
        let stack = try JSONDecoder().decode(Stack.self, from: Data("""
        {"id": 10, "title": "To do", "boardId": 1, "order": 0, "cards": [
          {"id": 1, "title": "Second", "stackId": 10, "order": 2, "archived": false},
          {"id": 2, "title": "Old", "stackId": 10, "order": 0, "archived": true, "lastModified": 100},
          {"id": 3, "title": "First", "stackId": 10, "order": 1, "archived": false},
          {"id": 4, "title": "Newer", "stackId": 10, "order": 3, "archived": true, "lastModified": 200}
        ]}
        """.utf8))
        XCTAssertEqual(stack.activeCards.map(\.title), ["First", "Second"], "archived cards stay off the board")
        XCTAssertEqual(stack.archivedCards.map(\.title), ["Newer", "Old"], "most recently archived first")
    }
}

// MARK: - Moving cards

extension CardModelTests {
    private func board() throws -> [Stack] {
        try JSONDecoder().decode([Stack].self, from: Data("""
        [{"id": 1, "title": "To do", "boardId": 1, "order": 0, "cards": [
           {"id": 10, "title": "A", "stackId": 1, "order": 0},
           {"id": 11, "title": "B", "stackId": 1, "order": 1}]},
         {"id": 2, "title": "Done", "boardId": 1, "order": 1, "cards": [
           {"id": 20, "title": "C", "stackId": 2, "order": 0},
           {"id": 21, "title": "Old", "stackId": 2, "order": 5, "archived": true}]}]
        """.utf8))
    }

    func testMovingACardToAnotherList() throws {
        let moved = try XCTUnwrap(board().movingCard(10, toStack: 2, at: 1))
        XCTAssertEqual(moved[0].activeCards.map(\.id), [11])
        XCTAssertEqual(moved[1].activeCards.map(\.id), [20, 10])
        XCTAssertEqual(moved[1].activeCards.map(\.order), [0, 1])
        XCTAssertEqual(moved[1].activeCards.last?.stackId, 2)
        XCTAssertEqual(moved[1].archivedCards.map(\.id), [21], "archived cards stay put")
    }

    func testMovingACardWithinItsList() throws {
        let moved = try XCTUnwrap(board().movingCard(11, toStack: 1, at: 0))
        XCTAssertEqual(moved[0].activeCards.map(\.id), [11, 10])
    }

    func testMovingAnUnknownCardChangesNothing() throws {
        XCTAssertNil(try board().movingCard(99, toStack: 2, at: 0))
        XCTAssertNil(try board().movingCard(10, toStack: 99, at: 0))
    }
}
