// Makes Crowns puzzles: an N×N grid split into N coloured regions, with exactly one way to place
// N crowns (one per row, column and region, none touching, not even diagonally).
//
//   node scripts/puzzles/crowns.mjs > packs/games/crowns/assets/puzzles.json
//
// A puzzle is { r: one region letter per cell, s: the crown's column in each row }.
//
// Every puzzle is checked by a solver that counts solutions; only boards with exactly one are kept.
// The output is the same every run (a fixed seed), so the daily puzzles never change once published.

const SIZES = { 6: 600, 7: 600, 8: 600, 9: 600 };   // board size → puzzles made

// A small seeded random number generator (mulberry32).
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

// Crowns: col[r] for each row, no two in a column, neighbouring rows at least 2 columns apart.
function placeCrowns(n, rand) {
  const col = [], used = new Set();
  const go = r => {
    if (r === n) return true;
    for (const c of shuffle([...Array(n).keys()], rand)) {
      if (used.has(c) || (r > 0 && Math.abs(col[r - 1] - c) < 2)) continue;
      col[r] = c; used.add(c);
      if (go(r + 1)) return true;
      used.delete(c);
    }
    return false;
  };
  return go(0) ? col : null;
}

// Regions grown at random from the crowns until they fill the board.
function growRegions(n, col, rand) {
  const region = new Array(n * n).fill(-1);
  const frontier = [];
  for (let r = 0; r < n; r++) { region[r * n + col[r]] = r; frontier.push(r * n + col[r]); }
  let left = n * n - n;
  while (left > 0) {
    const k = Math.floor(rand() * frontier.length);
    const cell = frontier[k];
    const r = Math.floor(cell / n), c = cell % n;
    const open = [[r - 1, c], [r + 1, c], [r, c - 1], [r, c + 1]]
      .filter(([y, x]) => y >= 0 && y < n && x >= 0 && x < n && region[y * n + x] < 0);
    if (!open.length) { frontier.splice(k, 1); continue; }
    const [y, x] = open[Math.floor(rand() * open.length)];
    region[y * n + x] = region[cell];
    frontier.push(y * n + x);
    left--;
  }
  return region;
}

// Counts solutions, stopping at `limit`. Returns { count, first, second }.
function solve(n, region, limit = 2) {
  const colUsed = new Array(n).fill(false), regUsed = new Array(n).fill(false);
  const pos = [];
  let count = 0, first = null, second = null;
  const go = r => {
    if (count >= limit) return;
    if (r === n) {
      count++;
      if (count === 1) first = pos.slice(); else second = pos.slice();
      return;
    }
    for (let c = 0; c < n; c++) {
      const g = region[r * n + c];
      if (colUsed[c] || regUsed[g] || (r > 0 && Math.abs(pos[r - 1] - c) < 2)) continue;
      colUsed[c] = regUsed[g] = true; pos[r] = c;
      go(r + 1);
      colUsed[c] = regUsed[g] = false;
      if (count >= limit) return;
    }
  };
  go(0);
  return { count, first, second };
}

// Is the region still one connected piece?
function connected(n, region, g) {
  const cells = [];
  for (let i = 0; i < n * n; i++) if (region[i] === g) cells.push(i);
  if (!cells.length) return false;
  const seen = new Set([cells[0]]), stack = [cells[0]];
  while (stack.length) {
    const i = stack.pop(), r = Math.floor(i / n), c = i % n;
    for (const [y, x] of [[r - 1, c], [r + 1, c], [r, c - 1], [r, c + 1]]) {
      const j = y * n + x;
      if (y >= 0 && y < n && x >= 0 && x < n && region[j] === g && !seen.has(j)) { seen.add(j); stack.push(j); }
    }
  }
  return seen.size === cells.length;
}

// Reshapes regions until the planted crowns are the only solution: each time a second solution
// shows up, one of its crowns' cells is handed to a neighbouring region, which rules that solution out.
function makeUnique(n, col, region, rand) {
  const planted = new Set(col.map((c, r) => r * n + c));
  for (let step = 0; step < 400; step++) {
    const { count, first, second } = solve(n, region);
    if (count === 1) return region;
    const other = first.every((c, r) => c === col[r]) ? second : first;
    const moves = shuffle(other.map((c, r) => r * n + c).filter(i => !planted.has(i)), rand);
    let moved = false;
    for (const cell of moves) {
      const r = Math.floor(cell / n), c = cell % n, from = region[cell];
      const targets = shuffle([[r - 1, c], [r + 1, c], [r, c - 1], [r, c + 1]]
        .filter(([y, x]) => y >= 0 && y < n && x >= 0 && x < n)
        .map(([y, x]) => region[y * n + x]).filter(g => g !== from), rand);
      for (const to of targets) {
        region[cell] = to;
        if (connected(n, region, from)) { moved = true; break; }
        region[cell] = from;
      }
      if (moved) break;
    }
    if (!moved) return null;
  }
  return null;
}

function puzzle(n, rand) {
  for (;;) {
    const col = placeCrowns(n, rand);
    const region = makeUnique(n, col, growRegions(n, col, rand), rand);
    if (!region) continue;
    // Regions are numbered in reading order, so the colours look the same in every puzzle's corners.
    const order = new Map();
    for (const g of region) if (!order.has(g)) order.set(g, order.size);
    return { r: region.map(g => "abcdefghijk"[order.get(g)]).join(""), s: col };
  }
}

const rand = rng(20261020);
const out = {};
for (const [size, count] of Object.entries(SIZES)) {
  const n = Number(size), seen = new Set(), list = [];
  while (list.length < count) {
    const p = puzzle(n, rand);
    if (seen.has(p.r)) continue;
    seen.add(p.r);
    list.push(p);
  }
  out[size] = list;
  process.stderr.write(`${n}×${n}: ${list.length} puzzles\n`);
}
// The checker in the pack's tests re-solves every puzzle, so a wrong one never ships.
for (const [size, list] of Object.entries(out)) {
  for (const p of list) {
    const n = Number(size), region = [...p.r].map(ch => ch.charCodeAt(0) - 97);
    if (solve(n, region).count !== 1) throw new Error("not unique: " + p);
  }
}
process.stdout.write(JSON.stringify(out) + "\n");
