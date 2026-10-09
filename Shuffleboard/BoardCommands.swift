import AppKit
import SwiftUI

/// The menu bar commands for boards, lists and cards (#159). Each has a shortcut, so the common actions don't need
/// the mouse, and VoiceOver and Full Keyboard Access reach them through the menus. Card commands act on the selected
/// card, which the arrow keys move around the board.
struct BoardCommands: Commands {
    @ObservedObject var appState: AppState

    private var isSignedIn: Bool {
        appState.isLoggedIn && !appState.showingLogin
    }

    /// A board is open and no card's sheet is in front of it.
    private var boardIsOpen: Bool {
        isSignedIn && appState.selectedBoard != nil && appState.openedCard == nil
    }

    private var cardIsSelected: Bool {
        boardIsOpen && appState.selectedCard != nil
    }

    private var canMoveCard: Bool {
        boardIsOpen && appState.canMoveSelectedCard
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Card") {
                appState.startNewCard()
            }
            .keyboardShortcut("n")
            .disabled(!boardIsOpen || appState.stacks.isEmpty)
            Button("New List\u{2026}") {
                appState.showingNewStack = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!boardIsOpen)
            Button("New Board\u{2026}") {
                appState.showingNewBoard = true
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!isSignedIn)
            Divider()
            Button("Refresh") {
                Task { await appState.refresh() }
            }
            .keyboardShortcut("r")
            .disabled(!isSignedIn)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Filter Cards") {
                appState.filterFocusRequest += 1
            }
            .keyboardShortcut("f")
            .disabled(!boardIsOpen)
            Button("Search All Boards") {
                appState.cardSearchFocusRequest += 1
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!isSignedIn)
        }
        CommandMenu("Card") {
            Button("Open Card") {
                appState.openSelectedCard()
            }
            .keyboardShortcut("o")
            .disabled(!cardIsSelected)
            Button(appState.selectedCard?.isDone == true ? "Mark as Not Done" : "Mark as Done") {
                Task { await appState.toggleSelectedCardDone() }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!cardIsSelected)
            Button("Archive Card") {
                Task { await appState.archiveSelectedCard() }
            }
            .keyboardShortcut("a", modifiers: [.command, .control])
            .disabled(!cardIsSelected)
            Button("Delete Card\u{2026}") {
                deleteCardOrText()
            }
            .keyboardShortcut(.delete)
            .disabled(!cardIsSelected)
            Divider()
            moveButton("Move Up", .up, key: .upArrow)
            moveButton("Move Down", .down, key: .downArrow)
            moveButton("Move to Previous List", .left, key: .leftArrow)
            moveButton("Move to Next List", .right, key: .rightArrow)
        }
        CommandGroup(before: .sidebar) {
            Button("Previous Board") {
                appState.selectBoard(offset: -1)
            }
            .keyboardShortcut("[")
            .disabled(!isSignedIn || appState.boardsInSidebarOrder.isEmpty)
            Button("Next Board") {
                appState.selectBoard(offset: 1)
            }
            .keyboardShortcut("]")
            .disabled(!isSignedIn || appState.boardsInSidebarOrder.isEmpty)
            ForEach(Array(appState.activeBoards.prefix(9).enumerated()), id: \.element.id) { index, board in
                Button(board.title) {
                    appState.selectedBoardId = board.id
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                .disabled(!isSignedIn)
            }
            Divider()
        }
    }

    private func moveButton(_ title: String, _ direction: CardDirection, key: KeyEquivalent) -> some View {
        Button(title) {
            Task { await appState.moveSelectedCard(direction) }
        }
        .keyboardShortcut(key, modifiers: [.command, .option])
        .disabled(!canMoveCard)
    }

    /// ⌘⌫ deletes the selected card, except while typing, where it keeps deleting to the start of the line.
    private func deleteCardOrText() {
        if NSApp.keyWindow?.firstResponder is NSText {
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
        } else {
            appState.requestDeletingSelectedCard()
        }
    }
}
