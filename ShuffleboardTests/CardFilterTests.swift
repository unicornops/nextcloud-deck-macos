import Foundation
import XCTest
@testable import Shuffleboard

/// Board filtering (#78).
final class CardFilterTests: XCTestCase {
    private let now = DeckDate.parse("2026-10-06T12:00:00+00:00") ?? Date()

    private func card(_ fields: String) throws -> Card {
        // No "title" here: tests that need one pass it, and a duplicate key would be ambiguous.
        let json = #"{"id": 1, "stackId": 2, "order": 0, "archived": false, "#
        return try JSONDecoder().decode(Card.self, from: Data((json + fields + "}").utf8))
    }

    private func matches(_ filter: CardFilter, _ fields: String) throws -> Bool {
        try filter.matches(card(fields), at: now)
    }

    func testEmptyFilterMatchesEverythingAndIsInactive() throws {
        XCTAssertFalse(CardFilter().isActive)
        XCTAssertFalse(CardFilter(text: "   ").isActive, "whitespace alone doesn't pause drag and drop")
        XCTAssertTrue(try matches(CardFilter(), #""description": null"#))
    }

    func testTextMatchesTitleOrDescriptionIgnoringCaseAndAccents() throws {
        let filter = CardFilter(text: "  cafe ")
        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(try matches(filter, #""title": "Visit the Café""#))
        XCTAssertTrue(try matches(filter, #""title": "Errand", "description": "pick up CAFE beans""#))
        XCTAssertFalse(try matches(filter, #""title": "Errand", "description": "groceries""#))
    }

    func testLabelsMatchAnySelected() throws {
        let filter = CardFilter(labelIds: [1, 3])
        XCTAssertTrue(try matches(filter, #""labels": [{"id": 3, "title": "Urgent", "color": "ff0000"}]"#))
        XCTAssertFalse(try matches(filter, #""labels": [{"id": 2, "title": "Later", "color": "00ff00"}]"#))
        XCTAssertFalse(try matches(filter, #""labels": []"#))
    }

    func testAssigneesMatchAnySelected() throws {
        let filter = CardFilter(assigneeIds: ["alice"])
        XCTAssertTrue(try matches(filter, #""assignedUsers": [{"id": 1, "participant": {"uid": "alice"}, "type": 0}]"#))
        XCTAssertFalse(try matches(filter, #""assignedUsers": [{"id": 1, "participant": {"uid": "bob"}, "type": 0}]"#))
        XCTAssertFalse(try matches(filter, #""assignedUsers": []"#))
    }

    func testDueOptions() throws {
        let overdue = #""duedate": "2026-10-01T09:00:00+00:00""#
        let soon = #""duedate": "2026-10-09T09:00:00+00:00""#
        let later = #""duedate": "2026-11-20T09:00:00+00:00""#
        let none = #""description": null"#

        let overdueFilter = CardFilter(due: .overdue)
        XCTAssertTrue(try matches(overdueFilter, overdue))
        XCTAssertFalse(try matches(overdueFilter, soon))

        let soonFilter = CardFilter(due: .dueSoon)
        XCTAssertTrue(try matches(soonFilter, soon))
        XCTAssertFalse(try matches(soonFilter, later))
        XCTAssertFalse(try matches(soonFilter, overdue), "overdue isn't 'due in the next 7 days'")
        XCTAssertFalse(try matches(soonFilter, soon + #", "done": "2026-10-05T09:00:00+00:00""#))

        let noneFilter = CardFilter(due: .noDueDate)
        XCTAssertTrue(try matches(noneFilter, none))
        XCTAssertFalse(try matches(noneFilter, later))
    }

    func testHideDone() throws {
        let filter = CardFilter(hideDone: true)
        XCTAssertFalse(try matches(filter, #""done": "2026-10-05T09:00:00+00:00""#))
        XCTAssertTrue(try matches(filter, #""done": null"#))
    }

    func testAllCriteriaMustMatch() throws {
        let filter = CardFilter(text: "report", labelIds: [3])
        XCTAssertTrue(try matches(filter, #""title": "Q3 report", "labels": [{"id": 3, "title": "Urgent"}]"#))
        XCTAssertFalse(try matches(filter, #""title": "Q3 report", "labels": []"#))
        XCTAssertFalse(try matches(filter, #""title": "Budget", "labels": [{"id": 3, "title": "Urgent"}]"#))
    }
}
