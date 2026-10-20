// Makes Dusk puzzles: an N×N grid (N even) to fill with suns and moons, half of each in every row and
// column, never three alike next to each other, plus "=" (same) and "×" (different) links between cells.
// Every puzzle has exactly one solution.
//
//   node scripts/puzzles/dusk.mjs > packs/games/dusk/assets/puzzles.json
//
// A puzzle is { g, h, v, s }: s is the answer ("s"/"m" per cell), g[i] is the given cell ("s", "m" or "."), h[i] the link between cell i and
// the one to its right, v[i] the link between cell i and the one below ("=", "x" or ".").
// The output is the same every run (a fixed seed), so the dailies never change once published.

const LEVELS = { easy: { n: 6, extra: 5 }, medium: { n: 6, extra: 1 }, hard: { n: 8, extra: 0 } };
const COUNT = 600;

function rng(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffle(a, rand) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// Can cell i hold v (1 sun, 2 moon), given the cells filled so far and the links?
function fits(n, grid, i, v, h, v2) {
  const r = Math.floor(i / n), c = i % n, half = n / 2;
  let rowCount = 0, colCount = 0;
  for (let k = 0; k < n; k++) {
    if (grid[r * n + k] === v) rowCount++;
    if (grid[k * n + c] === v) colCount++;
  }
  if (rowCount >= half || colCount >= half) return false;
  const at = (rr, cc) => (rr >= 0 && rr < n && cc >= 0 && cc < n) ? grid[rr * n + cc] : 0;
  // Never three alike in a row or column (check every triple through i).
  for (const [dr, dc] of [[0, 1], [1, 0]]) {
    for (let s = -2; s <= 0; s++) {
      let same = 0;
      for (let k = 0; k < 3; k++) {
        const rr = r + dr * (s + k), cc = c + dc * (s + k);
        if (rr === r && cc === c) same++; else if (at(rr, cc) === v) same++;
      }
      if (same === 3) return false;
    }
  }
  // Links to neighbours that are already filled.
  const link = (j, kind) => {
    const w = grid[j];
    if (!w || kind === ".") return true;
    return kind === "=" ? w === v : w !== v;
  };
  if (c > 0 && !link(i - 1, h[i - 1])) return false;
  if (c < n - 1 && !link(i + 1, h[i])) return false;
  if (r > 0 && !link(i - n, v2[i - n])) return false;
  if (r < n - 1 && !link(i + n, v2[i])) return false;
  return true;
}

// Counts solutions (stopping at `limit`), filling cells in reading order.
function count(n, givens, h, v, limit = 2) {
  const grid = givens.slice();
  let found = 0;
  const go = i => {
    if (found >= limit) return;
    if (i === n * n) { found++; return; }
    if (grid[i]) {
      const keep = grid[i]; grid[i] = 0;
      if (fits(n, grid, i, keep, h, v)) { grid[i] = keep; go(i + 1); }
      grid[i] = keep;
      return;
    }
    for (const val of [1, 2]) {
      if (!fits(n, grid, i, val, h, v)) continue;
      grid[i] = val; go(i + 1); grid[i] = 0;
      if (found >= limit) return;
    }
  };
  go(0);
  return found;
}

function solution(n, rand) {
  const grid = new Array(n * n).fill(0), none = new Array(n * n).fill(".");
  const go = i => {
    if (i === n * n) return true;
    for (const val of shuffle([1, 2], rand)) {
      if (!fits(n, grid, i, val, none, none)) continue;
      grid[i] = val;
      if (go(i + 1)) return true;
      grid[i] = 0;
    }
    return false;
  };
  go(0);
  return grid;
}

function puzzle(level, rand) {
  const { n, extra } = LEVELS[level];
  const sol = solution(n, rand);
  // Start from every cell given plus a link on about a third of the cell edges, then take clues away
  // one by one (in random order) while the answer stays the only one.
  const givens = sol.slice();
  const h = new Array(n * n).fill("."), v = new Array(n * n).fill(".");
  for (let i = 0; i < n * n; i++) {
    const r = Math.floor(i / n), c = i % n;
    if (c < n - 1 && rand() < 0.33) h[i] = sol[i] === sol[i + 1] ? "=" : "x";
    if (r < n - 1 && rand() < 0.33) v[i] = sol[i] === sol[i + n] ? "=" : "x";
  }
  const clues = [];
  for (let i = 0; i < n * n; i++) {
    clues.push(["g", i]);
    if (h[i] !== ".") clues.push(["h", i]);
    if (v[i] !== ".") clues.push(["v", i]);
  }
  const removed = [];
  for (const [kind, i] of shuffle(clues, rand)) {
    const arr = kind === "g" ? givens : kind === "h" ? h : v;
    const old = arr[i];
    arr[i] = kind === "g" ? 0 : ".";
    if (count(n, givens, h, v) !== 1) arr[i] = old; else if (kind === "g") removed.push(i);
  }
  // Easier levels get a few of the removed cells back.
  for (const i of shuffle(removed, rand).slice(0, extra)) givens[i] = sol[i];
  const shown = givens.filter(Boolean).length;
  if (shown < 2) return null;                       // a board with almost nothing given looks broken
  return { g: givens.map(x => ".sm"[x]).join(""), h: h.join(""), v: v.join(""), s: sol.map(x => ".sm"[x]).join("") };
}

const rand = rng(20261021);
const out = {};
for (const level of Object.keys(LEVELS)) {
  const seen = new Set(), list = [];
  while (list.length < COUNT) {
    const p = puzzle(level, rand);
    if (!p) continue;
    const key = p.g + p.h + p.v;
    if (seen.has(key)) continue;
    seen.add(key);
    list.push(p);
  }
  out[level] = list;
  process.stderr.write(`${level} (${LEVELS[level].n}×${LEVELS[level].n}): ${list.length} puzzles\n`);
}
// Check every puzzle again before writing.
for (const [level, list] of Object.entries(out)) {
  const n = LEVELS[level].n;
  for (const p of list) {
    if (count(n, [...p.g].map(ch => ".sm".indexOf(ch)), [...p.h], [...p.v]) !== 1) throw new Error("not unique");
  }
}
process.stdout.write(JSON.stringify(out) + "\n");
