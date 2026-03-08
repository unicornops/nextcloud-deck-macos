import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var boards: [Board] = []
    @Published var selectedBoardId: Int?
    @Published var stacks: [Stack] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingStacks: Bool = false
    @Published var errorMessage: String?
    @Published var stacksError: String?
    @Published var showingLogin: Bool = false

    private var deckAPI: DeckAPI?
    private var credentials: (serverURL: URL, username: String, appPassword: String)?

    var selectedBoard: Board? {
        guard let id = selectedBoardId else { return nil }
        return boards.first { $0.id == id }
    }

    init() {
        if let creds = KeychainStorage.load() {
            credentials = creds
            deckAPI = DeckAPI(serverURL: creds.serverURL, username: creds.username, appPassword: creds.appPassword)
            isLoggedIn = true
            Task { await loadBoards() }
        } else {
            showingLogin = true
        }
    }

    func login(serverURL: URL, username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let appPassword = try await NextcloudAuth.getAppPassword(serverURL: serverURL, username: username, password: password)
            let storedURL = try KeychainStorage.save(serverURL: serverURL, username: username, appPassword: appPassword)
            credentials = (storedURL, username, appPassword)
            deckAPI = DeckAPI(serverURL: storedURL, username: username, appPassword: appPassword)
            isLoggedIn = true
            showingLogin = false
            await loadBoards()
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("two-factor") || msg.lowercased().contains("2fa") || msg.lowercased().contains("second factor") {
                errorMessage = "This account uses two-factor authentication. Use “Sign in with browser” above."
            } else {
                errorMessage = msg
            }
        }
    }

    /// Sign in via browser (Login Flow v2). Supports 2FA — user completes login and 2FA in the browser.
    func loginWithBrowser(serverURL: URL) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (url, loginName, appPassword) = try await NextcloudAuth.loginWithBrowser(serverURL: serverURL)
            let storedURL = try KeychainStorage.save(serverURL: url, username: loginName, appPassword: appPassword)
            credentials = (storedURL, loginName, appPassword)
            deckAPI = DeckAPI(serverURL: storedURL, username: loginName, appPassword: appPassword)
            isLoggedIn = true
            showingLogin = false
            await loadBoards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        try? KeychainStorage.delete()
        credentials = nil
        deckAPI = nil
        isLoggedIn = false
        boards = []
        selectedBoardId = nil
        stacks = []
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
                selectedBoardId = first.id
            }
            if let bid = selectedBoardId {
                await loadStacks(boardId: bid)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Call when main interface appears so boards are loaded (e.g. after launch with Keychain or after login).
    func loadBoardsIfNeeded() async {
        guard isLoggedIn else { return }
        await loadBoards()
    }

    func loadStacks(boardId: Int) async {
        guard let api = deckAPI else { return }
        stacks = []
        stacksError = nil
        isLoadingStacks = true
        defer { isLoadingStacks = false }
        do {
            stacks = try await api.getStacks(boardId: boardId)
            stacks.sort { ($0.order, $0.id) < ($1.order, $1.id) }
        } catch {
            stacksError = error.localizedDescription
        }
    }

    func selectBoard(_ board: Board) {
        selectedBoardId = board.id
        Task { await loadStacks(boardId: board.id) }
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Permanently deletes the stack and its cards from the board.
    func deleteStack(boardId: Int, stackId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.deleteStack(boardId: boardId, stackId: stackId)
            await loadStacks(boardId: boardId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCard(boardId: Int, stackId: Int, card: Card, title: String?, description: String?) async {
        guard let api = deckAPI else { return }
        do {
            _ = try await api.updateCard(boardId: boardId, stackId: stackId, cardId: card.id, title: title ?? card.title, description: description ?? card.description, order: nil, duedate: nil)
            await loadStacks(boardId: boardId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCard(boardId: Int, stackId: Int, cardId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.deleteCard(boardId: boardId, stackId: stackId, cardId: cardId)
            await loadStacks(boardId: boardId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderCard(boardId: Int, fromStackId: Int, cardId: Int, toStackId: Int, order: Int) async {
        guard let api = deckAPI else { return }
        do {
            _ = try await api.reorderCard(boardId: boardId, stackId: fromStackId, cardId: cardId, order: order, newStackId: toStackId)
            await loadStacks(boardId: boardId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCard(boardId: Int, cardId: Int, fromStackId: Int, toStackId: Int, order: Int) async {
        guard fromStackId != toStackId else { return }
        guard let api = deckAPI else { return }

        if let card = stacks.first(where: { $0.id == fromStackId })?.cards?.first(where: { $0.id == cardId }) {
            do {
                _ = try await api.moveCardToStack(card: card, toStackId: toStackId, order: order)
                await loadStacks(boardId: boardId)
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        await reorderCard(boardId: boardId, fromStackId: fromStackId, cardId: cardId, toStackId: toStackId, order: order)
    }

    func assignLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.assignLabel(boardId: boardId, stackId: stackId, cardId: cardId, labelId: labelId)
            await loadStacks(boardId: boardId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async {
        guard let api = deckAPI else { return }
        do {
            try await api.removeLabel(boardId: boardId, stackId: stackId, cardId: cardId, labelId: labelId)
            await loadStacks(boardId: boardId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates a new label on the board and refreshes board/stacks. Returns the new label id if successful.
    func createLabel(boardId: Int, title: String, color: String) async -> Int? {
        guard let api = deckAPI else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let label = try await api.createLabel(boardId: boardId, title: trimmed, color: color)
            await loadBoards()
            if let bid = selectedBoardId, bid == boardId {
                await loadStacks(boardId: boardId)
            }
            return label.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
