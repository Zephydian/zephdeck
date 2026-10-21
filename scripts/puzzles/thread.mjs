// Makes Thread puzzles: an N×N grid with numbered cells (and, on harder ones, walls between some
// cells). The answer is one path through every cell, from 1 through the numbers in order to the last,
// never crossing a wall. Every puzzle has exactly one such path.
//
//   node scripts/puzzles/thread.mjs > packs/games/thread/assets/puzzles.json
//
// A puzzle is { n, nums: [[cell, number], …], walls: [[cell, cell], …], s: the answer's cells in order }.
// The output is the same every run (a fixed seed), so the dailies never change once published.

const LEVELS = {
  easy: { n: 6, keep: 10, wallShare: 0 },     // keep: stop taking numbers away at this many
  medium: { n: 7, keep: 7, wallShare: 0.04 },
  hard: { n: 8, keep: 4, wallShare: 0.1 },
};
const COUNT = 600;
const NODE_LIMIT = 400000;    // a search that runs longer counts as "not proven unique"

function rng(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const neighbours = (n, i) => {
  const r = Math.floor(i / n), c = i % n, out = [];
  if (r > 0) out.push(i - n);
  if (r < n - 1) out.push(i + n);
  if (c > 0) out.push(i - 1);
  if (c < n - 1) out.push(i + 1);
  return out;
};

// A random path through every cell: start from a snake and apply many "backbite" moves.
function randomPath(n, rand) {
  let path = [];
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) path.push(r * n + (r % 2 ? n - 1 - c : c));
  for (let step = 0; step < n * n * 40; step++) {
    if (rand() < 0.5) path.reverse();
    const end = path[path.length - 1];
    const options = neighbours(n, end).filter(x => x !== path[path.length - 2]);
    const pick = options[Math.floor(rand() * options.length)];
    const k = path.indexOf(pick);
    // Join the end to `pick`, then the old piece after `pick` runs backwards.
    path = path.slice(0, k + 1).concat(path.slice(k + 1).reverse());
  }
  return path;
}

const edge = (a, b) => (a < b ? a + "-" + b : b + "-" + a);

// Counts paths (up to 2) that visit every cell, start at the 1, meet the numbers in order and end
// at the last one. Returns 2 if the search gets too big.
function count(n, nums, walls) {
  const numberAt = new Map(nums.map(([cell, k]) => [cell, k]));
  const last = Math.max(...nums.map(x => x[1]));
  const start = nums.find(x => x[1] === 1)[0];
  const visited = new Uint8Array(n * n);
  const open = (a, b) => !walls.has(edge(a, b));
  let found = 0, nodes = 0;

  // Every unvisited cell must still be reachable from the head.
  const reachable = head => {
    const seen = new Uint8Array(n * n), stack = [head];
    seen[head] = 1;
    let total = 0;
    while (stack.length) {
      const i = stack.pop();
      for (const j of neighbours(n, i)) {
        if (!seen[j] && !visited[j] && open(i, j)) { seen[j] = 1; total++; stack.push(j); }
      }
    }
    return total;
  };

  const go = (head, depth, next) => {
    if (found >= 2 || ++nodes > NODE_LIMIT) return;
    if (depth === n * n) { if (numberAt.get(head) === last) found++; return; }
    if (reachable(head) !== n * n - depth) return;
    for (const j of neighbours(n, head)) {
      if (visited[j] || !open(head, j)) continue;
      const k = numberAt.get(j);
      if (k !== undefined && k !== next) continue;
      visited[j] = 1;
      go(j, depth + 1, k !== undefined ? next + 1 : next);
      visited[j] = 0;
      if (found >= 2 || nodes > NODE_LIMIT) return;
    }
  };
  visited[start] = 1;
  go(start, 1, 2);
  return nodes > NODE_LIMIT ? 2 : found;
}

function shuffle(a, rand) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function puzzle(level, rand) {
  const { n, keep, wallShare } = LEVELS[level];
  const path = randomPath(n, rand);
  // Walls only on edges the path doesn't use, so they never block the answer.
  const used = new Set();
  for (let k = 1; k < path.length; k++) used.add(edge(path[k - 1], path[k]));
  const walls = new Set();
  for (let i = 0; i < n * n; i++) {
    for (const j of neighbours(n, i)) {
      if (j > i && !used.has(edge(i, j)) && rand() < wallShare) walls.add(edge(i, j));
    }
  }
  // Start with a number on every third cell (and both ends), then take numbers away while the
  // path stays the only one.
  let marks = [];
  for (let k = 0; k < path.length; k++) if (k === 0 || k === path.length - 1 || k % 3 === 0) marks.push(k);
  const numbered = () => marks.map((k, idx) => [path[k], idx + 1]);
  if (count(n, numbered(), walls) !== 1) return null;
  for (const k of shuffle(marks.slice(1, -1), rand)) {
    if (marks.length <= keep) break;
    const before = marks;
    marks = marks.filter(x => x !== k);
    if (count(n, numbered(), walls) !== 1) marks = before;
  }
  return { n, nums: numbered(), walls: [...walls].map(e => e.split("-").map(Number)), s: path };
}

const rand = rng(20261022);
const out = {};
for (const level of Object.keys(LEVELS)) {
  const list = [], seen = new Set();
  while (list.length < COUNT) {
    const p = puzzle(level, rand);
    if (!p) continue;
    const key = JSON.stringify(p);
    if (seen.has(key)) continue;
    seen.add(key);
    list.push(p);
    if (list.length % 100 === 0) process.stderr.write(`${level}: ${list.length}\n`);
  }
  out[level] = list;
  const avg = list.reduce((s, p) => s + p.nums.length, 0) / list.length;
  const walls = list.reduce((s, p) => s + p.walls.length, 0) / list.length;
  process.stderr.write(`${level} (${LEVELS[level].n}×${LEVELS[level].n}): ${list.length} puzzles, ${avg.toFixed(1)} numbers, ${walls.toFixed(1)} walls\n`);
}
process.stdout.write(JSON.stringify(out) + "\n");
