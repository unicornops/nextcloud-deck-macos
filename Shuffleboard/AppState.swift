import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn = false
    /// Every signed-in account, in the order they were added; `activeAccount` is the one in use.
    @Published private(set) var accounts: [Account] = []
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
    /// Which cards the open board shows; reset when switching boards.
    @Published var cardFilter = CardFilter()

    private var deckAPI: DeckAPI?
    /// Where credentials are kept: the Keychain in the app, an in-memory store in tests.
    private let credentialStore: CredentialStore
    /// The URL session for all server requests; tests pass one that talks to a stub server.
    private let session: URLSession
    /// Opens the browser for sign-in.
    private let openURL: @MainActor @Sendable (URL) -> Void
    /// The board `stacks` currently belongs to.
    private var stacksBoardId: Int?
    /// Incremented by every `loadStacks` call; a response is only applied if no newer load has started.
    private var stacksGeneration = 0
    /// ETags of the last board list and of the lists of the board in `stacksBoardId`, for `refreshIfChanged()`.
    private var boardsETag: String?
    private var stacksETag: String?
    private var credentials: Credentials?
    /// What `credentialStore` holds: every account and which one is active.
    private var savedAccounts = SavedAccounts()

    /// The account whose boards are shown.
    var activeAccount: Account? {
        credentials?.account
    }

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

    init(
        credentialStore: CredentialStore = KeychainCredentialStore(),
        session: URLSession = .shared,
        openURL: @escaping @MainActor @Sendable (URL) -> Void = { url in _ = NSWorkspace.shared.open(url) }
    ) {
        self.credentialStore = credentialStore
        self.session = session
        self.openURL = openURL
        self.savedAccounts = credentialStore.load()
        self.accounts = savedAccounts.accounts
        if let creds = savedAccounts.active {
            self.credentials = creds
            self.deckAPI = makeAPI(creds)
            self.isLoggedIn = true
            Task { await loadBoards() }
        } else {
            self.showingLogin = true
        }
    }

    private func makeAPI(_ creds: Credentials) -> DeckAPI {
        DeckAPI(serverURL: creds.serverURL, username: creds.username, appPassword: creds.appPassword, session: session)
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
            let (url, loginName, appPassword) = try await NextcloudAuth.loginWithBrowser(
                serverURL: serverURL,
                session: session,
                openURL: openURL
            )
            try Task.checkCancellation()
            try await finishSignIn(Credentials(serverURL: url, username: loginName, appPassword: appPassword))
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

    /// If `error` means the app password was revoked or has expired, signs the active account out. With
    /// other accounts signed in it switches to the next one and says why in the banner; otherwise it returns
    /// to the login screen with an explanation. Returns `true` if it did, so the caller shows nothing further.
    @discardableResult
    func endSessionIfUnauthorized(_ error: Error) -> Bool {
        guard case .unauthorized? = error as? DeckAPIError else { return false }
        // Requests still in flight from the ended session may fail the same way; handle it once.
        if isLoggedIn, let account = activeAccount {
            logout()
            if isLoggedIn {
                actionError = "Signed out of \(account.id): \(error.localizedDescription)"
            } else {
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    /// Signs the active account out at the user's request: ends its session locally straight away, then
    /// revokes the app password on the server so it stops working and leaves the user's Nextcloud device list.
    /// Revocation failures (offline, server unreachable) are ignored; the local sign-out has already happened.
    func signOut() async {
        let api = deckAPI
        logout()
        try? await api?.revokeAppPassword()
    }

    /// Ends the active account's session locally and forgets its credentials. If another account is signed
    /// in, switches to it; otherwise returns to the login screen. Does not contact the server; see `signOut()`.
    func logout() {
        if let account = activeAccount {
            savedAccounts.remove(account.id)
            try? credentialStore.save(savedAccounts)
        }
        if let next = savedAccounts.active {
            activate(next)
            Task { await loadBoards() }
            return
        }
        resetSession()
        credentials = nil
        deckAPI = nil
        accounts = []
        isLoggedIn = false
        showingLogin = true
    }

    func loadBoards() async {
        guard let api = deckAPI else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchBoards(ifNoneMatch: nil)
            // Switched accounts meanwhile: these are another account's boards.
            guard api === deckAPI, let fetched else { return }
            boards = fetched.value
            boardsETag = fetched.etag
            if selectedBoardId == nil, let first = boards.first {
                // BoardDetailView's `.task(id: selectedBoardId)` loads the newly selected board's lists.
                selectedBoardId = first.id
            } else if let bid = selectedBoardId {
                await loadStacks(boardId: bid)
            }
        } catch {
            guard api === deckAPI, !endSessionIfUnauthorized(error) else { return }
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

        let result: Result<Tagged<[Stack]>, Error>
        do {
            guard let loaded = try await api.fetchStacks(boardId: boardId, ifNoneMatch: nil) else {
                throw DeckAPIError.invalidResponse
            }
            result = .success(loaded)
        } catch {
            result = .failure(error)
        }

        guard generation == stacksGeneration, selectedBoardId == boardId else { return }
        isLoadingStacks = false
        switch result {
        case let .success(loaded):
            stacks = Self.sorted(loaded.value)
            stacksETag = loaded.etag

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
        stacksETag = nil
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

    /// Deletes the stack and its cards. Deck keeps them restorable until the server clears deleted items.
    func deleteStack(boardId: Int, stackId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.deleteStack(boardId: boardId, stackId: stackId)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
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
}

// MARK: - Background refresh

@MainActor
extension AppState {
    /// Picks up changes made elsewhere (the web UI, other devices) without spinners or error messages.
    ///
    /// Uses ETags, so when nothing has changed each request is a 304 with no body. Skipped while boards are
    /// loading, a list reorder is saving or a list is being dragged. A 401 still signs out; other failures are
    /// ignored until the next refresh. A full `loadStacks` that starts meanwhile wins.
    func refreshIfChanged() async {
        guard let api = deckAPI, !isLoading, !isReorderingStacks, !isDraggingStack else { return }
        do {
            let fetched = try await api.fetchBoards(ifNoneMatch: boardsETag)
            guard api === deckAPI else { return }
            if let fetched {
                boards = fetched.value
                boardsETag = fetched.etag
                if let selected = selectedBoardId, !boards.contains(where: { $0.id == selected }) {
                    // The selected board was deleted elsewhere; `.task(id: selectedBoardId)` loads the next one.
                    selectedBoardId = activeBoards.first?.id
                }
            }
        } catch {
            if api === deckAPI {
                endSessionIfUnauthorized(error)
            }
            return
        }

        guard let boardId = selectedBoardId, stacksBoardId == boardId, !isLoadingStacks else { return }
        let generation = stacksGeneration
        do {
            guard let fetched = try await api.fetchStacks(boardId: boardId, ifNoneMatch: stacksETag) else { return }
            guard generation == stacksGeneration, selectedBoardId == boardId,
                  !isReorderingStacks, !isDraggingStack else { return }
            stacks = Self.sorted(fetched.value)
            stacksETag = fetched.etag
            stacksError = nil
        } catch {
            if api === deckAPI {
                endSessionIfUnauthorized(error)
            }
        }
    }

    /// Lists in board order.
    nonisolated static func sorted(_ stacks: [Stack]) -> [Stack] {
        stacks.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }
}

// MARK: - Sharing

@MainActor
extension AppState {
    /// Shares `board` with `sharee`, read-only to start, then refreshes the board's sharing list.
    func share(_ board: Board, with sharee: Sharee) async -> Bool {
        guard let type = sharee.shareType else { return false }
        return await sharingAction(on: board) {
            try await $0.addShare(
                boardId: board.id,
                type: type,
                participant: sharee.participantId,
                permissions: SharePermissions()
            )
        }
    }

    func updateShare(_ entry: ACLEntry, on board: Board, permissions: SharePermissions) async {
        guard let aclId = entry.id else { return }
        _ = await sharingAction(on: board) {
            try await $0.updateShare(boardId: board.id, aclId: aclId, permissions: permissions)
        }
    }

    func removeShare(_ entry: ACLEntry, from board: Board) async {
        guard let aclId = entry.id else { return }
        _ = await sharingAction(on: board) { try await $0.removeShare(boardId: board.id, aclId: aclId) }
    }

    /// Search results for the share field; empty (and the banner) on failure.
    func searchSharees(_ query: String) async -> [Sharee] {
        guard let api = deckAPI else { return [] }
        do {
            return try await api.searchSharees(query)
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                report(error)
            }
            return []
        }
    }

    /// Runs a sharing change, then re-fetches just this board so its sharing list and rights are current.
    private func sharingAction(on board: Board, _ action: (DeckAPI) async throws -> Void) async -> Bool {
        guard let api = deckAPI else { return false }
        do {
            try await action(api)
            let updated = try await api.getBoard(id: board.id)
            if let index = boards.firstIndex(where: { $0.id == board.id }) {
                boards[index] = updated
            }
            return true
        } catch {
            report(error)
            return false
        }
    }
}

// MARK: - Comments

@MainActor
extension AppState {
    /// The signed-in user's id; only a comment's author can edit or delete it.
    var currentUserId: String? {
        credentials?.username
    }

    /// A page of the card's comments, newest first; nil (and the banner) on failure.
    func comments(for card: Card, offset: Int) async -> [CardComment]? {
        await commentAction { try await $0.getComments(cardId: card.id, offset: offset) }
    }

    func addComment(_ message: String, to card: Card) async -> CardComment? {
        await commentAction { try await $0.addComment(cardId: card.id, message: message) }
    }

    func updateComment(_ comment: CardComment, message: String, on card: Card) async -> CardComment? {
        await commentAction { try await $0.updateComment(cardId: card.id, commentId: comment.id, message: message) }
    }

    func deleteComment(_ comment: CardComment, from card: Card) async -> Bool {
        await commentAction { try await $0.deleteComment(cardId: card.id, commentId: comment.id) } != nil
    }

    private func commentAction<Result: Sendable>(_ action: (DeckAPI) async throws -> Result) async -> Result? {
        guard let api = deckAPI else { return nil }
        do {
            return try await action(api)
        } catch {
            report(error)
            return nil
        }
    }
}

// MARK: - Cards

/// What the card sheet edits.
struct CardEdits {
    var title: String
    var description: String
    /// nil removes the due date.
    var dueDate: Date?
    var isDone: Bool
}

@MainActor
extension AppState {
    /// Saves the card sheet's edits to `card`, keeping its other fields as they are.
    /// Returns `true` if the card was saved, `false` otherwise (and sets `errorMessage`).
    func updateCard(boardId: Int, stackId: Int, card: Card, edits: CardEdits) async -> Bool {
        guard let api = deckAPI else { return false }
        var updated = card.withSchedule(dueDate: edits.dueDate, isDone: edits.isDone)
        updated.title = edits.title
        updated.description = edits.description
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

    /// Archives the card and reloads the lists (errors go to the banner).
    func archiveCard(_ card: Card, boardId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.archiveCard(boardId: boardId, stackId: card.stackId, cardId: card.id)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    /// Returns `true` if the card was unarchived; reloads the lists so it reappears.
    @discardableResult
    func unarchiveCard(_ card: Card, boardId: Int) async -> Bool {
        guard let api = deckAPI else { return false }
        do {
            try await api.unarchiveCard(boardId: boardId, stackId: card.stackId, cardId: card.id)
            await loadStacks(boardId: boardId)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// The board's lists holding their archived cards; nil (and the banner) on failure.
    func archivedStacks(boardId: Int) async -> [Stack]? {
        guard let api = deckAPI else { return nil }
        do {
            return try await Self.sorted(api.getArchivedStacks(boardId: boardId))
        } catch {
            report(error)
            return nil
        }
    }

    /// Assigns `user` to the card (errors go to the banner).
    func assignUser(_ user: DeckUser, boardId: Int, card: Card) async {
        guard let api = deckAPI else { return }
        do {
            try await api.assignUser(boardId: boardId, stackId: card.stackId, cardId: card.id, userId: user.uid)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    /// Removes an assignment from the card (errors go to the banner).
    func unassign(_ assignment: CardAssignment, boardId: Int, card: Card) async {
        guard let api = deckAPI else { return }
        do {
            try await api.unassignUser(
                boardId: boardId,
                stackId: card.stackId,
                cardId: card.id,
                userId: assignment.participant.uid,
                type: assignment.type
            )
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
        }
    }

    /// Marks a card done or not done from the board (errors go to the banner).
    func setCardDone(boardId: Int, card: Card, done: Bool) async {
        guard let api = deckAPI, card.isDone != done else { return }
        do {
            let updated = card.withSchedule(dueDate: card.dueDate, isDone: done)
            _ = try await api.updateCard(boardId: boardId, stackId: card.stackId, card: updated)
            await loadStacks(boardId: boardId)
        } catch {
            report(error)
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
}

// MARK: - Attachments

@MainActor
extension AppState {

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

// MARK: - Accounts

@MainActor
extension AppState {
    /// Shows the login screen to sign in to another account; `cancelAddingAccount()` goes back.
    func addAccount() {
        errorMessage = nil
        showingLogin = true
    }

    /// Leaves the login screen opened by `addAccount()` without signing in.
    func cancelAddingAccount() {
        cancelLogin()
        errorMessage = nil
        showingLogin = !isLoggedIn
    }

    /// Saves `creds` as a signed-in account (replacing that account's earlier sign-in, whose app password is
    /// then revoked), makes it active and loads its boards.
    func finishSignIn(_ creds: Credentials) async throws {
        var updated = savedAccounts
        let replaced = updated.add(creds)
        try credentialStore.save(updated)
        savedAccounts = updated
        activate(creds)
        if let replaced, replaced.appPassword != creds.appPassword {
            let oldAPI = makeAPI(replaced)
            Task { try? await oldAPI.revokeAppPassword() }
        }
        await loadBoards()
    }

    /// Shows `account`'s boards instead of the current account's.
    func switchAccount(to account: Account) async {
        guard account.id != activeAccount?.id, let creds = savedAccounts.credentials(for: account.id) else { return }
        savedAccounts.activate(account.id)
        try? credentialStore.save(savedAccounts)
        activate(creds)
        await loadBoards()
    }

    /// Makes `creds` the account in use, starting from an empty board list.
    private func activate(_ creds: Credentials) {
        resetSession()
        credentials = creds
        deckAPI = makeAPI(creds)
        accounts = savedAccounts.accounts
        isLoggedIn = true
        showingLogin = false
    }

    /// Forgets everything shown for the previous account.
    private func resetSession() {
        boards = []
        selectedBoardId = nil
        boardsETag = nil
        clearStacks()
        cardFilter = CardFilter()
        actionError = nil
        errorMessage = nil
    }
}
