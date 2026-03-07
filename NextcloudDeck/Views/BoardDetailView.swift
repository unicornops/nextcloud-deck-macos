import SwiftUI

struct BoardDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCard: Card?
    @State private var newStackTitle = ""
    @State private var showingNewStack = false
    
    var body: some View {
        Group {
            if let board = appState.selectedBoard {
                VStack(spacing: 0) {
                    boardHeader(board)
                    Divider()
                    scrollableStacks(board)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ContentUnavailableView(
                    "Select a Board",
                    systemImage: "rectangle.stack",
                    description: Text("Choose a board from the sidebar to get started.")
                )
            }
        }
        .navigationTitle(appState.selectedBoard?.title ?? "Deck")
        .sheet(item: $selectedCard) { card in
            if let board = appState.selectedBoard {
                CardDetailSheet(card: card, boardId: board.id, onDismiss: {
                    selectedCard = nil
                    Task { await appState.loadStacks(boardId: board.id) }
                })
                .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showingNewStack) {
            if let board = appState.selectedBoard {
                NewStackSheet(boardId: board.id, onDismiss: {
                    showingNewStack = false
                    newStackTitle = ""
                    Task { await appState.loadStacks(boardId: board.id) }
                })
                .environmentObject(appState)
            }
        }
        .onChange(of: appState.selectedBoardId) { _, newId in
            if let bid = newId {
                Task { await appState.loadStacks(boardId: bid) }
            } else {
                appState.stacks = []
            }
        }
        .task(id: appState.selectedBoardId) {
            guard let bid = appState.selectedBoardId else { return }
            await appState.loadStacks(boardId: bid)
        }
    }
    
    private func boardHeader(_ board: Board) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(boardColor(board))
                .frame(width: 16, height: 16)
            Text(board.title)
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                Task { await appState.loadStacks(boardId: board.id) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh lists")
            .accessibilityLabel("Refresh lists")
            .disabled(appState.isLoadingStacks)
            Button {
                showingNewStack = true
            } label: {
                SwiftUI.Label("Add list", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("Add a new list to this board")
            .accessibilityLabel("Add list")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private func boardColor(_ board: Board) -> Color {
        guard let hex = board.color, !hex.isEmpty else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }
    
    private func scrollableStacks(_ board: Board) -> some View {
        Group {
            if appState.isLoadingStacks && appState.stacks.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading lists…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.stacksError, appState.stacks.isEmpty {
                ContentUnavailableView {
                    Label("Could not load lists", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Try again") {
                        Task { await appState.loadStacks(boardId: board.id) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(appState.stacks) { stack in
                            StackColumnView(
                                board: board,
                                stack: stack,
                                onSelectCard: { selectedCard = $0 },
                                onRefresh: { Task { await appState.loadStacks(boardId: board.id) } }
                            )
                            .environmentObject(appState)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    BoardDetailView()
        .environmentObject(AppState())
}
