import XCTest
@testable import Shuffleboard

/// Moving the selection and the selected card with the keyboard (#159).
final class CardNavigationTests: XCTestCase {
    /// "To do" has cards 1, 2 and 3, "Doing" is empty and "Done" has card 4.
    private var stacks: [Stack] = []

    override func setUpWithError() throws {
        stacks = try [
            Stack(
                id: 10,
                title: "To do",
                boardId: 1,
                cards: [card(1, 10, 0), card(2, 10, 1), card(3, 10, 2)],
                order: 0
            ),
            Stack(id: 20, title: "Doing", boardId: 1, cards: [], order: 1),
            Stack(id: 30, title: "Done", boardId: 1, cards: [card(4, 30, 0)], order: 2),
        ]
    }

    private func select(from id: Int?, _ direction: CardDirection, hiding hidden: Set<Int> = []) -> Int? {
        stacks.cardId(from: id, moving: direction) { $0.activeCards.filter { !hidden.contains($0.id) } }
    }

    func testWithNothingSelectedAnyArrowSelectsTheFirstCard() {
        for direction in [CardDirection.up, .down, .left, .right] {
            XCTAssertEqual(select(from: nil, direction), 1)
        }
        XCTAssertEqual(select(from: 99, .down), 1, "a card no longer on the board")
        XCTAssertEqual(select(from: nil, .down, hiding: [1, 2]), 3, "the first card the filter shows")
    }

    func testUpAndDownStayInTheList() {
        XCTAssertEqual(select(from: 1, .down), 2)
        XCTAssertEqual(select(from: 3, .up), 2)
        XCTAssertNil(select(from: 1, .up))
        XCTAssertNil(select(from: 3, .down))
        XCTAssertEqual(select(from: 1, .down, hiding: [2]), 3, "skips hidden cards")
    }

    func testLeftAndRightSkipEmptyListsAndKeepThePosition() {
        XCTAssertEqual(select(from: 3, .right), 4, "the last card of a shorter list")
        XCTAssertEqual(select(from: 4, .left), 1, "the same position")
        XCTAssertNil(select(from: 4, .right))
        XCTAssertNil(select(from: 1, .left))
        XCTAssertNil(select(from: 1, .right, hiding: [4]), "no shown cards to the right")
    }

    func testMovingACardUpAndDown() throws {
        let down = try XCTUnwrap(stacks.destination(movingCard: 1, .down))
        XCTAssertEqual(down.stackId, 10)
        XCTAssertEqual(down.order, 1)
        let up = try XCTUnwrap(stacks.destination(movingCard: 3, .up))
        XCTAssertEqual(up.stackId, 10)
        XCTAssertEqual(up.order, 1)
        XCTAssertNil(stacks.destination(movingCard: 1, .up))
        XCTAssertNil(stacks.destination(movingCard: 3, .down))
    }

    func testMovingACardToTheNextListIncludingAnEmptyOne() throws {
        let right = try XCTUnwrap(stacks.destination(movingCard: 3, .right))
        XCTAssertEqual(right.stackId, 20, "into the empty list beside it")
        XCTAssertEqual(right.order, 0)
        let left = try XCTUnwrap(stacks.destination(movingCard: 4, .left))
        XCTAssertEqual(left.stackId, 20)
        XCTAssertNil(stacks.destination(movingCard: 1, .left))
        XCTAssertNil(stacks.destination(movingCard: 4, .right))
        XCTAssertNil(stacks.destination(movingCard: 99, .down))
    }
}

private func card(_ id: Int, _ stackId: Int, _ order: Int) throws -> Card {
    let json = #"{"id": \#(id), "title": "Card \#(id)", "stackId": \#(stackId), "order": \#(order)}"#
    return try JSONDecoder().decode(Card.self, from: Data(json.utf8))
}
