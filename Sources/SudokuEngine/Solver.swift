import Foundation

/// Exact backtracking solver. Search is deterministic: digits are tried from
/// low to high, and the next cell is the one with the fewest candidates.
public enum SudokuSolver {
    /// Up to `limit` completed grids. An invalid puzzle returns an empty list.
    public static func solutions(of values: [Int], limit: Int = 2) -> [[Int]] {
        guard values.count == Grid.cellCount, limit > 0 else { return [] }
        var grid = values
        var rows = [UInt16](repeating: 0, count: 9)
        var columns = [UInt16](repeating: 0, count: 9)
        var boxes = [UInt16](repeating: 0, count: 9)

        for index in 0..<Grid.cellCount {
            let digit = grid[index]
            if digit == 0 { continue }
            guard (1...9).contains(digit) else { return [] }
            let flag = Grid.bit(digit)
            let row = Grid.row(of: index)
            let column = Grid.column(of: index)
            let box = Grid.box(of: index)
            if rows[row] & flag != 0 || columns[column] & flag != 0 || boxes[box] & flag != 0 {
                return []
            }
            rows[row] |= flag
            columns[column] |= flag
            boxes[box] |= flag
        }

        func candidateMask(at index: Int) -> UInt16 {
            let row = Grid.row(of: index)
            let column = Grid.column(of: index)
            let box = Grid.box(of: index)
            return Grid.allDigits & ~(rows[row] | columns[column] | boxes[box])
        }

        func place(_ digit: Int, at index: Int) {
            let flag = Grid.bit(digit)
            grid[index] = digit
            rows[Grid.row(of: index)] |= flag
            columns[Grid.column(of: index)] |= flag
            boxes[Grid.box(of: index)] |= flag
        }

        func clear(_ digit: Int, at index: Int) {
            let flag = Grid.bit(digit)
            grid[index] = 0
            rows[Grid.row(of: index)] &= ~flag
            columns[Grid.column(of: index)] &= ~flag
            boxes[Grid.box(of: index)] &= ~flag
        }

        var found: [[Int]] = []

        func undo(_ placed: [Int]) {
            for index in placed.reversed() {
                clear(grid[index], at: index)
            }
        }

        /// Fills naked singles and hidden singles. Returns nil when the grid
        /// contradicts itself. Forced cells are listed so search can undo them.
        func propagate() -> [Int]? {
            var placed: [Int] = []
            var changed = true
            while changed {
                changed = false
                for index in 0..<Grid.cellCount where grid[index] == 0 {
                    let mask = candidateMask(at: index)
                    if mask == 0 {
                        undo(placed)
                        return nil
                    }
                    if mask.nonzeroBitCount == 1 {
                        place(Int(mask.trailingZeroBitCount) + 1, at: index)
                        placed.append(index)
                        changed = true
                    }
                }
                if changed { continue }

                for house in Grid.allHouses {
                    for digit in 1...9 {
                        let flag = Grid.bit(digit)
                        var alreadyPlaced = false
                        var spots: [Int] = []
                        for index in house {
                            if grid[index] == digit {
                                alreadyPlaced = true
                                break
                            }
                            if grid[index] == 0 && candidateMask(at: index) & flag != 0 {
                                spots.append(index)
                                if spots.count > 1 { break }
                            }
                        }
                        if alreadyPlaced { continue }
                        if spots.isEmpty {
                            undo(placed)
                            return nil
                        }
                        if spots.count == 1 {
                            place(digit, at: spots[0])
                            placed.append(spots[0])
                            changed = true
                        }
                    }
                    if changed { break }
                }
            }
            return placed
        }

        func search() {
            if found.count >= limit { return }
            guard let forced = propagate() else { return }
            defer { undo(forced) }

            var bestIndex = -1
            var bestMask: UInt16 = 0
            var bestCount = 10
            for index in 0..<Grid.cellCount where grid[index] == 0 {
                let mask = candidateMask(at: index)
                let count = mask.nonzeroBitCount
                if count == 0 { return }
                if count < bestCount {
                    bestCount = count
                    bestIndex = index
                    bestMask = mask
                    if count == 1 { break }
                }
            }

            if bestIndex == -1 {
                found.append(grid)
                return
            }

            var bits = bestMask
            while bits != 0 && found.count < limit {
                let lowest = bits & (0 &- bits)
                bits &= ~lowest
                let digit = Int(lowest.trailingZeroBitCount) + 1
                place(digit, at: bestIndex)
                search()
                clear(digit, at: bestIndex)
            }
        }

        search()
        return found
    }

    public static func solutionCount(of values: [Int], limit: Int = 2) -> Int {
        solutions(of: values, limit: limit).count
    }

    public static func solve(_ values: [Int]) -> [Int]? {
        solutions(of: values, limit: 1).first
    }
}
