import Foundation

/// Techniques a careful player can apply without guessing.
/// Ordered from the move this app treats as easiest to the move it treats as hardest.
public enum Technique: Int, Comparable, Sendable, Codable {
    case none = 0
    case nakedSingle = 1
    case hiddenSingle = 2
    case nakedPair = 3
    case hiddenPair = 4
    case pointing = 5
    case boxLine = 6
    case xWing = 7

    public static func < (lhs: Technique, rhs: Technique) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var difficulty: Difficulty {
        switch self {
        case .none, .nakedSingle:
            return .easy
        case .hiddenSingle:
            return .medium
        case .nakedPair, .hiddenPair, .pointing, .boxLine, .xWing:
            return .hard
        }
    }
}

public struct SolveReport: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case solved
        case contradicted
        case stuck
    }

    public var outcome: Outcome
    public var hardest: Technique
    public var values: [Int]

    public var difficulty: Difficulty {
        outcome == .solved ? hardest.difficulty : .expert
    }
}

public struct LogicStep: Equatable, Sendable {
    public var technique: Technique
    public var house: House?
    /// Cells the player should look at.
    public var focus: [Int]
    /// A digit this step is about, when there is exactly one.
    public var digit: Int?
    /// Digits a pair is holding, when the step is a pair.
    public var digits: [Int]
    /// When set, the step places this digit. Elimination steps leave it nil.
    public var placement: CellPlacement?
}

public struct CellPlacement: Equatable, Sendable, Codable {
    public var index: Int
    public var digit: Int

    public init(index: Int, digit: Int) {
        self.index = index
        self.digit = digit
    }
}

/// Logical solver used for difficulty ratings and for the first useful hint.
public struct HumanSolver: Sendable {
    public private(set) var values: [Int]
    private var candidates: [UInt16]

    public init(values: [Int]) {
        precondition(values.count == Grid.cellCount)
        self.values = values
        self.candidates = Self.candidates(for: values)
    }

    public func candidateDigits(at index: Int) -> [Int] {
        Grid.digits(in: candidates[index])
    }

    public func solve(allowing maxTechnique: Technique) -> SolveReport {
        var solver = self
        var hardest: Technique = .none
        var guardRail = 0
        while guardRail < 600 {
            guardRail += 1
            if let placement = solver.nakedSingle() {
                guard maxTechnique >= .nakedSingle else { break }
                solver.place(placement.digit, at: placement.index)
                hardest = max(hardest, .nakedSingle)
                continue
            }
            if maxTechnique >= .hiddenSingle, let hidden = solver.hiddenSingle() {
                solver.place(hidden.digit, at: hidden.index)
                hardest = max(hardest, .hiddenSingle)
                continue
            }
            if maxTechnique >= .nakedPair, solver.eliminateNakedPair() {
                hardest = max(hardest, .nakedPair)
                continue
            }
            if maxTechnique >= .hiddenPair, solver.eliminateHiddenPair() {
                hardest = max(hardest, .hiddenPair)
                continue
            }
            if maxTechnique >= .pointing, solver.eliminatePointing() {
                hardest = max(hardest, .pointing)
                continue
            }
            if maxTechnique >= .boxLine, solver.eliminateBoxLine() {
                hardest = max(hardest, .boxLine)
                continue
            }
            if maxTechnique >= .xWing, solver.eliminateXWing() {
                hardest = max(hardest, .xWing)
                continue
            }
            break
        }

        if solver.values.allSatisfy({ $0 != 0 }) {
            return SolveReport(outcome: .solved, hardest: hardest, values: solver.values)
        }
        let contradicted = (0..<Grid.cellCount).contains { index in
            solver.values[index] == 0 && solver.candidates[index] == 0
        }
        return SolveReport(
            outcome: contradicted ? .contradicted : .stuck,
            hardest: hardest,
            values: solver.values
        )
    }

