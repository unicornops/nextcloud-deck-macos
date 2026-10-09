import Foundation
import XCTest
@testable import Shuffleboard

/// Searching every board's cards (#158).
final class CardSearchTests: XCTestCase {
    private func card(_ id: Int, _ title: String, _ more: String = "") throws -> Card {
        let json = #"{"id": \#(id), "title": "\#(title)", "stackId": 1, "order": \#(id)\#(more)}"#
        return try JSONDecoder().decode(Card.self, from: Data(json.utf8))
    }

    private func board(_ id: Int, _ title: String) -> Board {
        Board(
            id: id,
            title: title,
            color: nil,
            archived: false,
            owner: nil,
            labels: [],
            acl: [],
            permissions: nil,
            users: [],
            shared: nil,
            deletedAt: nil,
            lastModified: nil,
            settings: nil
        )
    }

    func testEveryWordMustBeInTheTitleDescriptionLabelsOrAssignees() throws {
        let card = try card(1, "Fix the Café sign", #"""
        , "description": "Ask the printer",
        "labels": [{"id": 1, "title": "Urgent", "color": "ff0000"}],
        "assignedUsers": [{"id": 1, "participant": {"primaryKey": "bob", "uid": "bob", "displayname": "Bob Byrne"},
                           "type": 0}]
        """#)
        for query in ["cafe", "SIGN printer", "urgent fix", "byrne", "  fix   sign "] {
            XCTAssertTrue(CardSearch.matches(card, words: CardSearch.words(in: query)), query)
        }
        for query in ["cafe menu", "alice", ""] {
            XCTAssertFalse(CardSearch.matches(card, words: CardSearch.words(in: query)), query)
        }
    }

    func testResultsAreGroupedByBoardWithArchivedCardsLast() throws {
        let home = board(1, "Home")
        let work = board(2, "Work")
        let empty = board(3, "Nothing here")
        let cards: [Int: SearchableCards] = try [
            1: SearchableCards(
                stacks: [
                    Stack(id: 11, title: "Later", boardId: 1, cards: [card(3, "Paint fence")], order: 1),
                    Stack(id: 10, title: "Now", boardId: 1, cards: [card(4, "Paint door"), card(2, "Mow")], order: 0),
                ],
                archivedStacks: [
                    Stack(id: 10, title: "Now", boardId: 1, cards: [card(1, "Paint shed", #", "archived": true"#)]),
                ]
            ),
            2: SearchableCards(stacks: [Stack(id: 20, title: "Doing", boardId: 2, cards: [card(5, "Paint office")])]),
            3: SearchableCards(stacks: [Stack(id: 30, title: "To do", boardId: 3, cards: [card(6, "Email")])]),
        ]

        let groups = CardSearch.results(for: "paint", in: [work, home, empty]) { cards[$0.id] ?? SearchableCards() }

        XCTAssertEqual(groups.map(\.board.title), ["Work", "Home"], "in the boards' order, without empty ones")
        XCTAssertEqual(groups[1].results.map(\.card.title), ["Paint door", "Paint fence", "Paint shed"])
        XCTAssertEqual(groups[1].results.map(\.listTitle), ["Now", "Later", "Now"])
        XCTAssertEqual(groups[1].results.map(\.card.archived), [false, false, true])
        XCTAssertTrue(CardSearch.results(for: "  ", in: [home]) { cards[$0.id] ?? SearchableCards() }.isEmpty)
    }
}
