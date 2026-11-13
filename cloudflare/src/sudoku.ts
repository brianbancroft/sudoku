const all = 0x1ff;

function bit(digit: number): number {
  return 1 << (digit - 1);
}

/** Counts solutions up to `limit`. A saved puzzle must have exactly one. */
export function solutionCount(values: number[], limit = 2): number {
  if (values.length !== 81) return 0;
  const grid = values.slice();
  const rows = Array(9).fill(0);
  const columns = Array(9).fill(0);
  const boxes = Array(9).fill(0);
  for (let index = 0; index < 81; index += 1) {
    const digit = grid[index];
    if (!digit) continue;
    if (digit < 1 || digit > 9) return 0;
    const flag = bit(digit);
    const row = Math.floor(index / 9);
    const column = index % 9;
    const box = Math.floor(row / 3) * 3 + Math.floor(column / 3);
    if (rows[row] & flag || columns[column] & flag || boxes[box] & flag) return 0;
    rows[row] |= flag;
    columns[column] |= flag;
    boxes[box] |= flag;
  }
  let count = 0;
  const search = (): void => {
    if (count >= limit) return;
    let best = -1;
    let bestMask = 0;
    let bestCount = 10;
    for (let index = 0; index < 81; index += 1) {
      if (grid[index]) continue;
      const row = Math.floor(index / 9);
      const column = index % 9;
      const box = Math.floor(row / 3) * 3 + Math.floor(column / 3);
      const mask = all & ~(rows[row] | columns[column] | boxes[box]);
      const bits = mask.toString(2).replace(/0/g, "").length;
      if (bits === 0) return;
      if (bits < bestCount) {
        best = index;
        bestMask = mask;
        bestCount = bits;
        if (bits === 1) break;
      }
    }
    if (best === -1) {
      count += 1;
      return;
    }
    const row = Math.floor(best / 9);
    const column = best % 9;
    const box = Math.floor(row / 3) * 3 + Math.floor(column / 3);
    for (let digit = 1; digit <= 9; digit += 1) {
      const flag = bit(digit);
      if ((bestMask & flag) === 0) continue;
      grid[best] = digit;
      rows[row] |= flag;
      columns[column] |= flag;
      boxes[box] |= flag;
      search();
      rows[row] &= ~flag;
      columns[column] &= ~flag;
      boxes[box] &= ~flag;
      grid[best] = 0;
      if (count >= limit) return;
    }
  };
  search();
  return count;
}

export function parseGrid(raw: string): number[] | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!Array.isArray(parsed) || parsed.length !== 81) return null;
  const values = parsed.map((item) => (typeof item === "number" ? item : Number.NaN));
  if (values.some((value) => !Number.isInteger(value) || value < 0 || value > 9)) return null;
  return values;
}

export function gridsMatch(givens: number[], solution: number[]): boolean {
  if (solutionCount(solution, 2) !== 1) return false;
  if (solutionCount(givens, 2) !== 1) return false;
  for (let index = 0; index < 81; index += 1) {
    if (givens[index] !== 0 && givens[index] !== solution[index]) return false;
  }
  const solved = solve(givens);
  return !!solved && solved.every((value, index) => value === solution[index]);
}

function solve(values: number[]): number[] | null {
  const grid = values.slice();
  const rows = Array(9).fill(0);
  const columns = Array(9).fill(0);
  const boxes = Array(9).fill(0);
  for (let index = 0; index < 81; index += 1) {
    const digit = grid[index];
    if (!digit) continue;
    const flag = bit(digit);
    const row = Math.floor(index / 9);
    const column = index % 9;
    const box = Math.floor(row / 3) * 3 + Math.floor(column / 3);
    rows[row] |= flag;
    columns[column] |= flag;
    boxes[box] |= flag;
  }
  const search = (): boolean => {
    let best = -1;
    let bestMask = 0;
    let bestCount = 10;
    for (let index = 0; index < 81; index += 1) {
      if (grid[index]) continue;
      const row = Math.floor(index / 9);
      const column = index % 9;
      const box = Math.floor(row / 3) * 3 + Math.floor(column / 3);
      const mask = all & ~(rows[row] | columns[column] | boxes[box]);
      const bits = mask.toString(2).replace(/0/g, "").length;
      if (bits === 0) return false;
      if (bits < bestCount) {
        best = index;
        bestMask = mask;
        bestCount = bits;
        if (bits === 1) break;
      }
    }
    if (best === -1) return true;
    const row = Math.floor(best / 9);
    const column = best % 9;
    const box = Math.floor(row / 3) * 3 + Math.floor(column / 3);
    for (let digit = 1; digit <= 9; digit += 1) {
      const flag = bit(digit);
      if ((bestMask & flag) === 0) continue;
      grid[best] = digit;
      rows[row] |= flag;
      columns[column] |= flag;
      boxes[box] |= flag;
      if (search()) return true;
      rows[row] &= ~flag;
      columns[column] &= ~flag;
      boxes[box] &= ~flag;
      grid[best] = 0;
    }
    return false;
  };
  return search() ? grid : null;
}
