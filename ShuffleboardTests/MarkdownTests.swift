import Foundation
import XCTest
@testable import Shuffleboard

/// Markdown descriptions (#77): block parsing, checklist progress and checkbox toggling.
final class MarkdownTests: XCTestCase {
    private let sample = """
    # Plan
    Some **bold** text
    continues here

    - [ ] Buy milk
    - [x] Write code
      - nested bullet
    1. first
    2) second
    > quoted
    ---
    ```
    - [ ] not a task
    ```
    """

    func testBlocks() {
        XCTAssertEqual(Markdown.blocks(sample), [
            .heading(level: 1, text: "Plan"),
            .paragraph("Some **bold** text\ncontinues here"),
            .task(done: false, text: "Buy milk", indent: 0, line: 4),
            .task(done: true, text: "Write code", indent: 0, line: 5),
            .bullet(text: "nested bullet", indent: 1),
            .numbered(number: 1, text: "first", indent: 0),
            .numbered(number: 2, text: "second", indent: 0),
            .quote("quoted"),
            .rule,
            .code("- [ ] not a task"),
        ])
    }

    func testInlineMarkersAreNotLists() {
        XCTAssertEqual(Markdown.blocks("*emphasis* here\n**bold** there"), [
            .paragraph("*emphasis* here\n**bold** there"),
        ])
        XCTAssertEqual(Markdown.blocks("#hashtag"), [.paragraph("#hashtag")])
    }

    func testUnclosedCodeFenceStillShowsAsCode() {
        XCTAssertEqual(Markdown.blocks("```\nlet x = 1"), [.code("let x = 1")])
    }

    func testProgressIgnoresCodeBlocks() {
        XCTAssertEqual(Markdown.progress(sample), Markdown.Progress(done: 1, total: 2))
        XCTAssertNil(Markdown.progress("Just text"))
        XCTAssertEqual(Markdown.progress("- [X] Done\n* [x] Also done")?.isComplete, true)
    }

    func testTogglingChangesOnlyThatLine() {
        let ticked = Markdown.togglingTask(atLine: 4, in: sample)
        let lines = ticked.components(separatedBy: "\n")
        XCTAssertEqual(lines[4], "- [x] Buy milk")
        XCTAssertEqual(lines.count, sample.components(separatedBy: "\n").count)
        XCTAssertEqual(Markdown.togglingTask(atLine: 4, in: ticked), sample, "toggling twice restores the text")
        XCTAssertEqual(
            Markdown.togglingTask(atLine: 5, in: sample).components(separatedBy: "\n")[5],
            "- [ ] Write code"
        )
    }

    func testTogglingIgnoresNonTaskAndMissingLines() {
        XCTAssertEqual(Markdown.togglingTask(atLine: 0, in: sample), sample)
        XCTAssertEqual(Markdown.togglingTask(atLine: 99, in: sample), sample)
    }

    func testWindowsLineEndings() {
        XCTAssertEqual(Markdown.progress("- [ ] a\r\n- [x] b"), Markdown.Progress(done: 1, total: 2))
    }

    func testCardChecklistProgress() throws {
        let card = try JSONDecoder().decode(Card.self, from: Data(#"""
        {"id": 1, "title": "t", "stackId": 2, "order": 0, "archived": false,
         "description": "- [x] one\n- [ ] two\n- [ ] three"}
        """#.utf8))
        XCTAssertEqual(card.checklistProgress, Markdown.Progress(done: 1, total: 3))
    }
}
