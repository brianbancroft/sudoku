import Foundation

/// Indexing, houses, and candidate bit masks for a 9×9 Sudoku.
/// Cells are numbered row-major, 0 through 80. Digit bits use bit 0 for 1
/// and bit 8 for 9.
public enum Grid {
    public static let cellCount = 81
    public static let allDigits: UInt16 = 0x1FF

    public static func bit(_ digit: Int) -> UInt16 {
        precondition((1...9).contains(digit))
        return UInt16(1) << UInt16(digit - 1)
    }

    public static func digits(in mask: UInt16) -> [Int] {
        var digits: [Int] = []
        var bits = mask
        while bits != 0 {
            let lowest = bits & (0 &- bits)
            digits.append(Int(lowest.trailingZeroBitCount) + 1)
            bits &= ~lowest
        }
        return digits
    }

    public static func row(of index: Int) -> Int { index / 9 }
    public static func column(of index: Int) -> Int { index % 9 }

    public static func box(of index: Int) -> Int {
        (index / 27) * 3 + (index % 9) / 3
    }

    public static func index(row: Int, column: Int) -> Int {
        row * 9 + column
    }

    public static func isValidIndex(_ index: Int) -> Bool {
        (0..<cellCount).contains(index)
    }

    public static let rowCells: [[Int]] = (0..<9).map { row in
        (0..<9).map { column in index(row: row, column: column) }
    }

    public static let columnCells: [[Int]] = (0..<9).map { column in
        (0..<9).map { row in index(row: row, column: column) }
    }

    public static let boxCells: [[Int]] = {
        var boxes = Array(repeating: [Int](), count: 9)
        for index in 0..<cellCount {
            boxes[box(of: index)].append(index)
        }
        return boxes
    }()

    public static let allHouses: [[Int]] = rowCells + columnCells + boxCells

    /// The other 20 cells that share a row, column, or box.
    public static let peers: [[Int]] = (0..<cellCount).map { index in
        var set = Set<Int>()
        set.formUnion(rowCells[row(of: index)])
        set.formUnion(columnCells[column(of: index)])
        set.formUnion(boxCells[box(of: index)])
        set.remove(index)
        return set.sorted()
    }

    public static func conflictingIndices(in values: [Int]) -> Set<Int> {
        guard values.count == cellCount else { return [] }
        var conflicts = Set<Int>()
        func scan(_ cells: [Int]) {
            var firstIndex: [Int: Int] = [:]
            for index in cells {
                let value = values[index]
                guard value != 0 else { continue }
                if let previous = firstIndex[value] {
                    conflicts.insert(previous)
                    conflicts.insert(index)
                } else {
                    firstIndex[value] = index
                }
            }
        }
        for row in 0..<9 { scan(rowCells[row]) }
        for column in 0..<9 { scan(columnCells[column]) }
        for box in 0..<9 { scan(boxCells[box]) }
        return conflicts
    }

    public static func isCompleteAndValid(_ values: [Int]) -> Bool {
        values.count == cellCount
            && !values.contains(0)
            && values.allSatisfy { (1...9).contains($0) }
            && conflictingIndices(in: values).isEmpty
    }

    public static func description(of values: [Int]) -> String {
        guard values.count == cellCount else { return "invalid grid" }
        var lines: [String] = []
        for row in 0..<9 {
            if row > 0 && row % 3 == 0 {
                lines.append("------+-------+------")
            }
            var cells: [String] = []
            for column in 0..<9 {
                if column > 0 && column % 3 == 0 { cells.append("|") }
                let value = values[index(row: row, column: column)]
                cells.append(value == 0 ? "." : String(value))
            }
            lines.append(cells.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}

public enum House: Equatable, Sendable, Codable {
    case row(Int)
    case column(Int)
    case box(Int)

    public var cells: [Int] {
        switch self {
        case .row(let index): Grid.rowCells[index]
        case .column(let index): Grid.columnCells[index]
        case .box(let index): Grid.boxCells[index]
        }
    }
}
