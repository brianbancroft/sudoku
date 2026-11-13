import SwiftUI

struct SettingsView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Mistake checking", selection: $store.settings.mistakes) {
                    ForEach(MistakeChecking.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Mistake checking")
            } footer: {
                Text(store.settings.mistakes.explanation)
            }

            Section {
                Toggle("Hints", isOn: $store.settings.hintsEnabled)
                Toggle("Highlight the same digit", isOn: $store.settings.highlightSameNumber)
                Toggle("Highlight the row, column, and box", isOn: $store.settings.highlightHouses)
            } footer: {
                Text("A hint describes a cell or a pattern. It fills a digit only if you tap Reveal.")
            }

            Section {
                Text("Puzzles are made on this phone and stay on this phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: store.settings) { _, _ in
            store.save()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
    }
}
