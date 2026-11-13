import SwiftUI

struct NumberPadView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(1..<4, id: \.self) { column in
                        let digit = row * 3 + column
                        digitButton(digit)
                    }
                }
            }
        }
        .opacity(store.inputEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number pad")
    }

    private func digitButton(_ digit: Int) -> some View {
        let remaining = max(0, store.game?.remainingCounts[digit - 1] ?? 0)
        let emphasized = store.emphasisDigit == digit
        return Button {
            store.input(digit: digit)
        } label: {
            VStack(spacing: 0) {
                Text("\(digit)")
                    .font(.system(.title2, design: .serif).weight(.medium))
                    .foregroundStyle(remaining == 0 ? Palette.muted : Palette.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("\(remaining)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .fill(emphasized ? Palette.hint : Palette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .strokeBorder(emphasized ? Palette.ink : Palette.line, lineWidth: emphasized ? 2 : 1)
            }
        }
        .buttonStyle(PressOpacityStyle())
        .keyboardShortcut(KeyEquivalent(Character("\(digit)")), modifiers: [])
        .accessibilityLabel(store.pencilMode ? "Pencil \(digit)" : "Digit \(digit)")
        .accessibilityValue(remaining == 0 ? "All placed" : "\(remaining) remaining")
        .accessibilityHint(hint(emphasized: emphasized))
    }

    private func hint(emphasized: Bool) -> String {
        if emphasized { return "Suggested" }
        if !store.inputEnabled { return "Select an empty cell first" }
        if store.pencilMode { return "Toggles this pencil mark" }
        return "Enters this digit. Enter it again to clear the cell."
    }
}

struct ToolRow: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            tool(
                title: "Notes",
                systemImage: "pencil",
                isOn: store.pencilMode,
                enabled: store.game?.isWon != true,
                shortcut: (key: "n", modifiers: .command)
            ) {
                store.togglePencil()
            }
            .accessibilityValue(store.pencilMode ? "On" : "Off")
            .accessibilityHint("Toggles pencil marks for empty cells")

            tool(
                title: "Erase",
                systemImage: "delete.left",
                enabled: store.inputEnabled,
                shortcut: (key: .delete, modifiers: [])
            ) {
                store.erase()
            }

            tool(
                title: "Undo",
                systemImage: "arrow.uturn.backward",
                enabled: store.game?.canUndo == true && store.game?.isWon != true,
                shortcut: (key: "z", modifiers: .command)
            ) {
                store.undo()
            }

            tool(
                title: "Redo",
                systemImage: "arrow.uturn.forward",
                enabled: store.game?.canRedo == true,
                shortcut: (key: "z", modifiers: [.command, .shift])
            ) {
                store.redo()
            }

            tool(
                title: "Hint",
                systemImage: "lightbulb",
                enabled: store.game?.isWon != true,
                shortcut: (key: "h", modifiers: .command)
            ) {
                store.requestHint()
            }
            .accessibilityHint(store.settings.hintsEnabled ? "Describes a useful next step" : "Hints are off in Settings")
        }
    }

    private func tool(
        title: String,
        systemImage: String,
        isOn: Bool = false,
        enabled: Bool,
        shortcut: (key: KeyEquivalent, modifiers: EventModifiers)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOn ? Palette.primaryButtonText : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .fill(isOn ? Palette.ink : Palette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(PressOpacityStyle())
        .disabled(!enabled)
        .modifier(ShortcutModifier(shortcut: shortcut))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ShortcutModifier: ViewModifier {
    var shortcut: (key: KeyEquivalent, modifiers: EventModifiers)?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }
}
