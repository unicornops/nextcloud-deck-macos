import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Group {
            if appState.showingLogin {
                LoginView()
            } else {
                mainInterface
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.showingLogin)
    }
    
    private var mainInterface: some View {
        NavigationSplitView {
            BoardListView()
        } detail: {
            BoardDetailView()
        }
        .task {
            await appState.loadBoardsIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await appState.refresh() }
                    }
                    Divider()
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                        appState.logout()
                    }
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
