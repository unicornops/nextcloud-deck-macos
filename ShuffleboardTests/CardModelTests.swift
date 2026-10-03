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
}
