import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var boards: [Board] = []
    @Published var selectedBoardId: Int?
    @Published var stacks: [Stack] = []
    @Published var isLoading = false
    @Published var isLoadingStacks = false
    /// Errors shown inline where they happen: the login screen, the empty sidebar and the create sheets.
    @Published var errorMessage: String?
    /// Errors from actions that have no UI of their own (moving, deleting, labelling…), shown as a banner.
    @Published var actionError: String?
    @Published var stacksError: String?
    @Published var showingLogin = false
    @Published var showingAbout = false
    @Published var isDraggingStack = false

    private var deckAPI: DeckAPI?
    /// The board `stacks` currently belongs to.
    private var stacksBoardId: Int?
    /// Incremented by every `loadStacks` call; a response is only applied if no newer load has started.
    private var stacksGeneration = 0
    private var credentials: (serverURL: URL, username: String, appPassword: String)?

    var selectedBoard: Board? {
        guard let id = selectedBoardId else { return nil }
        return boards.first { $0.id == id }
    }

    /// Boards that are not archived and not soft-deleted.
    var activeBoards: [Board] {
        boards.filter { !$0.archived && ($0.deletedAt == nil || $0.deletedAt == 0) }
    }

    /// Boards that are archived but not soft-deleted.
    var archivedBoards: [Board] {
        boards.filter { $0.archived && ($0.deletedAt == nil || $0.deletedAt == 0) }
    }

    init() {
        if let creds = KeychainStorage.load() {
            self.credentials = creds
            self.deckAPI = DeckAPI(serverURL: creds.serverURL, username: creds.username, appPassword: creds.appPassword)
            self.isLoggedIn = true
            Task { await loadBoards() }
        } else {
            self.showingLogin = true
        }
    }

    func login(serverURL: URL, username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let appPassword = try await NextcloudAuth.getAppPassword(
                serverURL: serverURL,
                username: username,
                password: password
            )
            let storedURL = try KeychainStorage.save(serverURL: serverURL, username: username, appPassword: appPassword)
            credentials = (storedURL, username, appPassword)
            deckAPI = DeckAPI(serverURL: storedURL, username: username, appPassword: appPassword)
            isLoggedIn = true
            showingLogin = false
            await loadBoards()
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("two-factor") || msg.lowercased().contains("2fa") || msg.lowercased()
                .contains("second factor") {
                errorMessage = "This account uses two-factor authentication. Use “Sign in with browser” above."
            } else {
                errorMessage = msg
            }
        }
    }

    /// The in-flight browser sign-in, if any; cancelled by `cancelLogin()`.
    private var loginTask: Task<Void, Never>?
    /// Identifies the current sign-in attempt, so a cancelled one can't change the state of a newer one.
    private var loginAttempt = 0

    /// Starts signing in via the browser (Login Flow v2). Supports 2FA: the user completes login and 2FA
    /// in the browser while the app waits. `cancelLogin()` stops waiting.
    func startBrowserLogin(serverURL: URL) {
        loginTask?.cancel()
        loginTask = Task { await loginWithBrowser(serverURL: serverURL) }
    }

    /// Stops waiting for a browser sign-in started with `startBrowserLogin(serverURL:)`.
    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginAttempt += 1
        isLoading = false
    }

    /// Sign in via browser (Login Flow v2). Supports 2FA — user completes login and 2FA in the browser.
    func loginWithBrowser(serverURL: URL) async {
        loginAttempt += 1
        let attempt = loginAttempt
        isLoading = true
        errorMessage = nil
        defer {
            if attempt == loginAttempt {
                isLoading = false
            }
        }
        do {
            let (url, loginName, appPassword) = try await NextcloudAuth.loginWithBrowser(serverURL: serverURL)
            try Task.checkCancellation()
            let storedURL = try KeychainStorage.save(serverURL: url, username: loginName, appPassword: appPassword)
            credentials = (storedURL, loginName, appPassword)
            deckAPI = DeckAPI(serverURL: storedURL, username: loginName, appPassword: appPassword)
            isLoggedIn = true
            showingLogin = false
            await loadBoards()
        } catch {
            // Cancelled by the user: either `CancellationError` or a request torn down mid-flight.
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Shows `error` in the action error banner.
    func report(_ error: Error) {
        guard !endSessionIfUnauthorized(error) else { return }
        actionError = error.localizedDescription
    }

    /// If `error` means the app password was revoked or has expired, signs out and returns to the login
    /// screen with an explanation. Returns `true` if it did, so the caller shows nothing further.
    @discardableResult
    func endSessionIfUnauthorized(_ error: Error) -> Bool {
        guard case .unauthorized? = error as? DeckAPIError else { return false }
        // Requests still in flight from the ended session may fail the same way; handle it once.
        if isLoggedIn {
            logout()
            errorMessage = error.localizedDescription
        }
        return true
    }

    /// Signs out at the user's request: ends the session locally straight away, then revokes the app
    /// password on the server so it stops working and leaves the user's Nextcloud device list.
    /// Revocation failures (offline, server unreachable) are ignored; the local sign-out has already happened.
    func signOut() async {
        let api = deckAPI
        logout()
        try? await api?.revokeAppPassword()
    }

    /// Ends the session locally: forgets the stored credentials and returns to the login screen.
    /// Does not contact the server; see `signOut()`.
    func logout() {
        try? KeychainStorage.delete()
        credentials = nil
        deckAPI = nil
        isLoggedIn = false
        boards = []
        selectedBoardId = nil
        clearStacks()
        actionError = nil
        showingLogin = true
    }

    func loadBoards() async {
        guard deckAPI != nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let api = deckAPI else { return }
            boards = try await api.getBoards(details: true)
            if selectedBoardId == nil, let first = boards.first {
                // BoardDetailView's `.task(id: selectedBoardId)` loads the newly selected board's lists.
                selectedBoardId = first.id
            } else if let bid = selectedBoardId {
                await loadStacks(boardId: bid)
            }
        } catch {
            guard !endSessionIfUnauthorized(error) else { return }
            errorMessage = error.localizedDescription
            // The sidebar only shows `errorMessage` when there are no boards; a failed refresh needs the banner.
            if !boards.isEmpty {
                report(error)
            }
        }
    }

    /// Call when main interface appears so boards are loaded (e.g. after launch with Keychain or after login).
    func loadBoardsIfNeeded() async {
        guard isLoggedIn else { return }
        await loadBoards()
    }

    /// Loads the lists for `boardId` if it is the selected board.
    ///
    /// The current lists stay on screen while the same board is refreshed; they are only cleared when
    /// switching boards. If loads overlap, only the most recent one's result is applied, so a slow
    /// response for a previously selected board can never replace the current board's lists.
    func loadStacks(boardId: Int) async {
        guard let api = deckAPI, selectedBoardId == boardId else { return }
        stacksGeneration += 1
        let generation = stacksGeneration
        if stacksBoardId != boardId {
            stacks = []
            stacksBoardId = boardId
        }
        stacksError = nil
        isLoadingStacks = true

        let result: Result<[Stack], Error>
        do {
            let loaded = try await api.getStacks(boardId: boardId)
            result = .success(loaded)
        } catch {
            result = .failure(error)
        }

        guard generation == stacksGeneration, selectedBoardId == boardId else { return }
        isLoadingStacks = false
        switch result {
        case let .success(loaded):
            stacks = loaded.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        case let .failure(error):
            guard !endSessionIfUnauthorized(error) else { return }
            // A cancelled load (the board view went away) is not an error worth showing.
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                stacksError = error.localizedDescription
            }
        }
    }

    /// Clears the lists when no board is selected.
    func clearStacks() {
        stacksGeneration += 1
        stacks = []
        stacksBoardId = nil
        stacksError = nil
        isLoadingStacks = false
    }

    func selectBoard(_ board: Board) {
        // BoardDetailView's `.task(id: selectedBoardId)` loads the lists.
        selectedBoardId = board.id
    }

    func refresh() async {
        await loadBoards()
    }

    func createCard(boardId: Int, stackId: Int, title: String) async {
        guard let api = deckAPI else { return }
        do {
            _ = try await api.createCard(boardId: boardId, stackId: stackId, title: title)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    func archiveBoard(id: Int) async {
        guard let api = deckAPI,
              let board = boards.first(where: { $0.id == id }) else { return }
        do {
            _ = try await api.updateBoard(id: id, title: board.title, color: board.color, archived: true)
            if let idx = boards.firstIndex(where: { $0.id == id }) {
                boards[idx].archived = true
            }
            if selectedBoardId == id {
                selectedBoardId = activeBoards.first?.id
            }
        } catch {
            report(error)
        }
    }

    func unarchiveBoard(id: Int) async {
        guard let api = deckAPI,
              let board = boards.first(where: { $0.id == id }) else { return }
        do {
            _ = try await api.updateBoard(id: id, title: board.title, color: board.color, archived: false)
            if let idx = boards.firstIndex(where: { $0.id == id }) {
                boards[idx].archived = false
            }
        } catch {
            report(error)
        }
    }

    func restoreBoard(id: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.undoDeleteBoard(id: id)
            await loadBoards()
        } catch {
            report(error)
        }
    }

    func deleteBoard(id: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.deleteBoard(id: id)
            boards.removeAll { $0.id == id }
            if selectedBoardId == id {
                selectedBoardId = boards.first?.id
            }
        } catch {
            report(error)
        }
    }

    /// Returns `true` if the board was created successfully, `false` otherwise (and sets `errorMessage`).
    func createBoard(title: String, color: String) async -> Bool {
        guard let api = deckAPI else { return false }
        do {
            _ = try await api.createBoard(title: title, color: color)
            await loadBoards()
            return true
        } catch {
            guard !endSessionIfUnauthorized(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Returns `true` if the stack was created successfully, `false` otherwise (and sets `errorMessage`).
    func createStack(boardId: Int, title: String) async -> Bool {
        guard let api = deckAPI else { return false }
        do {
            _ = try await api.createStack(boardId: boardId, title: title)
            await loadStacks(boardId: boardId)
            return true
        } catch {
            guard !endSessionIfUnauthorized(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// True while `reorderStacks` is saving, so a second drag can't interleave its updates with the first.
    private var isReorderingStacks = false

    /// Reorders stacks by moving the stack at `fromIndex` to `toIndex`, then
    /// persists the new order values to the server.
    ///
    /// The Deck API has no bulk reorder, so each moved stack is updated in turn. If one update fails the
    /// rest are not sent, the error is shown and the lists are reloaded so the screen matches the server.
    func reorderStacks(boardId: Int, fromIndex: Int, toIndex: Int) async {
        guard let api = deckAPI, !isReorderingStacks,
              selectedBoardId == boardId, stacksBoardId == boardId else { return }
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < stacks.count,
              toIndex >= 0, toIndex <= stacks.count else { return }
        isReorderingStacks = true
        defer { isReorderingStacks = false }

        // Move the stack in the local array
        let moving = stacks.remove(at: fromIndex)
        let insertAt = toIndex > fromIndex ? toIndex - 1 : toIndex
        stacks.insert(moving, at: insertAt)

        // Assign sequential order values and persist to server
        let changes = stacks.enumerated().filter { $0.element.order != $0.offset }
        for (idx, _) in changes {
            stacks[idx].order = idx
        }
        for (newOrder, stack) in changes {
            do {
                _ = try await api.updateStack(
                    boardId: boardId,
                    stackId: stack.id,
                    title: stack.title,
                    order: newOrder
                )
            } catch {
                report(error)
                await loadStacks(boardId: boardId)
                return
            }
        }
    }

    /// Permanently deletes the stack and its cards from the board.
    func deleteStack(boardId: Int, stackId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.deleteStack(boardId: boardId, stackId: stackId)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    /// Saves a new title and description for `card`, keeping its other fields as they are.
    /// Returns `true` if the card was saved, `false` otherwise (and sets `errorMessage`).
    func updateCard(boardId: Int, stackId: Int, card: Card, title: String, description: String) async -> Bool {
        guard let api = deckAPI else { return false }
        var updated = card
        updated.title = title
        updated.description = description
        do {
            _ = try await api.updateCard(boardId: boardId, stackId: stackId, card: updated)
            await loadStacks(boardId: boardId)
            return true
        } catch {
            guard !endSessionIfUnauthorized(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Returns `true` if the card was deleted, `false` otherwise (and shows the error banner).
    @discardableResult
    func deleteCard(boardId: Int, stackId: Int, cardId: Int) async -> Bool {
        guard let api = deckAPI else { return false }
        do {
            try await api.deleteCard(boardId: boardId, stackId: stackId, cardId: cardId)
            await loadStacks(boardId: boardId)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Moves a card to position `order` in `toStackId`, which may be the stack it is already in.
    func reorderCard(boardId: Int, fromStackId: Int, cardId: Int, toStackId: Int, order: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.reorderCard(
                boardId: boardId,
                stackId: fromStackId,
                cardId: cardId,
                order: order,
                newStackId: toStackId
            )
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    /// Moves a card into a different stack at position `order`.
    func moveCard(boardId: Int, cardId: Int, fromStackId: Int, toStackId: Int, order: Int) async {
        guard fromStackId != toStackId else { return }
        await reorderCard(
            boardId: boardId,
            fromStackId: fromStackId,
            cardId: cardId,
            toStackId: toStackId,
            order: order
        )
    }

    func assignLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.assignLabel(boardId: boardId, stackId: stackId, cardId: cardId, labelId: labelId)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    func removeLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.removeLabel(boardId: boardId, stackId: stackId, cardId: cardId, labelId: labelId)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    /// Creates a new label on the board and refreshes board/stacks. Returns the new label id if successful.
    func createLabel(boardId: Int, title: String, color: String) async -> Int? {
        guard let api = deckAPI else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let label = try await api.createLabel(boardId: boardId, title: trimmed, color: color)
            // Reloads the board's labels and, for the selected board, its lists.
            await loadBoards()
            return label.id
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: - Attachments

    /// Fetches the full card (including attachments) from the API.
    func getFullCard(boardId: Int, stackId: Int, cardId: Int) async -> Card? {
        guard let api = deckAPI else { return nil }
        do {
            return try await api.getCard(boardId: boardId, stackId: stackId, cardId: cardId)
        } catch {
            report(error)
            return nil
        }
    }

    /// Fetches attachments for a card.
    func getAttachments(boardId: Int, stackId: Int, cardId: Int) async -> [Attachment] {
        guard let api = deckAPI else { return [] }
        do {
            return try await api.getAttachments(boardId: boardId, stackId: stackId, cardId: cardId)
        } catch {
            report(error)
            return []
        }
    }

    /// Downloads an attachment and saves it to the user's chosen location.
    func downloadAttachment(
        boardId: Int,
        stackId: Int,
        cardId: Int,
        attachment: Attachment,
        saveURL: URL
    ) async
        -> Bool {
        guard let api = deckAPI else { return false }
        do {
            let data = try await api.downloadAttachment(
                boardId: boardId,
                stackId: stackId,
                cardId: cardId,
                attachmentId: attachment.id,
                type: attachment.type
            )
            try data.write(to: saveURL)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Uploads a file as an attachment to a card. Refreshes stacks on success.
    /// Returns `true` if the upload succeeded, `false` otherwise (and shows the error banner).
    func uploadAttachment(boardId: Int, stackId: Int, cardId: Int, fileURL: URL) async -> Bool {
        guard let api = deckAPI else { return false }
        do {
            try await api.uploadAttachment(
                boardId: boardId,
                stackId: stackId,
                cardId: cardId,
                fileURL: fileURL,
                filename: fileURL.lastPathComponent
            )
            await loadStacks(boardId: boardId)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Deletes an attachment from a card.
    func deleteAttachment(boardId: Int, stackId: Int, cardId: Int, attachmentId: Int, type: String? = nil) async {
        guard let api = deckAPI else { return }
        do {
            try await api.deleteAttachment(
                boardId: boardId,
                stackId: stackId,
                cardId: cardId,
                attachmentId: attachmentId,
                type: type
            )
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }
}
