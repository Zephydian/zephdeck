// Thread: draw one thread through every cell, starting at 1 and passing the numbers in order to the
// last one. It moves between neighbouring cells, never crosses itself, and never goes through a wall.
// Every puzzle has exactly one answer (made and checked by scripts/puzzles/thread.mjs).
//
// A daily puzzle (the same for everyone that day; harder through the week) and unlimited practice.
// Drag from 1 (or the thread's end); drag back over the thread to undo steps; click it to cut it there.

const PUZZLES = z.data("puzzles.json");     // level → [{ n, nums: [[cell, number]], walls: [[a, b]], s: the answer's cells }]

// Sounds (Kenney, CC0), played only while game sounds are on (Settings, and this game's speaker).
const SOUND_NAMES = ["cut", "giveup", "hint", "number", "step", "win"];
const sound = (name, volume) => z.sound.play("sounds/" + name + ".wav", { volume: volume == null ? 1 : volume });
const preloadSounds = () => z.sound.preload(SOUND_NAMES.map(n => "sounds/" + n + ".wav"));

const DAILY_POOL = 200;                     // the first 200 of each level are dailies, the rest practice
const DAILY_LEVEL = ["hard", "easy", "easy", "medium", "medium", "medium", "hard"];   // by weekday, Sunday first
const LEVELS = [
  { name: "Daily" },
  { name: "Easy", key: "easy" },
  { name: "Medium", key: "medium" },
  { name: "Hard", key: "hard" },
];
const MAX_UNDO = 200;

let level = 0;
let n = 6, numberAt = new Map(), last = 0, walls = new Set(), path = [], answer = [];
let puzzleKey = "";
let history = [];
let solved = false, solvedTime = 0;
let gaveUp = false, hintsUsed = 0;
let elapsed = 0, runningSince = null;
let dragging = false;
let lastSecond = -1;

// ───────────── Days ─────────────

function today() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

// Days since 1 January 2026, by the person's own calendar (local midnight).
function dayNumber(date) {
  return Math.round((date - new Date(2026, 0, 1)) / 86400000);
}

function hoursToMidnight() {
  const now = new Date(), next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  return Math.max(1, Math.ceil((next - now) / 3600000));
}

// ───────────── Puzzles ─────────────

const edge = (a, b) => (a < b ? a + "-" + b : b + "-" + a);

function load(key, index, puzzle) {
  const p = PUZZLES[key][index];
  n = p.n;
  numberAt = new Map(p.nums);
  last = Math.max(...p.nums.map(x => x[1]));
  walls = new Set(p.walls.map(([a, b]) => edge(a, b)));
  answer = p.s;
  puzzleKey = puzzle;
  const saved = z.storage.get(slot(puzzle));
  if (saved && saved.key === puzzle && Array.isArray(saved.path)) {
    path = saved.path; elapsed = saved.elapsed || 0; solved = !!saved.solved; solvedTime = saved.solvedTime || 0;
    gaveUp = !!saved.gaveUp; hintsUsed = saved.hints || 0;
  } else {
    path = []; elapsed = 0; solved = false; solvedTime = 0; gaveUp = false; hintsUsed = 0;
  }
  history = []; runningSince = null; dragging = false;
  z.overlay(null);
  setActions();
  if (solved) showSolved(); else z.loop.start(250);
  z.redraw();
}

function openDaily() {
  const day = dayNumber(today());
  const key = DAILY_LEVEL[today().getDay()];
  load(key, ((day % DAILY_POOL) + DAILY_POOL) % DAILY_POOL, "daily-" + day);
}

function openPractice() {
  const key = LEVELS[level].key;
  const index = DAILY_POOL + Math.floor(Math.random() * (PUZZLES[key].length - DAILY_POOL));
  load(key, index, "practice-" + key + "-" + index);
}

function open() { if (level === 0) openDaily(); else openPractice(); }

// The daily and practice each keep their own progress, so a practice game never forgets today's daily.
function slot(key) { return key.startsWith("daily-") ? "progress-daily" : "progress-practice"; }

function save() {
  z.storage.set(slot(puzzleKey), { key: puzzleKey, path, elapsed: time(), solved, solvedTime, gaveUp, hints: hintsUsed });
}

