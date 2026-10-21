// Makes Quilt puzzles: an N×N grid with clues. The answer splits the grid into rectangles; each one
// holds exactly one clue, its area is the clue's number, and its shape matches the clue's mark
// ("square", "tall" = taller than wide, "wide" = wider than tall, "any"). Exactly one answer each.
//
//   node scripts/puzzles/quilt.mjs > packs/games/quilt/assets/puzzles.json
//
// A puzzle is { n, clues: [[cell, area, shape], …], s: the answer's patches [[row, col, width, height], …] }
// with shape "s", "t", "w" or "a" (any).
// The output is the same every run (a fixed seed), so the dailies never change once published.

const LEVELS = {
  easy: { n: 5, maxArea: 6, anyShare: 0 },
  medium: { n: 6, maxArea: 8, anyShare: 0.35 },
  hard: { n: 7, maxArea: 9, anyShare: 0.7 },
};
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

const shapeOf = (w, h) => (w === h ? "s" : h > w ? "t" : "w");

// Random rectangles that cover the board: each starts at the first free cell (reading order).
function partition(n, maxArea, rand) {
  const owner = new Array(n * n).fill(-1), rects = [];
  for (let i = 0; i < n * n; i++) {
    if (owner[i] >= 0) continue;
    const r = Math.floor(i / n), c = i % n;
    const options = [];
    for (let h = 1; r + h <= n; h++) {
      for (let w = 1; c + w <= n; w++) {
        if (w * h > maxArea) break;
        let free = true;
        for (let y = r; y < r + h && free; y++) for (let x = c; x < c + w; x++) if (owner[y * n + x] >= 0) { free = false; break; }
        if (!free) break;
        if (w * h >= 2) options.push([w, h]);
      }
    }
    if (!options.length) return null;                 // only a single cell fits: try again
    const [w, h] = options[Math.floor(rand() * options.length)];
    for (let y = r; y < r + h; y++) for (let x = c; x < c + w; x++) owner[y * n + x] = rects.length;
    rects.push({ r, c, w, h });
  }
  return rects;
}

// Counts answers (up to 2): each clue picks one of its possible rectangles, without overlaps.
function count(n, clues) {
  const clueAt = new Map(clues.map(([cell], k) => [cell, k]));
  const options = clues.map(([cell, area, shape], k) => {
    const r0 = Math.floor(cell / n), c0 = cell % n, list = [];
    for (let w = 1; w <= area; w++) {
      if (area % w) continue;
      const h = area / w;
      if (shape !== "a" && shapeOf(w, h) !== shape) continue;
      for (let r = r0 - h + 1; r <= r0; r++) {
        for (let c = c0 - w + 1; c <= c0; c++) {
          if (r < 0 || c < 0 || r + h > n || c + w > n) continue;
          const cells = [];
          let ok = true;
          for (let y = r; y < r + h && ok; y++) {
            for (let x = c; x < c + w; x++) {
              const j = y * n + x;
              if (clueAt.has(j) && clueAt.get(j) !== k) { ok = false; break; }
              cells.push(j);
            }
          }
          if (ok) list.push(cells);
        }
      }
    }
    return list;
  });
  const taken = new Uint8Array(n * n);
  let found = 0;
  // Clues with the fewest options first.
  const order = clues.map((_, k) => k).sort((a, b) => options[a].length - options[b].length);
  const go = d => {
    if (found >= 2) return;
    if (d === order.length) { found++; return; }
    for (const cells of options[order[d]]) {
      if (cells.some(j => taken[j])) continue;
      cells.forEach(j => taken[j] = 1);
      go(d + 1);
      cells.forEach(j => taken[j] = 0);
      if (found >= 2) return;
    }
  };
  go(0);
  return found;
}

function puzzle(level, rand) {
  const { n, maxArea, anyShare } = LEVELS[level];
  const rects = partition(n, maxArea, rand);
  if (!rects) return null;
  const clues = rects.map(({ r, c, w, h }) => {
    const cell = (r + Math.floor(rand() * h)) * n + (c + Math.floor(rand() * w));
    return [cell, w * h, shapeOf(w, h)];
  });
  if (count(n, clues) !== 1) return null;
  // Harder levels hide some shape marks ("any"), only where the answer stays the only one.
  for (const k of shuffle(clues.map((_, k) => k), rand)) {
    if (rand() >= anyShare) continue;
    const old = clues[k][2];
    clues[k][2] = "a";
    if (count(n, clues) !== 1) clues[k][2] = old;
  }
  return { n, clues: clues.sort((a, b) => a[0] - b[0]), s: rects.map(({ r, c, w, h }) => [r, c, w, h]) };
}

const rand = rng(20261023);
const out = {};
for (const level of Object.keys(LEVELS)) {
  const list = [], seen = new Set();
  while (list.length < COUNT) {
    const p = puzzle(level, rand);
    if (!p) continue;
    const key = JSON.stringify(p.clues);
    if (seen.has(key)) continue;
    seen.add(key);
    list.push(p);
  }
  out[level] = list;
  const patches = list.reduce((s, p) => s + p.clues.length, 0) / list.length;
  const any = list.reduce((s, p) => s + p.clues.filter(c => c[2] === "a").length, 0) / list.length;
  process.stderr.write(`${level} (${LEVELS[level].n}×${LEVELS[level].n}): ${list.length} puzzles, ${patches.toFixed(1)} patches, ${any.toFixed(1)} "any"\n`);
}
for (const list of Object.values(out)) for (const p of list) if (count(p.n, p.clues) !== 1) throw new Error("not unique");
process.stdout.write(JSON.stringify(out) + "\n");
