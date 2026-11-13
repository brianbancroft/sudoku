import Foundation

public struct CellState: Equatable, Sendable, Codable {
    public var index: Int
    public var value: Int
    public var notes: UInt16

    public init(index: Int, value: Int, notes: UInt16) {
        self.index = index
        self.value = value
        self.notes = notes
    }
}

public struct GameAction: Equatable, Sendable, Codable {
    public var before: [CellState]
    public var after: [CellState]
    /// True when this action came from an explicit hint reveal.
    public var countsAsHint: Bool

    public init(before: [CellState], after: [CellState], countsAsHint: Bool = false) {
        self.before = before
        self.after = after
        self.countsAsHint = countsAsHint
    }
}

/// One playable puzzle: values, pencil marks, and a single undo history.
public struct SudokuGame: Equatable, Sendable {
    public let puzzle: SudokuPuzzle
    public private(set) var values: [Int]
    public private(set) var notes: [UInt16]
    public private(set) var undoStack: [GameAction]
    public private(set) var redoStack: [GameAction]
    public private(set) var hintsUsed: Int

    public init(puzzle: SudokuPuzzle) {
        precondition(puzzle.givens.count == Grid.cellCount)
        precondition(puzzle.solution.count == Grid.cellCount)
        self.puzzle = puzzle
        self.values = puzzle.givens
        self.notes = Array(repeating: 0, count: Grid.cellCount)
        self.undoStack = []
        self.redoStack = []
        self.hintsUsed = 0
    }

    public init(saved: SavedGame) {
        self.puzzle = saved.puzzle
        self.values = saved.values
        self.notes = saved.notes
        self.undoStack = saved.undoStack
        self.redoStack = saved.redoStack
        self.hintsUsed = saved.hintsUsed
    }

    public func isGiven(_ index: Int) -> Bool {
        puzzle.givens[index] != 0
    }

    public var filledCount: Int {
        values.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
    }

    public var remainingCells: Int {
        Grid.cellCount - filledCount
    }

    /// How many of each digit, 1 through 9, are still missing.
    public var remainingCounts: [Int] {
        var placed = [Int](repeating: 0, count: 9)
        for value in values where (1...9).contains(value) {
            placed[value - 1] += 1
        }
        return placed.map { 9 - $0 }
    }

    public var conflicts: Set<Int> {
        Grid.conflictingIndices(in: values)
    }

    /// Player entries that differ from the unique solution.
    public var solutionMismatches: Set<Int> {
        var mismatches = Set<Int>()
        for index in 0..<Grid.cellCount {
            let value = values[index]
            if value != 0 && !isGiven(index) && value != puzzle.solution[index] {
                mismatches.insert(index)
            }
        }
        return mismatches
    }

    public var isWon: Bool {
        Grid.isCompleteAndValid(values)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func noteDigits(at index: Int) -> [Int] {
        Grid.digits(in: notes[index])
    }

    /// Places a digit, or clears the cell when the same digit is entered again.
    /// Pencil mode toggles a mark and will not add a digit already present in the house.
    @discardableResult
    public mutating func enterDigit(
        _ digit: Int,
        at index: Int,
        pencil: Bool,
        togglesOffExisting: Bool = true
    ) -> Bool {
        guard Grid.isValidIndex(index), (1...9).contains(digit), !isWon else { return false }
        guard !isGiven(index) else { return false }

        if pencil {
            guard values[index] == 0 else { return false }
            let flag = Grid.bit(digit)
            let turningOn = notes[index] & flag == 0
            if turningOn && houseContains(digit, around: index) {
                return false
            }
            let before = CellState(index: index, value: values[index], notes: notes[index])
            notes[index] ^= flag
            let after = CellState(index: index, value: values[index], notes: notes[index])
            push(before: [before], after: [after])
            return true
        }

        if values[index] == digit {
            guard togglesOffExisting else { return false }
            return erase(at: index)
        }

        let flag = Grid.bit(digit)
        var affected = [index]
        for peer in Grid.peers[index] where notes[peer] & flag != 0 {
            affected.append(peer)
        }
        let before = affected.map { CellState(index: $0, value: values[$0], notes: notes[$0]) }
        values[index] = digit
        notes[index] = 0
        for peer in Grid.peers[index] {
            notes[peer] &= ~flag
        }
        let after = affected.map { CellState(index: $0, value: values[$0], notes: notes[$0]) }
        push(before: before, after: after)
        return true
    }

    @discardableResult
    public mutating func erase(at index: Int) -> Bool {
        guard Grid.isValidIndex(index), !isGiven(index), !isWon else { return false }
        guard values[index] != 0 || notes[index] != 0 else { return false }
        let before = CellState(index: index, value: values[index], notes: notes[index])
        values[index] = 0
        notes[index] = 0
        let after = CellState(index: index, value: 0, notes: 0)
        push(before: [before], after: [after])
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let action = undoStack.popLast() else { return false }
        write(action.before)
        redoStack.append(action)
        if action.countsAsHint {
            hintsUsed = max(0, hintsUsed - 1)
        }
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let action = redoStack.popLast() else { return false }
        write(action.after)
        undoStack.append(action)
        if action.countsAsHint {
            hintsUsed += 1
        }
        return true
    }

    public func makeHint() -> Hint? {
        HintEngine.hint(for: self)
    }

    /// Writes the hint's digit only after the player confirms.
    @discardableResult
    public mutating func reveal(_ hint: Hint) -> Bool {
        guard let placement = hint.reveal, !isWon else { return false }
        let changed = enterDigit(
            placement.digit,
            at: placement.index,
            pencil: false,
            togglesOffExisting: false
        )
        if changed, !undoStack.isEmpty {
            undoStack[undoStack.count - 1].countsAsHint = true
            hintsUsed += 1
        }
        return changed
    }

    public func saved() -> SavedGame {
        SavedGame(
            puzzle: puzzle,
            values: values,
            notes: notes,
            undoStack: undoStack,
            redoStack: redoStack,
            hintsUsed: hintsUsed
        )
    }

    private func houseContains(_ digit: Int, around index: Int) -> Bool {
        if values[index] == digit { return true }
        for peer in Grid.peers[index] where values[peer] == digit {
            return true
        }
        return false
    }

    private mutating func push(before: [CellState], after: [CellState]) {
        undoStack.append(GameAction(before: before, after: after))
        redoStack.removeAll()
    }

    private mutating func write(_ states: [CellState]) {
        for state in states {
            values[state.index] = state.value
            notes[state.index] = state.notes
        }
    }
}

public struct SavedGame: Equatable, Sendable, Codable {
    public var puzzle: SudokuPuzzle
    public var values: [Int]
    public var notes: [UInt16]
    public var undoStack: [GameAction]
    public var redoStack: [GameAction]
    public var hintsUsed: Int

    public init(
        puzzle: SudokuPuzzle,
        values: [Int],
        notes: [UInt16],
        undoStack: [GameAction],
        redoStack: [GameAction],
        hintsUsed: Int
    ) {
        self.puzzle = puzzle
        self.values = values
        self.notes = notes
        self.undoStack = undoStack
        self.redoStack = redoStack
        self.hintsUsed = hintsUsed
    }
}