// ───────────── Time ─────────────

function time() { return elapsed + (runningSince == null ? 0 : Date.now() - runningSince); }

function startClock() { if (!solved && runningSince == null) runningSince = Date.now(); }

function stopClock() {
  if (runningSince != null) { elapsed += Date.now() - runningSince; runningSince = null; }
}

function clock(ms) {
  const s = Math.floor(ms / 1000);
  return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
}

// ───────────── The thread ─────────────

const start = () => [...numberAt].find(([, k]) => k === 1)[0];

// The number the thread must meet next.
function nextNumber() {
  let k = 1;
  for (const cell of path) if (numberAt.has(cell)) k = numberAt.get(cell) + 1;
  return k;
}

const isNeighbour = (a, b) => (Math.abs(a - b) === 1 && Math.floor(a / n) === Math.floor(b / n)) || Math.abs(a - b) === n;

// One step to cell j: forward onto a free neighbour, or back over the thread.
function step(j) {
  const head = path[path.length - 1];
  if (j === head) return true;
  if (path.length > 1 && j === path[path.length - 2]) { path.pop(); return true; }   // stepping back is silent (B-55)
  const k = path.indexOf(j);
  if (k >= 0) { path.length = k + 1; return true; }        // back to a cell on the thread: cut there
  if (!isNeighbour(head, j) || walls.has(edge(head, j))) return false;
  if (numberAt.has(j) && numberAt.get(j) !== nextNumber()) return false;
  path.push(j);
  // A quiet tick for each step; reaching the next number plucks.
  if (numberAt.has(j)) sound("number"); else sound("step", 0.35);
  return true;
}

// The pointer can skip cells when it moves fast: walk there one cell at a time.
function walkTo(target) {
  for (let guard = 0; guard < n * 2; guard++) {
    const head = path[path.length - 1];
    if (head === target) return;
    if (path.includes(target)) { step(target); return; }
    const hr = Math.floor(head / n), hc = head % n, tr = Math.floor(target / n), tc = target % n;
    const dr = Math.sign(tr - hr), dc = Math.sign(tc - hc);
    // Try the longer direction first, then the other.
    const tries = Math.abs(tr - hr) >= Math.abs(tc - hc) ? [[dr, 0], [0, dc]] : [[0, dc], [dr, 0]];
    let moved = false;
    for (const [a, b] of tries) {
      if (!a && !b) continue;
      if (step((hr + a) * n + (hc + b))) { moved = true; break; }
    }
    if (!moved) return;
  }
}

function remember() {
  history.push(path.slice());
  if (history.length > MAX_UNDO) history.shift();
}

function checkSolved() {
  if (path.length !== n * n || numberAt.get(path[path.length - 1]) !== last) return;
  stopClock();
  solved = true;
  solvedTime = elapsed;
  recordWin();
  sound("win");
  save();
  setActions();
  showSolved();
}

function recordWin() {
  const best = z.storage.get("best") || {};
  const secs = Math.floor(solvedTime / 1000);
  if (!best[n] || secs < best[n]) { best[n] = secs; z.storage.set("best", best); }
  if (puzzleKey.startsWith("daily-")) {
    const day = Number(puzzleKey.slice(6));
    const streak = z.storage.get("streak") || { count: 0, last: null };
    if (streak.last !== day) {
      streak.count = streak.last === day - 1 ? streak.count + 1 : 1;
      streak.last = day;
      z.storage.set("streak", streak);
    }
  }
}

function showSolved() {
  z.loop.stop();
  const best = (z.storage.get("best") || {})[n];
  const parts = [];
  const isDaily = puzzleKey.startsWith("daily-");
  if (isDaily) parts.push("Streak " + (z.storage.get("streak") || { count: 0 }).count);
  if (best) parts.push("best " + clock(best * 1000));
  if (isDaily) parts.push("Next daily in " + hoursToMidnight() + " h");
  if (gaveUp) { parts.length = 0; if (isDaily) parts.push("Streak reset", "Next daily in " + hoursToMidnight() + " h"); }
  else if (hintsUsed) parts.splice(isDaily ? 1 : 0, 0, hintsUsed + (hintsUsed === 1 ? " hint" : " hints"));
  z.overlay({
    title: gaveUp ? "Here’s the solution" : "Solved in " + clock(solvedTime),
    subtitle: parts.join(" · "),
    buttons: [isDaily
      ? { label: "Play practice", prominent: true, action() { level = 2; setMenu(); open(); } }
      : { label: "New puzzle", prominent: true, action() { open(); } }],
  });
}


