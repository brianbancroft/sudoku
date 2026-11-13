import Foundation

public struct Hint: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case nakedSingle
        case hiddenSingle
        case nakedPair
        case hiddenPair
        case pointing
        case boxLine
        case xWing
        case fewestCandidates
        case incorrectEntry
    }

    public var kind: Kind
    /// Describes the pattern. It does not name the digit that would be placed.
    public var message: String
    public var highlightedCells: [Int]
    public var house: House?
    /// Digit to emphasize on the pad. Nil when showing it would skip the pattern.
    public var emphasisDigit: Int?
    /// Filled only if the player explicitly asks to reveal a digit.
    public var reveal: CellPlacement?

    public init(
        kind: Kind,
        message: String,
        highlightedCells: [Int],
        house: House?,
        emphasisDigit: Int?,
        reveal: CellPlacement?
    ) {
        self.kind = kind
        self.message = message
        self.highlightedCells = highlightedCells
        self.house = house
        self.emphasisDigit = emphasisDigit
        self.reveal = reveal
    }
}

public enum HintEngine {
    public static func hint(for game: SudokuGame) -> Hint? {
        if game.isWon { return nil }

        if let index = game.values.indices.first(where: { candidate in
            let value = game.values[candidate]
            return value != 0 && !game.isGiven(candidate) && value != game.puzzle.solution[candidate]
        }) {
            return Hint(
                kind: .incorrectEntry,
                message: "This digit doesn't belong here. Erase it, or reveal the one that does.",
                highlightedCells: [index],
                house: nil,
                emphasisDigit: nil,
                reveal: CellPlacement(index: index, digit: game.puzzle.solution[index])
            )
        }

        let solver = HumanSolver(values: game.values)
        if let step = solver.nextStep() {
            return hint(from: step, solution: game.puzzle.solution, solver: solver)
        }

        guard let fewest = solver.fewestCandidateCell() else { return nil }
        return Hint(
            kind: .fewestCandidates,
            message: "This cell has the fewest digits that still fit. Compare its row, column, and box.",
            highlightedCells: [fewest.index],
            house: nil,
            emphasisDigit: nil,
            reveal: CellPlacement(index: fewest.index, digit: game.puzzle.solution[fewest.index])
        )
    }

    private static func hint(from step: LogicStep, solution: [Int], solver: HumanSolver) -> Hint {
        let kind: Hint.Kind
        let message: String
        switch step.technique {
        case .nakedSingle:
            kind = .nakedSingle
            message = "Only one digit can sit in this cell."
        case .hiddenSingle:
            kind = .hiddenSingle
            message = hiddenMessage(step.house)
        case .nakedPair:
            kind = .nakedPair
            message = "These two cells share a pair. Those digits are finished for the rest of this house."
        case .hiddenPair:
            kind = .hiddenPair
            message = "Two digits in this house can only live in these cells. Other marks there can go."
        case .pointing:
            kind = .pointing
            message = pointingMessage(step.house)
        case .boxLine:
            kind = .boxLine
            message = boxLineMessage(step.house)
        case .xWing:
            kind = .xWing
            message = "These cells lock a digit into two lines. It can't appear elsewhere on those lines."
        case .none:
            kind = .fewestCandidates
            message = "Look again at the highlighted cell."
        }

        let emphasis: Int?
        switch step.technique {
        case .nakedSingle, .hiddenSingle, .pointing, .boxLine, .xWing:
            emphasis = step.digit
        case .nakedPair, .hiddenPair, .none:
            emphasis = nil
        }

        let reveal = revealPlacement(step: step, solution: solution, solver: solver)
        return Hint(
            kind: kind,
            message: message,
            highlightedCells: step.focus,
            house: step.house,
            emphasisDigit: emphasis,
            reveal: reveal
        )
    }

    private static func revealPlacement(
        step: LogicStep,
        solution: [Int],
        solver: HumanSolver
    ) -> CellPlacement? {
        if let placement = step.placement {
            return placement
        }
        let empties = step.focus.filter { solver.candidateDigits(at: $0).isEmpty == false }
        guard let index = empties.min(by: { lhs, rhs in
            let leftCount = solver.candidateDigits(at: lhs).count
            let rightCount = solver.candidateDigits(at: rhs).count
            if leftCount == rightCount { return lhs < rhs }
            return leftCount < rightCount
        }) else {
            return nil
        }
        return CellPlacement(index: index, digit: solution[index])
    }

    private static func hiddenMessage(_ house: House?) -> String {
        switch house {
        case .row:
            return "In this row, one digit has only one home."
        case .column:
            return "In this column, one digit has only one home."
        case .box:
            return "In this box, one digit has only one home."
        case nil:
            return "One digit has only one home in this house."
        }
    }

    private static func pointingMessage(_ house: House?) -> String {
        switch house {
        case .row:
            return "Inside this box, a digit lines up on one row. It can't repeat along the rest of that row."
        case .column:
            return "Inside this box, a digit lines up on one column. It can't repeat down the rest of that column."
        default:
            return "Inside this box, a digit lines up. It can't repeat along the rest of that line."
        }
    }

    private static func boxLineMessage(_ house: House?) -> String {
        switch house {
        case .row:
            return "Along this row, a digit stays inside one box. It can't go elsewhere in that box."
        case .column:
            return "Down this column, a digit stays inside one box. It can't go elsewhere in that box."
        default:
            return "A digit on this line stays inside one box."
        }
    }
}
