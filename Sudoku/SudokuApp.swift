import SwiftUI

enum AppRoute: Hashable {
    case game
    case packs
    case pack(String)
}

@main
struct SudokuApp: App {
    @State private var store = GameStore()
    @State private var packs = PackStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(packs)
                .task {
                    packs.serverURL = store.settings.packServerURL
                    await packs.bootstrap()
                }
        }
    }
}

struct RootView: View {
    @Environment(GameStore.self) private var store
    @Environment(PackStore.self) private var packs
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .game:
                        GameView()
                    case .packs:
                        PacksView()
                    case .pack(let id):
                        PackDetailView(packID: id)
                    }
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
        .onChange(of: store.path) { old, new in
            if old.contains(.game), !new.contains(.game) {
                store.noteGameClosed()
            }
        }
        .onChange(of: store.hasWon) { _, won in
            if won, let context = store.packContext {
                packs.markCompleted(packID: context.packID, puzzleID: context.puzzleID)
            }
        }
        .onChange(of: store.settings.packServerURL) { _, url in
            packs.serverURL = url
        }
    }
}