// ───────────── Hint and Give up ─────────────

// Hint and Give up under the board. Hints are counted on the finished card; giving up shows the
// solution and, on a daily, counts as a loss (the streak starts again).
function setActions() {
  const daily = puzzleKey.startsWith("daily-");
  z.actions([
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !solved, help: "Put the thread right, a few steps further", onPress: useHint },
    { id: "giveUp", label: "Give up", symbol: "eye", enabled: !solved,
      help: daily ? "Show the solution (counts as a loss)" : "Show the solution",
      confirm: daily
        ? { title: "Give up today’s puzzle?", message: "You’ll see the solution. This counts as a loss and resets your streak.", button: "Give Up" }
        : { title: "Give up?", message: "You’ll see the solution.", button: "Give Up" },
      onPress: giveUp },
  ]);
}

function useHint() {
  if (solved) return;
  startClock();
  if (!applyHint()) return;
  sound("hint");
  hintsUsed++;
  save();
  checkSolved();
  z.redraw();
}

function giveUp() {
  if (solved) return;
  stopClock();
  revealSolution();
  sound("giveup");
  solved = true;
  gaveUp = true;
  solvedTime = elapsed;
  if (puzzleKey.startsWith("daily-")) z.storage.set("streak", { count: 0, last: Number(puzzleKey.slice(6)) });
  save();
  setActions();
  showSolved();
  z.redraw();
}

// The thread is kept up to where it's still right, then goes on to the next number (at most 4 steps).
function applyHint() {
  let k = 0;
  while (k < path.length && path[k] === answer[k]) k++;
  if (k === answer.length) return false;
  let end = k + 1;
  while (end < answer.length && end - k < 4 && !numberAt.has(answer[end - 1])) end++;
  remember();
  path = answer.slice(0, end);
  return true;
}

function revealSolution() { path = answer.slice(); }

// ───────────── Moves ─────────────

// ───────────── Layout and drawing ─────────────

function layout() {
  const top = 34, pad = 14;
  const side = Math.min(z.width - pad * 2, z.height - top - pad);
  const size = side / n;
  return { x: (z.width - size * n) / 2, y: top + (z.height - top - pad - size * n) / 2, size };
}

function cellAt(x, y) {
  const L = layout();
  const c = Math.floor((x - L.x) / L.size), r = Math.floor((y - L.y) / L.size);
  return r >= 0 && r < n && c >= 0 && c < n ? r * n + c : -1;
}

function draw(g) {
  const L = layout(), dark = z.theme.dark;
  const line = dark ? "#ffffff22" : "#00000020";
  const wall = dark ? "#f2f2f7" : "#1c1c1e";
  const centre = i => [L.x + (i % n + 0.5) * L.size, L.y + (Math.floor(i / n) + 0.5) * L.size];

  const label = level === 0 ? "Daily · " + ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][today().getDay()] + " · " + n + "×" + n
    : LEVELS[level].name + " · " + n + "×" + n;
  g.text(label, L.x, 16, { size: 13, weight: "medium", color: "secondary" });
  g.text(clock(solved ? solvedTime : time()), L.x + L.size * n, 16, { size: 13, weight: "semibold", color: "text", align: "right", font: "mono" });

  // The grid, with the cells the thread covers tinted.
  g.rect(L.x, L.y, L.size * n, L.size * n, { fill: dark ? "#ffffff0d" : "#00000008", radius: 8 });
  g.save();
  g.alpha(0.18);
  for (const i of path) {
    const x = L.x + (i % n) * L.size, y = L.y + Math.floor(i / n) * L.size;
    g.rect(x, y, L.size, L.size, { fill: "accent" });
  }
  g.restore();
  for (let k = 1; k < n; k++) {
    g.line(L.x + k * L.size, L.y, L.x + k * L.size, L.y + n * L.size, { stroke: line, lineWidth: 1 });
    g.line(L.x, L.y + k * L.size, L.x + n * L.size, L.y + k * L.size, { stroke: line, lineWidth: 1 });
  }
  g.rect(L.x, L.y, L.size * n, L.size * n, { stroke: line, lineWidth: 1, radius: 8 });

  // Walls.
  for (const e of walls) {
    const [a, b] = e.split("-").map(Number);
    const x = L.x + (a % n) * L.size, y = L.y + Math.floor(a / n) * L.size;
    if (b === a + 1) g.line(x + L.size, y, x + L.size, y + L.size, { stroke: wall, lineWidth: 4, cap: "round" });
    else g.line(x, y + L.size, x + L.size, y + L.size, { stroke: wall, lineWidth: 4, cap: "round" });
  }

  // The thread.
  if (path.length > 1) g.path(path.map(centre), { stroke: "accent", lineWidth: L.size * 0.34, cap: "round" });
  if (path.length) {
    const [hx, hy] = centre(path[path.length - 1]);
    g.circle(hx, hy, L.size * 0.24, { fill: "accent" });
  }

  // The numbers.
  for (const [cell, k] of numberAt) {
    const [cx, cy] = centre(cell);
    g.circle(cx, cy, L.size * 0.3, { fill: dark ? "#f2f2f7" : "#1c1c1e" });
    g.text(String(k), cx, cy, { size: L.size * 0.3, weight: "bold", color: dark ? "#1c1c1e" : "#ffffff", align: "center" });
  }
}

