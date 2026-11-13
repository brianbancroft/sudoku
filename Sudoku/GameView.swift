import SwiftUI
import UIKit

struct GameView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    playSurface(in: proxy.size, scrollable: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(store.showsPause || store.hasWon)
                }
            } else {
                playSurface(in: proxy.size, scrollable: false)
                    .accessibilityHidden(store.showsPause || store.hasWon)
            }
        }
        .background { BlushCanvas() }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbarBackground(Palette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay { overlays }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = store.game?.isWon != true && !store.userPaused
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: store.userPaused) { _, paused in
            UIApplication.shared.isIdleTimerDisabled = !paused && store.game?.isWon != true
        }
        .onChange(of: store.hasWon) { _, won in
            if won { UIApplication.shared.isIdleTimerDisabled = false }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                store.checkpoint()
            }
        }
        .sensoryFeedback(.selection, trigger: store.moveCount) { _, count in
            count > 0
        }
        .sensoryFeedback(.success, trigger: store.hasWon) { _, won in
            won
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.showsPause)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.hasWon)
    }

    private func playSurface(in size: CGSize, scrollable: Bool) -> some View {
        let metrics = Metrics(size: size, showsBanner: store.banner != nil, scrollable: scrollable)
        return VStack(spacing: 10) {
            status
                .frame(minHeight: 44, alignment: .leading)
            if !scrollable { Spacer(minLength: 4) }
            if let game = store.game {
                BoardView(model: boardModel(game), onSelect: { store.select($0) })
                    .frame(width: metrics.board, height: metrics.board)
                    .accessibilityHidden(store.showsPause || store.hasWon)
            } else {
                ProgressView("Composing the grid")
                    .frame(width: metrics.board, height: metrics.board)
            }
            if !scrollable { Spacer(minLength: 4) }
            if let banner = store.banner {
                HintBanner(banner: banner)
                    .frame(maxWidth: metrics.board)
            }
            ToolRow()
                .frame(maxWidth: metrics.board)
            NumberPadView()
                .frame(maxWidth: metrics.board)
                .frame(height: metrics.padHeight)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: scrollable ? nil : .infinity)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(statusTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        guard let game = store.game else { return "New puzzle" }
        let open = game.remainingCells == 1 ? "1 cell open" : "\(game.remainingCells) cells open"
        if let pack = store.packContext {
            return "\(pack.packName) · \(pack.puzzleTitle) · \(open)"
        }
        return "\(game.puzzle.difficulty.title) · \(open)"
    }

    private var statusDetail: String {
        guard let game = store.game else { return "Choose a cell" }
        guard let selection = store.selection else { return "Choose a cell, then a number." }
        let row = Grid.row(of: selection) + 1
        let column = Grid.column(of: selection) + 1
        if game.isGiven(selection) {
            return "Row \(row), column \(column) · Given"
        }
        if store.pencilMode {
            return "Pencil marks · Row \(row), column \(column)"
        }
        return "Row \(row), column \(column)"
    }

    private func boardModel(_ game: SudokuGame) -> BoardModel {
        BoardModel(
            values: game.values,
            givens: game.puzzle.givens,
            notes: game.notes,
            selection: store.selection,
            errors: store.markedErrors,
            hintCells: store.hintCells,
            hintHouse: store.hintHouseCells,
            related: store.relatedCells,
            sameNumber: store.sameNumberCells,
            emphasisDigit: store.emphasisDigit
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                store.leaveGame()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
        }
        ToolbarItem(placement: .principal) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(store.formattedTime(at: context.date))
                    .font(.system(.headline, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(store.spokenTime(at: context.date))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                store.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")

            Button {
                store.togglePause()
            } label: {
                Image(systemName: store.userPaused ? "play.fill" : "pause.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(store.userPaused ? "Resume" : "Pause")
            .disabled(store.hasWon)
        }
    }

    @ViewBuilder
    private var overlays: some View {
        if store.hasWon, let game = store.game {
            WinOverlay(game: game)
        } else if store.showsPause {
            PauseOverlay()
        }
    }

}

private struct Metrics {
    var board: CGFloat
    var padHeight: CGFloat

    init(size: CGSize, showsBanner: Bool, scrollable: Bool) {
        let width = max(220, size.width - 32)
        if scrollable {
            board = width
            padHeight = 168
            return
        }
        var pad: CGFloat = 168
        let banner: CGFloat = showsBanner ? 118 : 0
        func chrome(pad: CGFloat) -> CGFloat {
            46 + 60 + banner + 24 + pad
        }
        if size.height - chrome(pad: pad) < min(width, 280) {
            pad = 148
        }
        let available = size.height - chrome(pad: pad)
        board = min(width, max(200, available))
        padHeight = pad
    }
}

struct HintBanner: View {
    @Environment(GameStore.self) private var store
    var banner: PlayBanner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Button("Not now") { store.dismissBanner() }
                    .buttonStyle(BannerButtonStyle(prominent: false))
                if case .hint = banner {
                    Button("Reveal digit") { store.confirmReveal() }
                        .buttonStyle(BannerButtonStyle(prominent: true))
                } else {
                    Button("Settings") { store.showSettings = true }
                        .buttonStyle(BannerButtonStyle(prominent: true))
                }
            }
        }
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        switch banner {
        case .hint(let hint): hint.message
        case .note(let text): text
        }
    }
}

struct PauseOverlay: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.28)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Paused")
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(store.formattedTime())
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(store.spokenTime())
                Button("Resume") { store.togglePause() }
                    .buttonStyle(InkButtonStyle(prominent: true))
                Button("Home") { store.leaveGame() }
                    .buttonStyle(InkButtonStyle(prominent: false))
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }
}

struct WinOverlay: View {
    @Environment(GameStore.self) private var store
    var game: SudokuGame

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.28)
                .ignoresSafeArea()
            PetalBloom()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Text("Complete")
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(game.puzzle.difficulty.title)
                    .font(.headline)
                    .foregroundStyle(Palette.muted)
                Text(store.formattedTime())
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .accessibilityLabel("Finished in \(store.spokenTime())")
                Text(hintLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Button {
                    store.startNewGame(matching: game.puzzle.difficulty)
                } label: {
                    if store.isGenerating {
                        HStack(spacing: 10) {
                            ProgressView().tint(Palette.primaryButtonText)
                            Text("Composing")
                        }
                    } else {
                        Text("New \(game.puzzle.difficulty.title.lowercased()) puzzle")
                    }
                }
                .buttonStyle(InkButtonStyle(prominent: true))
                .disabled(store.isGenerating)
                Button("Home") { store.leaveGame() }
                    .buttonStyle(InkButtonStyle(prominent: false))
                    .disabled(store.isGenerating)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var hintLine: String {
        switch game.hintsUsed {
        case 0: "No hints used."
        case 1: "1 hint used."
        default: "\(game.hintsUsed) hints used."
        }
    }
}

struct PetalBloom: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomed = false

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            ZStack {
                ForEach(0..<10, id: \.self) { index in
                    Capsule()
                        .fill(index.isMultiple(of: 2) ? Palette.accent : Palette.hint)
                        .frame(width: 9, height: 18)
                        .offset(y: bloomed ? -120 - CGFloat(index % 3) * 22 : -10)
                        .rotationEffect(.degrees(Double(index) * 36))
                        .opacity(bloomed ? 0 : 0.85)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.15)) {
                    bloomed = true
                }
            }
        }
    }
}

#Preview("Easy game") {
    let puzzle = SudokuGenerator(seed: 1).generate(difficulty: .easy)
    NavigationStack {
        GameView()
    }
    .environment(GameStore(preview: puzzle))
}
