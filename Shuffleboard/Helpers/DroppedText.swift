import AppKit
import os

/// Logs drags and drops by card and list id (never titles), to diagnose moves that don't happen:
/// `log stream --level debug --predicate 'subsystem == "ie.unicornops.shuffleboard"'`.
let dragLogger = Logger(subsystem: "ie.unicornops.shuffleboard", category: "DragAndDrop")

extension [NSItemProvider] {
    /// Loads the text of a drop (a dragged card or list) and passes it to `completion`, on a background queue.
    /// Returns `false` if nothing in the drop is text.
    ///
    /// Asks for the text as an `NSString` object rather than by one type identifier. A dragged string is on the
    /// pasteboard as `public.utf8-plain-text`; loading it as `public.plain-text` can come back empty, which made
    /// drops do nothing and the card snap back.
    func loadDroppedText(_ completion: @escaping @Sendable (String) -> Void) -> Bool {
        guard let provider = first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            dragLogger.notice("Drop ignored: no text in \(self.count) item(s)")
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { @Sendable object, error in
            guard let text = object as? NSString else {
                dragLogger.error("Drop ignored: couldn't load its text: \(String(describing: error), privacy: .public)")
                return
            }
            completion(text as String)
        }
        return true
    }
}
