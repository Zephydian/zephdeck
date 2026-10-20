// Makes Weave puzzles: a 6×6 grid of letters made of hidden words on a theme. Each word runs through
// neighbouring cells (up, down, left or right) and every cell belongs to exactly one word.
//
//   node scripts/puzzles/weave.mjs themes.txt > packs/games/weave/assets/puzzles.json
//
// themes.txt has one theme per line: "Theme | word word word …" with more words than needed;
// the script picks 5 to 7 of them whose letters add up to exactly 36, then lays them out as paths.
// A puzzle is { t: theme, g: the 36 letters row by row, w: [[word, [cells in order]], …] }.
// The output is the same every run (a fixed seed).

import { readFileSync } from "node:fs";

const N = 6, CELLS = N * N;
let seed = 20261025;
const rand = () => {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

const neighbours = i => {
  const r = Math.floor(i / N), c = i % N, out = [];
  if (r > 0) out.push(i - N);
  if (r < N - 1) out.push(i + N);
  if (c > 0) out.push(i - 1);
  if (c < N - 1) out.push(i + 1);
  return out;
};

// Every group of empty cells must be fillable by some of the words still to place.
function fillable(owner, lengths) {
  const seen = new Uint8Array(CELLS);
  for (let i = 0; i < CELLS; i++) {
    if (owner[i] >= 0 || seen[i]) continue;
    let size = 0;
    const stack = [i];
    seen[i] = 1;
    while (stack.length) {
      const j = stack.pop();
      size++;
      for (const k of neighbours(j)) if (owner[k] < 0 && !seen[k]) { seen[k] = 1; stack.push(k); }
    }
    if (size < Math.min(...lengths)) return false;
  }
  return true;
}

// Lays the words as paths: each one starts at the first empty cell (reading order) and winds on.
function layout(words) {
  const owner = new Array(CELLS).fill(-1), paths = [];
  let steps = 0;
  const place = left => {
    if (++steps > 200000) return false;
    if (!left.length) return true;
    const start = owner.indexOf(-1);
    for (const k of shuffle(left.slice())) {
      const len = words[k].length, path = [start];
      owner[start] = k;
      const grow = () => {
        if (path.length === len) {
          const rest = left.filter(x => x !== k);
          if (rest.length && !fillable(owner, rest.map(x => words[x].length))) return false;
          paths[k] = path.slice();
          return place(rest);
        }
        for (const j of shuffle(neighbours(path[path.length - 1]))) {
          if (owner[j] >= 0) continue;
          owner[j] = k; path.push(j);
          if (grow()) return true;
          path.pop(); owner[j] = -1;
        }
        return false;
      };
      if (grow()) return true;
      owner[start] = -1;
    }
    return false;
  };
  if (!place(words.map((_, k) => k))) return null;
  // Read half the words backwards along their paths, so they don't all start top-left.
  return paths.map((p, k) => (rand() < 0.5 ? p.slice().reverse() : p));
}

// 5–7 words whose letters add up to 36, chosen at random among the ones that fit.
function pick(words) {
  const options = [];
  const go = (i, chosen, total) => {
    if (total === CELLS && chosen.length >= 5) { options.push(chosen.slice()); return; }
    if (i === words.length || total >= CELLS || chosen.length === 7 || options.length > 500) return;
    chosen.push(i); go(i + 1, chosen, total + words[i].length); chosen.pop();
    go(i + 1, chosen, total);
  };
  go(0, [], 0);
  return options.length ? options[Math.floor(rand() * options.length)].map(i => words[i]) : null;
}

const lines = readFileSync(process.argv[2], "utf8").split("\n").map(l => l.trim()).filter(Boolean);
const out = [], problems = [];
for (const [n, line] of lines.entries()) {
  const [theme, list] = line.split("|").map(s => s.trim());
  const words = [...new Set(list.toLowerCase().split(/\s+/))];
  if (words.some(w => !/^[a-z]{3,10}$/.test(w))) { problems.push(`line ${n + 1}: words must be 3–10 letters a–z (${theme})`); continue; }
  const chosen = pick(words);
  if (!chosen) { problems.push(`line ${n + 1}: no 5–7 words add up to 36 letters (${theme})`); continue; }
  let paths = null;
  for (let tries = 0; tries < 20 && !paths; tries++) paths = layout(chosen);
  if (!paths) { problems.push(`line ${n + 1}: couldn't lay out the words (${theme})`); continue; }
  const grid = new Array(CELLS);
  chosen.forEach((w, k) => paths[k].forEach((cell, j) => { grid[cell] = w[j]; }));
  out.push({ t: theme, g: grid.join(""), w: chosen.map((w, k) => [w, paths[k]]) });
}
for (const p of problems) process.stderr.write("PROBLEM " + p + "\n");
process.stderr.write(`${out.length} puzzles\n`);
if (problems.length) process.exit(1);
// Mixed up, so similar themes don't come on neighbouring days.
process.stdout.write(JSON.stringify(shuffle(out)) + "\n");
