import Foundation

// MARK: - Blocks

/// A block of a Markdown card description. Inline styles (bold, links, code) stay in the text and are rendered
/// with `AttributedString(markdown:)`; this only covers the block structure SwiftUI's `Text` doesn't lay out.
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String, indent: Int)
    case numbered(number: Int, text: String, indent: Int)
    /// A Deck checklist item (`- [ ] text` / `- [x] text`); `line` is its index in the description's lines.
    case task(done: Bool, text: String, indent: Int, line: Int)
    case quote(String)
    case code(String)
    case rule
}

// MARK: - Markdown

/// Block parsing, checklist progress and checkbox toggling for Deck's Markdown descriptions.
enum Markdown {
    /// Checklist progress of a description, or nil if it has no checklist items.
    struct Progress: Equatable, Sendable {
        let done: Int
        let total: Int

        var isComplete: Bool {
            done == total
        }
    }

    static func blocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for (index, line) in lines(text).enumerated() {
            if isFence(line) {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            guard let block = block(for: line, at: index) else {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushParagraph()
                } else {
                    paragraph.append(line)
                }
                continue
            }
            flushParagraph()
            blocks.append(block)
        }
        flushParagraph()
        if let open = code {
            // An unclosed fence still shows its contents as code.
            blocks.append(.code(open.joined(separator: "\n")))
        }
        return blocks
    }

    /// Checklist progress, ignoring anything inside code blocks.
    static func progress(_ text: String) -> Progress? {
        var done = 0
        var total = 0
        for case let .task(isDone, _, _, _) in blocks(text) {
            total += 1
            if isDone {
                done += 1
            }
        }
        guard total > 0 else { return nil }
        return Progress(done: done, total: total)
    }

    /// The description with the checklist item on `line` ticked or unticked; other lines are unchanged.
    static func togglingTask(atLine line: Int, in text: String) -> String {
        var all = lines(text)
        guard all.indices.contains(line),
              let match = all[line].firstMatch(of: taskPattern) else { return text }
        let box = match.output.1
        let toggled = box.trimmingCharacters(in: .whitespaces).isEmpty ? "x" : " "
        all[line].replaceSubrange(box.startIndex ..< box.endIndex, with: toggled)
        return all.joined(separator: "\n")
    }

    // MARK: - Lines

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    /// Two spaces (or a tab) per nesting level.
    private static func indent(_ whitespace: Substring) -> Int {
        whitespace.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
    }

    private nonisolated(unsafe) static let taskPattern = /^\s*[-*+]\s+\[([ xX])\]\s+/
    private nonisolated(unsafe) static let headingPattern = /^(#{1,6})\s+(.*?)\s*#*$/
    private nonisolated(unsafe) static let taskLinePattern = /^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$/
    private nonisolated(unsafe) static let bulletPattern = /^(\s*)[-*+]\s+(.*)$/
    private nonisolated(unsafe) static let numberedPattern = /^(\s*)(\d+)[.)]\s+(.*)$/
    private nonisolated(unsafe) static let quotePattern = /^\s*>\s?(.*)$/
    private nonisolated(unsafe) static let rulePattern = /^\s*([-*_])(\s*\1){2,}\s*$/

    private static func block(for line: String, at index: Int) -> MarkdownBlock? {
        if line.wholeMatch(of: rulePattern) != nil {
            return .rule
        }
        if let match = line.wholeMatch(of: headingPattern) {
            return .heading(level: match.output.1.count, text: String(match.output.2))
        }
        if let match = line.wholeMatch(of: taskLinePattern) {
            let done = match.output.2 != " "
            return .task(done: done, text: String(match.output.3), indent: indent(match.output.1), line: index)
        }
        if let match = line.wholeMatch(of: bulletPattern) {
            return .bullet(text: String(match.output.2), indent: indent(match.output.1))
        }
        if let match = line.wholeMatch(of: numberedPattern), let number = Int(match.output.2) {
            return .numbered(number: number, text: String(match.output.3), indent: indent(match.output.1))
        }
        if let match = line.wholeMatch(of: quotePattern) {
            return .quote(String(match.output.1))
        }
        return nil
    }
}

extension Card {
    /// Checklist progress of the description, or nil if it has no checklist items.
    var checklistProgress: Markdown.Progress? {
        description.flatMap(Markdown.progress)
    }
}