    /// The easiest logical step available, or nil when the grid needs a guess
    /// or is already complete.
    public func nextStep() -> LogicStep? {
        let solver = self
        if let placement = solver.nakedSingle() {
            return LogicStep(
                technique: .nakedSingle,
                house: nil,
                focus: [placement.index],
                digit: placement.digit,
                digits: [placement.digit],
                placement: placement
            )
        }
        if let hidden = solver.hiddenSingleDetail() {
            return LogicStep(
                technique: .hiddenSingle,
                house: hidden.house,
                focus: [hidden.index],
                digit: hidden.digit,
                digits: [hidden.digit],
                placement: CellPlacement(index: hidden.index, digit: hidden.digit)
            )
        }
        if let pair = solver.nakedPairDetail() {
            return LogicStep(
                technique: .nakedPair,
                house: pair.house,
                focus: pair.focus,
                digit: nil,
                digits: pair.digits,
                placement: nil
            )
        }
        if let pair = solver.hiddenPairDetail() {
            return LogicStep(
                technique: .hiddenPair,
                house: pair.house,
                focus: pair.focus,
                digit: nil,
                digits: pair.digits,
                placement: nil
            )
        }
        if let pointing = solver.pointingDetail() {
            return LogicStep(
                technique: .pointing,
                house: pointing.house,
                focus: pointing.focus,
                digit: pointing.digit,
                digits: [pointing.digit],
                placement: nil
            )
        }
        if let reduction = solver.boxLineDetail() {
            return LogicStep(
                technique: .boxLine,
                house: reduction.house,
                focus: reduction.focus,
                digit: reduction.digit,
                digits: [reduction.digit],
                placement: nil
            )
        }
        if let wing = solver.xWingDetail() {
            return LogicStep(
                technique: .xWing,
                house: nil,
                focus: wing.focus,
                digit: wing.digit,
                digits: [wing.digit],
                placement: nil
            )
        }
        return nil
    }

    public func fewestCandidateCell() -> (index: Int, digits: [Int])? {
        var bestIndex = -1
        var bestMask: UInt16 = 0
        var bestCount = 10
        for index in 0..<Grid.cellCount where values[index] == 0 {
            let count = candidates[index].nonzeroBitCount
            if count > 0 && count < bestCount {
                bestCount = count
                bestIndex = index
                bestMask = candidates[index]
            }
        }
        guard bestIndex >= 0 else { return nil }
        return (bestIndex, Grid.digits(in: bestMask))
    }

    // MARK: - Placements

    private struct HiddenHit {
        var index: Int
        var digit: Int
        var house: House
    }

    private mutating func place(_ digit: Int, at index: Int) {
        values[index] = digit
        candidates[index] = 0
        let flag = Grid.bit(digit)
        for peer in Grid.peers[index] {
            candidates[peer] &= ~flag
        }
    }

    private func nakedSingle() -> CellPlacement? {
        for index in 0..<Grid.cellCount where values[index] == 0 && candidates[index].nonzeroBitCount == 1 {
            let digit = Int(candidates[index].trailingZeroBitCount) + 1
            return CellPlacement(index: index, digit: digit)
        }
        return nil
    }

    private func hiddenSingle() -> CellPlacement? {
        guard let hit = hiddenSingleDetail() else { return nil }
        return CellPlacement(index: hit.index, digit: hit.digit)
    }

    private func hiddenSingleDetail() -> HiddenHit? {
        for row in 0..<9 {
            if let hit = hiddenSingle(in: Grid.rowCells[row], house: .row(row)) { return hit }
        }
        for column in 0..<9 {
            if let hit = hiddenSingle(in: Grid.columnCells[column], house: .column(column)) { return hit }
        }
        for box in 0..<9 {
            if let hit = hiddenSingle(in: Grid.boxCells[box], house: .box(box)) { return hit }
        }
        return nil
    }

    private func hiddenSingle(in cells: [Int], house: House) -> HiddenHit? {
        for digit in 1...9 {
            let flag = Grid.bit(digit)
            var found: Int?
            var unique = true
            for index in cells {
                if values[index] == digit {
                    unique = false
                    break
                }
                if values[index] == 0 && candidates[index] & flag != 0 {
                    if found != nil {
                        unique = false
                        break
                    }
                    found = index
                }
            }
            if unique, let found {
                return HiddenHit(index: found, digit: digit, house: house)
            }
        }
        return nil
    }

    // MARK: - Eliminations

    private struct PairHit {
        var house: House
        var focus: [Int]
        var digits: [Int]
    }

    private struct DigitHit {
        var house: House?
        var focus: [Int]
        var digit: Int
    }

    private mutating func eliminateNakedPair() -> Bool {
        nakedPairDetail(applying: true) != nil
    }

    private func nakedPairDetail() -> PairHit? {
        var copy = self
        return copy.nakedPairDetail(applying: false)
    }

