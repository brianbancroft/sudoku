import SwiftUI

@main
struct SudokuApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

struct RootView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            HomeView()
                .navigationDestination(isPresented: $store.showGame) {
                    GameView()
                }
        }
        .tint(Palette.accent)
        .sheet(isPresented: $store.showSettings) {
            NavigationStack {
                SettingsView()
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Start a new puzzle?",
            isPresented: $store.confirmNewGame,
            titleVisibility: .visible
        ) {
            Button("Start \(store.lastDifficulty.title)") {
                store.startNewGame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The puzzle in progress will be replaced.")
        }
        .onChange(of: scenePhase) { _, phase in
            store.handleScenePhase(phase)
        }
    }
}
