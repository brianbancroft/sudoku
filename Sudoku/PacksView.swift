import SwiftUI

struct PacksView: View {
    @Environment(GameStore.self) private var store
    @Environment(PackStore.self) private var packs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Optional sets from the App Store. The generator on the home screen stays free.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if packs.serverUnreachable {
                    Text(packs.notice ?? "The puzzle server is unreachable. Purchased packs already on this phone still open.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let notice = packs.notice {
                    Text(notice)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(packs.listings) { listing in
                    packCard(listing)
                }
                Button {
                    Task { await packs.restore() }
                } label: {
                    if packs.isBusy {
                        ProgressView()
                    } else {
                        Text("Restore purchases")
                    }
                }
                .buttonStyle(InkButtonStyle(prominent: false))
                .disabled(packs.isBusy)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle("Puzzle packs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Palette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func packCard(_ listing: PackListing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.name)
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(listing.summary)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(listing.difficultyMix) · \(listing.puzzleCount) puzzles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            .accessibilityElement(children: .combine)
            action(for: listing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func action(for listing: PackListing) -> some View {
        if packs.isDownloaded(listing.id) {
            VStack(alignment: .leading, spacing: 10) {
                Text("On this phone · \(packs.completedCount(packID: listing.id)) of \(listing.puzzleCount) finished")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                NavigationLink(value: AppRoute.pack(listing.id)) {
                    Text("Choose a puzzle")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Palette.primaryButtonText)
                        .background(Palette.primaryButton, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityHint("Opens the puzzles in \(listing.name)")
            }
        } else if packs.ownedProductIDs.contains(listing.productID) {
            Button {
                Task { await packs.download(listing) }
            } label: {
                Text(packs.isBusy ? "Working" : "Download")
            }
            .buttonStyle(InkButtonStyle(prominent: true))
            .disabled(packs.isBusy)
            .accessibilityLabel("Download \(listing.name)")
            .accessibilityHint("Uses the App Store purchase already on this phone")
        } else if let price = packs.priceLabel(for: listing.productID) {
            Button {
                Task { await packs.buy(listing) }
            } label: {
                Text("Buy \(price)")
            }
            .buttonStyle(InkButtonStyle(prominent: true))
            .disabled(packs.isBusy)
            .accessibilityLabel("Buy \(listing.name)")
            .accessibilityValue(price)
        } else {
            Text("Price unavailable")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Palette.muted)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
                .accessibilityLabel("Price unavailable for \(listing.name)")
        }
    }
}

struct PackDetailView: View {
    @Environment(GameStore.self) private var store
    @Environment(PackStore.self) private var packs
    var packID: String

    private var listing: PackListing? {
        packs.listings.first { $0.id == packID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let listing {
                    Text(listing.summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let pack = packs.pack(id: packID) {
                    ForEach(pack.puzzles) { puzzle in
                        puzzleRow(puzzle, packName: listing?.name ?? packID)
                    }
                } else {
                    Text("This pack isn't on the phone yet.")
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle(listing?.name ?? "Pack")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Palette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog(
            "Play this puzzle?",
            isPresented: Bindable(store).confirmPackPlay,
            titleVisibility: .visible
        ) {
            Button("Play") { store.beginPendingPack() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The puzzle in progress will be replaced.")
        }
    }

    private func puzzleRow(_ puzzle: DownloadedPuzzle, packName: String) -> some View {
        let done = packs.isComplete(packID: packID, puzzleID: puzzle.id)
        return Button {
            store.requestPackPuzzle(puzzle, packID: packID, packName: packName)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(puzzle.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(puzzle.difficulty.title)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                if done {
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
                    .strokeBorder(Palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(PressOpacityStyle())
        .accessibilityLabel("\(puzzle.title), \(puzzle.difficulty.title)")
        .accessibilityValue(done ? "Finished" : "Not finished")
        .accessibilityHint("Opens this puzzle")
    }
}