    private mutating func nakedPairDetail(applying: Bool) -> PairHit? {
        for (house, cells) in Self.houses {
            let pairCells = cells.filter { values[$0] == 0 && candidates[$0].nonzeroBitCount == 2 }
            guard pairCells.count >= 2 else { continue }
            for left in 0..<(pairCells.count - 1) {
                for right in (left + 1)..<pairCells.count {
                    let first = pairCells[left]
                    let second = pairCells[right]
                    let mask = candidates[first]
                    guard mask == candidates[second] else { continue }
                    var removed = false
                    if applying {
                        for index in cells where index != first && index != second && values[index] == 0 {
                            if candidates[index] & mask != 0 {
                                candidates[index] &= ~mask
                                removed = true
                            }
                        }
                    } else {
                        removed = cells.contains { index in
                            index != first && index != second && values[index] == 0 && candidates[index] & mask != 0
                        }
                    }
                    if removed {
                        return PairHit(house: house, focus: [first, second], digits: Grid.digits(in: mask))
                    }
                }
            }
        }
        return nil
    }

    private mutating func eliminateHiddenPair() -> Bool {
        hiddenPairDetail(applying: true) != nil
    }

    private func hiddenPairDetail() -> PairHit? {
        var copy = self
        return copy.hiddenPairDetail(applying: false)
    }

    private mutating func hiddenPairDetail(applying: Bool) -> PairHit? {
        for (house, cells) in Self.houses {
            for firstDigit in 1...8 {
                for secondDigit in (firstDigit + 1)...9 {
                    let firstFlag = Grid.bit(firstDigit)
                    let secondFlag = Grid.bit(secondDigit)
                    var firstSpots: [Int] = []
                    var secondSpots: [Int] = []
                    for index in cells where values[index] == 0 {
                        if candidates[index] & firstFlag != 0 { firstSpots.append(index) }
                        if candidates[index] & secondFlag != 0 { secondSpots.append(index) }
                    }
                    guard firstSpots.count == 2, firstSpots == secondSpots else { continue }
                    let keep = firstFlag | secondFlag
                    var removed = false
                    for index in firstSpots where candidates[index] & ~keep != 0 {
                        if applying {
                            candidates[index] &= keep
                        }
                        removed = true
                    }
                    if removed {
                        return PairHit(
                            house: house,
                            focus: firstSpots,
                            digits: [firstDigit, secondDigit]
                        )
                    }
                }
            }
        }
        return nil
    }

    private mutating func eliminatePointing() -> Bool {
        pointingDetail(applying: true) != nil
    }

    private func pointingDetail() -> DigitHit? {
        var copy = self
        return copy.pointingDetail(applying: false)
    }

    private mutating func pointingDetail(applying: Bool) -> DigitHit? {
        for box in 0..<9 {
            let cells = Grid.boxCells[box]
            for digit in 1...9 {
                let flag = Grid.bit(digit)
                let spots = cells.filter { values[$0] == 0 && candidates[$0] & flag != 0 }
                guard spots.count >= 2 else { continue }
                let rows = Set(spots.map { Grid.row(of: $0) })
                if rows.count == 1, let row = rows.first {
                    let outside = Grid.rowCells[row].filter {
                        Grid.box(of: $0) != box && values[$0] == 0 && candidates[$0] & flag != 0
                    }
                    if !outside.isEmpty {
                        if applying {
                            for index in outside { candidates[index] &= ~flag }
                        }
                        return DigitHit(house: .row(row), focus: spots, digit: digit)
                    }
                }
                let columns = Set(spots.map { Grid.column(of: $0) })
                if columns.count == 1, let column = columns.first {
                    let outside = Grid.columnCells[column].filter {
                        Grid.box(of: $0) != box && values[$0] == 0 && candidates[$0] & flag != 0
                    }
                    if !outside.isEmpty {
                        if applying {
                            for index in outside { candidates[index] &= ~flag }
                        }
                        return DigitHit(house: .column(column), focus: spots, digit: digit)
                    }
                }
            }
        }
        return nil
    }

    private mutating func eliminateBoxLine() -> Bool {
        boxLineDetail(applying: true) != nil
    }

    private func boxLineDetail() -> DigitHit? {
        var copy = self
        return copy.boxLineDetail(applying: false)
    }

    private mutating func boxLineDetail(applying: Bool) -> DigitHit? {
        for row in 0..<9 {
            if let hit = boxLine(
                line: Grid.rowCells[row],
                house: .row(row),
                sameLine: { Grid.row(of: $0) == row },
                applying: applying
            ) {
                return hit
            }
        }
        for column in 0..<9 {
            if let hit = boxLine(
                line: Grid.columnCells[column],
                house: .column(column),
                sameLine: { Grid.column(of: $0) == column },
                applying: applying
            ) {
                return hit
            }
        }
        return nil
    }

