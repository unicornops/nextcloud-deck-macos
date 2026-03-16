import SwiftUI
import UniformTypeIdentifiers

private struct DraggedStack {
    let id: Int
    let index: Int

    var providerString: String {
        "stack:\(id):\(index)"
    }

    static func fromProviderString(_ value: String) -> DraggedStack? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "stack",
              let id = Int(parts[1]),
              let index = Int(parts[2]) else {
            return nil
        }
        return DraggedStack(id: id, index: index)
    }
}

struct BoardDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCard: Card?
    @State private var newStackTitle = ""
    @State private var showingNewStack = false
    @State private var stackDragInsertIndex: Int?

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

    private let stackDropTypes = [
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier,
        UTType.text.identifier,
    ]

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
                    HStack(alignment: .top, spacing: 0) {
                        stackInsertionGap(at: 0, boardId: board.id)
                        ForEach(Array(appState.stacks.enumerated()), id: \.element.id) { index, stack in
                            StackColumnView(
                                board: board,
                                stack: stack,
                                onSelectCard: { selectedCard = $0 },
                                onRefresh: { Task { await appState.loadStacks(boardId: board.id) } }
                            )
                            .environmentObject(appState)
                            .onDrag {
                                appState.isDraggingStack = true
                                return NSItemProvider(
                                    object: NSString(
                                        string: DraggedStack(id: stack.id, index: index).providerString
                                    )
                                )
                            }
                            stackInsertionGap(at: index + 1, boardId: board.id)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: stackDropTypes, isTargeted: nil) { _ in
                    // Catch-all: reset stack-dragging state for drops that miss a gap
                    appState.isDraggingStack = false
                    return false
                }
            }
        }
    }

    @ViewBuilder
    private func stackInsertionGap(at index: Int, boardId: Int) -> some View {
        let targeted = stackDragInsertIndex == index
        ZStack(alignment: .center) {
            Color.clear
                .frame(width: targeted ? 80 : 16)
            if targeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2, antialiased: true)
                    )
                    .frame(width: 72)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: targeted)
        .onDrop(
            of: stackDropTypes,
            isTargeted: Binding(
                get: { stackDragInsertIndex == index },
                set: { isTargeted in
                    if isTargeted {
                        stackDragInsertIndex = index
                    } else if stackDragInsertIndex == index {
                        stackDragInsertIndex = nil
                    }
                }
            ),
            perform: { providers in
                handleStackDrop(providers: providers, insertIndex: index, boardId: boardId)
            }
        )
    }

    private func handleStackDrop(providers: [NSItemProvider], insertIndex: Int, boardId: Int) -> Bool {
        guard let provider = providers.first(where: { provider in
            stackDropTypes.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }) else {
            return false
        }

        let typeIdentifier = stackDropTypes.first(where: {
            provider.hasItemConformingToTypeIdentifier($0)
        }) ?? UTType.plainText.identifier

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            let value: String? = if let data = item as? Data {
                String(data: data, encoding: .utf8)
            } else if let str = item as? String {
                str
            } else if let nsStr = item as? NSString {
                nsStr as String
            } else {
                nil
            }

            guard let value, let draggedStack = DraggedStack.fromProviderString(value) else { return }

            Task { @MainActor in
                appState.isDraggingStack = false
                await appState.reorderStacks(
                    boardId: boardId,
                    fromIndex: draggedStack.index,
                    toIndex: insertIndex
                )
            }
        }
        return true
    }
}

#Preview {
    BoardDetailView()
        .environmentObject(AppState())
}
