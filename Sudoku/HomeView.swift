import SwiftUI

struct HomeView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let game = store.game {
                        continueCard(game)
                    }
                    difficultyList
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            newGameButton
        }
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sudoku")
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("A quiet grid.")
                    .font(.title3)
                    .foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            settingsButton
        }
    }

    private func continueCard(_ game: SudokuGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.isWon ? "Finished" : "In progress")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(progressLine(game))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(game.isWon ? "Finished puzzle" : "Puzzle in progress")
            .accessibilityValue("\(game.puzzle.difficulty.title), \(store.spokenTime()), \(game.remainingCells) cells open")

            Button(game.isWon ? "Review the grid" : "Continue") {
                store.openCurrentGame()
            }
            .buttonStyle(InkButtonStyle(prominent: !game.isWon))
            .disabled(store.isGenerating)
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    private func progressLine(_ game: SudokuGame) -> String {
        let open = game.remainingCells == 1 ? "1 cell open" : "\(game.remainingCells) cells open"
        return "\(game.puzzle.difficulty.title) · \(store.formattedTime()) · \(open)"
    }

    private var difficultyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New puzzle")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            ForEach(Difficulty.allCases) { difficulty in
                difficultyRow(difficulty)
            }
        }
    }

    private func difficultyRow(_ difficulty: Difficulty) -> some View {
        let selected = store.lastDifficulty == difficulty
        return Button {
            store.selectDifficulty(difficulty)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(difficulty.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(difficulty.summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Palette.ink : Palette.line, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(PressOpacityStyle())
        .disabled(store.isGenerating)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Sets the difficulty for the next new game")
    }

    private var newGameButton: some View {
        Button {
            store.requestNewGame()
        } label: {
            if store.isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(store.game == nil ? Palette.primaryButtonText : Palette.ink)
                    Text("Composing a \(store.lastDifficulty.title.lowercased()) grid")
                }
            } else {
                Text("New game")
            }
        }
        .buttonStyle(InkButtonStyle(prominent: store.game == nil || store.game?.isWon == true))
        .disabled(store.isGenerating)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Palette.canvas)
        .accessibilityHint("Starts a \(store.lastDifficulty.title) puzzle")
    }

    private var settingsButton: some View {
        Button {
            store.showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Settings")
    }
}