    private mutating func boxLine(
        line: [Int],
        house: House,
        sameLine: (Int) -> Bool,
        applying: Bool
    ) -> DigitHit? {
        for digit in 1...9 {
            let flag = Grid.bit(digit)
            let spots = line.filter { values[$0] == 0 && candidates[$0] & flag != 0 }
            guard spots.count >= 2 else { continue }
            let boxes = Set(spots.map { Grid.box(of: $0) })
            guard boxes.count == 1, let box = boxes.first else { continue }
            let outside = Grid.boxCells[box].filter {
                !sameLine($0) && values[$0] == 0 && candidates[$0] & flag != 0
            }
            if outside.isEmpty { continue }
            if applying {
                for index in outside { candidates[index] &= ~flag }
            }
            return DigitHit(house: house, focus: spots, digit: digit)
        }
        return nil
    }

    private mutating func eliminateXWing() -> Bool {
        xWingDetail(applying: true) != nil
    }

    private func xWingDetail() -> DigitHit? {
        var copy = self
        return copy.xWingDetail(applying: false)
    }

    private mutating func xWingDetail(applying: Bool) -> DigitHit? {
        for digit in 1...9 {
            let flag = Grid.bit(digit)
            var rowSpots: [[Int]] = []
            for row in 0..<9 {
                rowSpots.append(Grid.rowCells[row].filter { values[$0] == 0 && candidates[$0] & flag != 0 })
            }
            for top in 0..<8 where rowSpots[top].count == 2 {
                let columns = rowSpots[top].map { Grid.column(of: $0) }
                for bottom in (top + 1)..<9 where rowSpots[bottom].count == 2 {
                    let otherColumns = rowSpots[bottom].map { Grid.column(of: $0) }
                    guard columns == otherColumns else { continue }
                    var affected: [Int] = []
                    for column in columns {
                        for index in Grid.columnCells[column] where values[index] == 0 && candidates[index] & flag != 0 {
                            let row = Grid.row(of: index)
                            if row != top && row != bottom { affected.append(index) }
                        }
                    }
                    if affected.isEmpty { continue }
                    if applying {
                        for index in affected { candidates[index] &= ~flag }
                    }
                    return DigitHit(house: nil, focus: rowSpots[top] + rowSpots[bottom], digit: digit)
                }
            }

            var columnSpots: [[Int]] = []
            for column in 0..<9 {
                columnSpots.append(
                    Grid.columnCells[column].filter { values[$0] == 0 && candidates[$0] & flag != 0 }
                )
            }
            for left in 0..<8 where columnSpots[left].count == 2 {
                let rows = columnSpots[left].map { Grid.row(of: $0) }
                for right in (left + 1)..<9 where columnSpots[right].count == 2 {
                    guard rows == columnSpots[right].map({ Grid.row(of: $0) }) else { continue }
                    var affected: [Int] = []
                    for row in rows {
                        for index in Grid.rowCells[row] where values[index] == 0 && candidates[index] & flag != 0 {
                            let column = Grid.column(of: index)
                            if column != left && column != right { affected.append(index) }
                        }
                    }
                    if affected.isEmpty { continue }
                    if applying {
                        for index in affected { candidates[index] &= ~flag }
                    }
                    return DigitHit(house: nil, focus: columnSpots[left] + columnSpots[right], digit: digit)
                }
            }
        }
        return nil
    }

    private static func candidates(for values: [Int]) -> [UInt16] {
        var masks = [UInt16](repeating: 0, count: Grid.cellCount)
        for index in 0..<Grid.cellCount where values[index] == 0 {
            var used: UInt16 = 0
            for peer in Grid.peers[index] where values[peer] != 0 {
                let digit = values[peer]
                if (1...9).contains(digit) {
                    used |= Grid.bit(digit)
                }
            }
            masks[index] = Grid.allDigits & ~used
        }
        return masks
    }

    private static let houses: [(House, [Int])] = {
        var list: [(House, [Int])] = []
        for index in 0..<9 { list.append((.row(index), Grid.rowCells[index])) }
        for index in 0..<9 { list.append((.column(index), Grid.columnCells[index])) }
        for index in 0..<9 { list.append((.box(index), Grid.boxCells[index])) }
        return list
    }()
}
