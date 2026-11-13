import SwiftUI

struct BoardModel {
    var values: [Int]
    var givens: [Int]
    var notes: [UInt16]
    var selection: Int?
    var errors: Set<Int>
    var hintCells: Set<Int>
    var hintHouse: Set<Int>
    var related: Set<Int>
    var sameNumber: Set<Int>
    var emphasisDigit: Int?
}

struct BoardView: View {
    var model: BoardModel
    var onSelect: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 9
            ZStack {
                Palette.board
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<9, id: \.self) { row in
                        GridRow {
                            ForEach(0..<9, id: \.self) { column in
                                cellButton(index: row * 9 + column, cell: cell)
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
                gridLines(side: side)
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.lineStrong, lineWidth: 2)
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sudoku board")
    }

    private func cellButton(index: Int, cell: CGFloat) -> some View {
        Button {
            onSelect(index)
        } label: {
            ZStack {
                Rectangle().fill(fill(for: index))
                cellContent(index: index, cell: cell)
                if model.errors.contains(index) {
                    Capsule()
                        .fill(Palette.conflictInk)
                        .frame(width: cell * 0.36, height: max(2, cell * 0.055))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, cell * 0.09)
                        .accessibilityHidden(true)
                }
                if model.selection == index {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Palette.lineStrong, lineWidth: 2)
                        .padding(max(2, cell * 0.07))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressOpacityStyle())
        .accessibilityLabel(label(for: index))
        .accessibilityHint("Selects this cell")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(model.selection == index ? .isSelected : [])
    }

    @ViewBuilder
    private func cellContent(index: Int, cell: CGFloat) -> some View {
        let value = model.values[index]
        if value != 0 {
            Text("\(value)")
                .font(.system(size: digitSize(cell), weight: model.givens[index] != 0 ? .bold : .regular, design: .serif))
                .foregroundStyle(numberColor(index: index))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        } else {
            noteGrid(index: index, cell: cell)
        }
    }

    private func noteGrid(index: Int, cell: CGFloat) -> some View {
        let mask = model.notes[index]
        let noteSize = max(8, cell * 0.2 * min(typeScale, 1.12))
        return VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(1..<4, id: \.self) { column in
                        let digit = row * 3 + column
                        let shown = mask & Grid.bit(digit) != 0
                        Text(shown ? "\(digit)" : " ")
                            .font(.system(size: noteSize, weight: .medium, design: .rounded))
                            .foregroundStyle(noteColor(digit: digit, shown: shown))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(cell * 0.06)
        .accessibilityHidden(true)
    }

    private func gridLines(side: CGFloat) -> some View {
        Canvas { context, _ in
            let step = side / 9
            for index in 1..<9 {
                let thick = index % 3 == 0
                let width: CGFloat = thick ? 1.6 : 0.6
                let color = thick ? Palette.lineStrong : Palette.line
                var horizontal = Path()
                let y = (step * CGFloat(index)).rounded()
                horizontal.move(to: CGPoint(x: 0, y: y))
                horizontal.addLine(to: CGPoint(x: side, y: y))
                context.stroke(horizontal, with: .color(color), lineWidth: width)
                var vertical = Path()
                let x = (step * CGFloat(index)).rounded()
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: side))
                context.stroke(vertical, with: .color(color), lineWidth: width)
            }
        }
        .frame(width: side, height: side)
    }

    private func fill(for index: Int) -> Color {
        if model.errors.contains(index) { return Palette.conflictFill }
        if model.hintCells.contains(index) { return Palette.hint }
        if model.selection == index { return Palette.selection }
        if model.sameNumber.contains(index) { return Palette.sameNumber }
        if model.related.contains(index) || model.hintHouse.contains(index) { return Palette.related }
        return .clear
    }

    private func numberColor(index: Int) -> Color {
        if model.errors.contains(index) { return Palette.conflictInk }
        if model.givens[index] != 0 { return Palette.ink }
        return Palette.entry
    }

    private func noteColor(digit: Int, shown: Bool) -> Color {
        guard shown else { return .clear }
        if model.emphasisDigit == digit { return Palette.accent }
        return Palette.note
    }

    private func digitSize(_ cell: CGFloat) -> CGFloat {
        max(15, cell * 0.52 * typeScale)
    }

    private var typeScale: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: 0.86
        case .small: 0.93
        case .medium: 0.97
        case .large: 1
        case .xLarge: 1.06
        case .xxLarge: 1.12
        case .xxxLarge: 1.18
        default: 1.22
        }
    }

    private func label(for index: Int) -> String {
        let row = Grid.row(of: index) + 1
        let column = Grid.column(of: index) + 1
        var parts = ["Row \(row)", "Column \(column)"]
        let value = model.values[index]
        if model.givens[index] != 0 {
            parts.append("given \(value)")
        } else if value != 0 {
            parts.append("entered \(value)")
        } else {
            let notes = Grid.digits(in: model.notes[index])
            if notes.isEmpty {
                parts.append("empty")
            } else {
                let list = notes.map(String.init).joined(separator: ", ")
                parts.append("notes \(list)")
            }
        }
        if model.errors.contains(index) {
            parts.append("marked")
        }
        if model.hintCells.contains(index) {
            parts.append("hinted")
        }
        return parts.joined(separator: ", ")
    }
}