// ───────────── Menu ─────────────

function setMenu() {
  z.menu({
    title: "Puzzle",
    items: LEVELS.map(l => l.name),
    selected: level,
    onSelect(i) { level = i; z.storage.set("level", level); open(); },
  });
}

zephydian.game({
  start() {
    preloadSounds();
    const saved = z.storage.get("level");
    if (typeof saved === "number" && saved >= 0 && saved < LEVELS.length) level = saved;
    setMenu();
    const progress = z.storage.get("progress-practice");
    if (level !== 0 && progress && !progress.solved) {
      const [, key, index] = progress.key.split("-");
      if (PUZZLES[key] && PUZZLES[key][Number(index)]) { load(key, Number(index), progress.key); return; }
    }
    open();
  },

  draw,

  tick() {
    if (level === 0 && puzzleKey !== "daily-" + dayNumber(today())) { open(); return; }
    const s = Math.floor(time() / 1000);
    if (s !== lastSecond) { lastSecond = s; z.redraw(); }
  },

  pointer(e) {
    if (solved) return;
    const i = cellAt(e.x, e.y);
    if (e.type === "down") {
      if (i < 0) return;
      if (!path.length) {
        if (i !== start()) return;
        remember();
        path = [i];
      } else if (path.includes(i)) {
        remember();
        // Click the thread: it's cut there (one soft click, B-55), and goes on from there.
        if (path.indexOf(i) < path.length - 1) sound("cut", 0.5);
        path.length = path.indexOf(i) + 1;
      } else {
        return;
      }
      startClock();
      dragging = true;
    } else if (e.type === "move" && dragging) {
      if (i >= 0) walkTo(i);
    } else if (e.type === "up") {
      if (dragging) { dragging = false; save(); checkSolved(); }
    }
    z.redraw();
  },

  key(e) {
    if (solved) return false;
    const moves = { ArrowLeft: [0, -1], ArrowRight: [0, 1], ArrowUp: [-1, 0], ArrowDown: [1, 0] };
    if (!moves[e.key]) return false;
    if (!path.length) { remember(); path = [start()]; }
    const head = path[path.length - 1], [dr, dc] = moves[e.key];
    const r = Math.floor(head / n) + dr, c = head % n + dc;
    if (r < 0 || r >= n || c < 0 || c >= n) return true;
    remember();
    startClock();
    step(r * n + c);
    save();
    checkSolved();
    z.redraw();
    return true;
  },

  undo() {
    if (solved || !history.length) return false;
    path = history.pop();
    save();
    z.redraw();
    return true;
  },

  pause() { stopClock(); dragging = false; save(); },

  resume() {
    preloadSounds();
    if (level === 0 && puzzleKey !== "daily-" + dayNumber(today())) open();
    z.redraw();
  },
});
