import SwiftUI

struct BoardListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingNewBoard = false
    @State private var pendingBoardDelete: Int?

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedBoardId },
            set: { new in
                appState.selectedBoardId = new
                if let bid = new, let board = appState.boards.first(where: { $0.id == bid }) {
                    appState.selectBoard(board)
                }
            }
        )) {
            Section("Boards") {
                if appState.isLoading && appState.boards.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if appState.activeBoards.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if let err = appState.errorMessage {
                            Text("Could not load boards")
                                .font(.subheadline.weight(.medium))
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        } else {
                            Text("No boards")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    ForEach(appState.activeBoards) { board in
                        Button {
                            appState.selectBoard(board)
                        } label: {
                            BoardRowView(board: board)
                        }
                        .buttonStyle(.plain)
                        .tag(board.id)
                        .contextMenu {
                            Button("Archive") {
                                Task { await appState.archiveBoard(id: board.id) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                pendingBoardDelete = board.id
                            }
                        }
                    }
                }
            }
            if !appState.archivedBoards.isEmpty {
                Section("Archived") {
                    ForEach(appState.archivedBoards) { board in
                        Button {
                            appState.selectBoard(board)
                        } label: {
                            BoardRowView(board: board)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .tag(board.id)
                        .contextMenu {
                            Button("Unarchive") {
                                Task { await appState.unarchiveBoard(id: board.id) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                pendingBoardDelete = board.id
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Boards")
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh boards")
                .accessibilityLabel("Refresh boards")
                .disabled(appState.isLoading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    showingNewBoard = true
                } label: {
                    Label("New Board", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("New board")
                .accessibilityLabel("New board")
            }
            .background(.background)
        }
        .sheet(isPresented: $showingNewBoard) {
            NewBoardSheet {
                showingNewBoard = false
            }
        }
        .confirmationDialog("Delete board?", isPresented: Binding(
            get: { pendingBoardDelete != nil },
            set: { if !$0 { pendingBoardDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let boardId = pendingBoardDelete else { return }
                pendingBoardDelete = nil
                Task { await appState.deleteBoard(id: boardId) }
            }
            Button("Cancel", role: .cancel) {
                pendingBoardDelete = nil
            }
        } message: {
            if let boardId = pendingBoardDelete,
               let board = appState.boards.first(where: { $0.id == boardId }) {
                Text(
                    "\u{201c}\(board.title)\u{201d} and all its lists and cards will be permanently deleted. This cannot be undone."
                )
            }
        }
    }
}

private struct BoardRowView: View {
    let board: Board

    var body: some View {
        SwiftUI.Label {
            Text(board.title)
                .lineLimit(1)
        } icon: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(boardColor)
                .frame(width: 12, height: 12)
        }
    }

    private var boardColor: Color {
        guard let hex = board.color, !hex.isEmpty else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }
}

#Preview {
    BoardListView()
        .environmentObject(AppState())
}
