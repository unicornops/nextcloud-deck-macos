import SwiftUI

struct BoardListView: View {
    @EnvironmentObject private var appState: AppState
    
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
                } else if appState.boards.isEmpty {
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
                    ForEach(appState.boards) { board in
                        Button {
                            appState.selectBoard(board)
                        } label: {
                            BoardRowView(board: board)
                        }
                        .buttonStyle(.plain)
                        .tag(board.id)
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
                .disabled(appState.isLoading)
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
