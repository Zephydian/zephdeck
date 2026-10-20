// Crowns: place one crown in every row, column and coloured region. Crowns never touch, not even
// diagonally. Every puzzle has exactly one solution (made and checked by scripts/puzzles/crowns.mjs).
//
// A daily puzzle (the same for everyone that day; harder through the week) and unlimited practice.
// Click a cell: × (a note), then a crown, then empty again. Drag to put × on many cells.

const PUZZLES = z.data("puzzles.json");     // size → [{ r: one region letter per cell, s: the crown's column per row }]
const DAILY_POOL = 200;                     // the first 200 of each size are dailies, the rest practice
const DAILY_SIZE = [9, 6, 7, 7, 8, 8, 9];   // by weekday, Sunday first: Monday easiest, weekends hardest
const LEVELS = [
  { name: "Daily" },
  { name: "Easy", sizes: [6] },
  { name: "Medium", sizes: [7, 8] },
  { name: "Hard", sizes: [9] },
];
const EMPTY = 0, MARK = 1, CROWN = 2;
const MAX_UNDO = 300;

// Soft region colours, our own palette, in light and dark versions.
const LIGHT = ["#f6c9cf", "#bfdcf5", "#cfe6c4", "#f3e0b5", "#dccdf0", "#f7d2b8", "#bfe8de", "#f2eaa8", "#d3d9e2", "#f4b8b0", "#b5dfe3"];
const DARK = ["#7a4a52", "#3f5f7d", "#4f6b45", "#7a6538", "#5e4d7a", "#7d5a40", "#3e6f63", "#6f6a33", "#4f5866", "#7d4a42", "#3c6a70"];

let level = 0;
let n = 6, regions = [], cells = [], answer = [];
let puzzleKey = "";
let history = [];
let solved = false, solvedTime = 0;
let gaveUp = false, hintsUsed = 0;
let elapsed = 0, runningSince = null;
let cursor = 0, showCursor = false;
let drag = null;                            // { marking: true } while dragging × across cells
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

function load(size, index, key) {
  n = size;
  const p = PUZZLES[String(size)][index];
  regions = [...p.r].map(ch => ch.charCodeAt(0) - 97);
  answer = p.s;
  puzzleKey = key;
  const saved = z.storage.get(slot(key));
  if (saved && saved.key === key && saved.cells.length === n * n) {
    cells = saved.cells; elapsed = saved.elapsed || 0; solved = !!saved.solved; solvedTime = saved.solvedTime || 0;
    gaveUp = !!saved.gaveUp; hintsUsed = saved.hints || 0;
  } else {
    cells = new Array(n * n).fill(EMPTY); elapsed = 0; solved = false; solvedTime = 0; gaveUp = false; hintsUsed = 0;
  }
  history = []; runningSince = null; cursor = 0; showCursor = false; drag = null;
  z.overlay(null);
  setActions();
  if (solved) showSolved(); else z.loop.start(250);
  z.redraw();
}

function openDaily() {
  const day = dayNumber(today());
  const size = DAILY_SIZE[today().getDay()];
  load(size, ((day % DAILY_POOL) + DAILY_POOL) % DAILY_POOL, "daily-" + day);
}

function openPractice() {
  const sizes = LEVELS[level].sizes;
  const size = sizes[Math.floor(Math.random() * sizes.length)];
  const pool = PUZZLES[String(size)].length - DAILY_POOL;
  const index = DAILY_POOL + Math.floor(Math.random() * pool);
  load(size, index, "practice-" + size + "-" + index);
}

function open() { if (level === 0) openDaily(); else openPractice(); }

// The daily and practice each keep their own progress, so a practice game never forgets today's daily.
function slot(key) { return key.startsWith("daily-") ? "progress-daily" : "progress-practice"; }

function save() {
  z.storage.set(slot(puzzleKey), { key: puzzleKey, cells, elapsed: time(), solved, solvedTime, gaveUp, hints: hintsUsed });
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

// ───────────── Rules ─────────────

// Every crown that clashes with another, and the rows, columns and regions where they clash.
function conflicts() {
  const crowns = [];
  cells.forEach((v, i) => { if (v === CROWN) crowns.push(i); });
  const bad = new Set(), rows = new Set(), cols = new Set(), regs = new Set();
  for (let a = 0; a < crowns.length; a++) {
    for (let b = a + 1; b < crowns.length; b++) {
      const i = crowns[a], j = crowns[b];
      const ri = Math.floor(i / n), ci = i % n, rj = Math.floor(j / n), cj = j % n;
      let clash = false;
      if (ri === rj) { rows.add(ri); clash = true; }
      if (ci === cj) { cols.add(ci); clash = true; }
      if (regions[i] === regions[j]) { regs.add(regions[i]); clash = true; }
      if (Math.abs(ri - rj) <= 1 && Math.abs(ci - cj) <= 1) clash = true;
      if (clash) { bad.add(i); bad.add(j); }
    }
  }
  return { bad, rows, cols, regs, count: crowns.length };
}

function checkSolved() {
  const c = conflicts();
  if (c.count !== n || c.bad.size) return;
  stopClock();
  solved = true;
  solvedTime = elapsed;
  recordWin();
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
  if (isDaily) {
    const streak = z.storage.get("streak") || { count: 0 };
    parts.push("Streak " + streak.count);
  }
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
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !solved, help: "Fix a wrong crown, or place a right one", onPress: useHint },
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
  hintsUsed++;
  save();
  checkSolved();
  z.redraw();
}

function giveUp() {
  if (solved) return;
  stopClock();
  revealSolution();
  solved = true;
  gaveUp = true;
  solvedTime = elapsed;
  if (puzzleKey.startsWith("daily-")) z.storage.set("streak", { count: 0, last: Number(puzzleKey.slice(6)) });
  save();
  setActions();
  showSolved();
  z.redraw();
}

// A wrong crown is taken away first; otherwise one right crown goes in.
function applyHint() {
  for (let i = 0; i < n * n; i++) {
    if (cells[i] === CROWN && answer[Math.floor(i / n)] !== i % n) { setCell(i, EMPTY); return true; }
  }
  for (let r = 0; r < n; r++) {
    const i = r * n + answer[r];
    if (cells[i] !== CROWN) { setCell(i, CROWN); return true; }
  }
  return false;
}

function revealSolution() {
  cells = new Array(n * n).fill(EMPTY);
  answer.forEach((c, r) => { cells[r * n + c] = CROWN; });
}

// ───────────── Moves ─────────────

function setCell(i, v) {
  if (cells[i] === v) return false;
  history.push([i, cells[i]]);
  if (history.length > MAX_UNDO) history.shift();
  cells[i] = v;
  return true;
}

function cycle(i) {
  if (solved) return;
  startClock();
  setCell(i, (cells[i] + 1) % 3);
  save();
  checkSolved();
  z.redraw();
}

function mark(i) {
  if (solved || cells[i] !== EMPTY) return;
  setCell(i, MARK);
  save();
  z.redraw();
}

// ───────────── Layout and drawing ─────────────

function layout() {
  const top = 34, pad = 14;
  const side = Math.min(z.width - pad * 2, z.height - top - pad);
  const size = side / n;
  return { x: (z.width - size * n) / 2, y: top + (z.height - top - pad - size * n) / 2, size, top };
}

function cellAt(x, y) {
  const L = layout();
  const c = Math.floor((x - L.x) / L.size), r = Math.floor((y - L.y) / L.size);
  return r >= 0 && r < n && c >= 0 && c < n ? r * n + c : -1;
}

function draw(g) {
  const L = layout(), dark = z.theme.dark, palette = dark ? DARK : LIGHT;
  const red = dark ? "#ff6961" : "#d70015";
  const line = dark ? "#00000066" : "#00000022";
  const wall = dark ? "#0b0b0d" : "#2b2b30";
  const c = conflicts();

  // The puzzle and the time.
  const label = level === 0 ? "Daily · " + ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][today().getDay()] + " · " + n + "×" + n
    : LEVELS[level].name + " · " + n + "×" + n;
  g.text(label, L.x, 16, { size: 13, weight: "medium", color: "secondary" });
  g.text(clock(solved ? solvedTime : time()), L.x + L.size * n, 16, { size: 13, weight: "semibold", color: "text", align: "right", font: "mono" });

  g.save();
  g.clip(L.x, L.y, L.size * n, L.size * n, { radius: 8 });
  for (let i = 0; i < n * n; i++) {
    const r = Math.floor(i / n), col = i % n;
    const x = L.x + col * L.size, y = L.y + r * L.size;
    g.rect(x, y, L.size, L.size, { fill: palette[regions[i] % palette.length] });
    // A clash: soft red stripes over the row, column or region.
    if (c.rows.has(r) || c.cols.has(col) || c.regs.has(regions[i])) {
      g.save();
      g.clip(x, y, L.size, L.size);
      for (let k = -L.size; k < L.size; k += 7) g.line(x + k, y + L.size, x + k + L.size, y, { stroke: red + "40", lineWidth: 2 });
      g.restore();
    }
  }
  // Thin lines between cells, thick walls between regions.
  for (let k = 1; k < n; k++) {
    g.line(L.x + k * L.size, L.y, L.x + k * L.size, L.y + n * L.size, { stroke: line, lineWidth: 1 });
    g.line(L.x, L.y + k * L.size, L.x + n * L.size, L.y + k * L.size, { stroke: line, lineWidth: 1 });
  }
  for (let i = 0; i < n * n; i++) {
    const r = Math.floor(i / n), col = i % n;
    const x = L.x + col * L.size, y = L.y + r * L.size;
    if (col < n - 1 && regions[i] !== regions[i + 1]) g.line(x + L.size, y, x + L.size, y + L.size, { stroke: wall, lineWidth: 2.5, cap: "round" });
    if (r < n - 1 && regions[i] !== regions[i + n]) g.line(x, y + L.size, x + L.size, y + L.size, { stroke: wall, lineWidth: 2.5, cap: "round" });
  }
  g.restore();
  g.rect(L.x, L.y, L.size * n, L.size * n, { stroke: wall, lineWidth: 2.5, radius: 8 });

  // Marks and crowns.
  for (let i = 0; i < n * n; i++) {
    const cx = L.x + (i % n + 0.5) * L.size, cy = L.y + (Math.floor(i / n) + 0.5) * L.size;
    if (cells[i] === MARK) {
      const d = L.size * 0.12;
      const ink = dark ? "#ffffffaa" : "#00000088";
      g.line(cx - d, cy - d, cx + d, cy + d, { stroke: ink, lineWidth: 1.6, cap: "round" });
      g.line(cx - d, cy + d, cx + d, cy - d, { stroke: ink, lineWidth: 1.6, cap: "round" });
    } else if (cells[i] === CROWN) {
      g.symbol("crown.fill", cx, cy, L.size * 0.5, { color: c.bad.has(i) ? red : (dark ? "#ffffff" : "#1c1c1e") });
    }
  }

  // The keyboard cursor, once the arrow keys are used.
  if (showCursor && !solved) {
    const x = L.x + (cursor % n) * L.size, y = L.y + Math.floor(cursor / n) * L.size;
    g.rect(x + 2, y + 2, L.size - 4, L.size - 4, { stroke: "accent", lineWidth: 2.5, radius: 5 });
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
    const saved = z.storage.get("level");
    if (typeof saved === "number" && saved >= 0 && saved < LEVELS.length) level = saved;
    setMenu();
    // Pick up an unfinished puzzle where it was left; otherwise today's daily or a new practice one.
    const progress = z.storage.get("progress-practice");
    if (level !== 0 && progress && progress.key.startsWith("practice-") && !progress.solved) {
      const [, size, index] = progress.key.split("-").map(Number);
      load(size, index, progress.key);
    } else {
      open();
    }
  },

  draw,

  tick() {
    // A new day while the daily is open: it moves on to the new daily.
    if (level === 0 && puzzleKey !== "daily-" + dayNumber(today())) { open(); return; }
    const s = Math.floor(time() / 1000);
    if (s !== lastSecond) { lastSecond = s; z.redraw(); }
  },

  pointer(e) {
    if (solved) return;
    const i = cellAt(e.x, e.y);
    if (e.type === "down") {
      if (i < 0) return;
      showCursor = false;
      drag = { from: i, marking: false };
      cycle(i);
    } else if (e.type === "move" && drag) {
      if (i < 0 || i === drag.from && !drag.marking) return;
      // Dragging off the first cell lays × on every empty cell the pointer passes.
      if (!drag.marking) {
        drag.marking = true;
        if (cells[drag.from] === MARK || cells[drag.from] === EMPTY) mark(drag.from);
      }
      startClock();
      mark(i);
    } else if (e.type === "up") {
      drag = null;
    }
  },

  key(e) {
    if (solved) return false;
    const r = Math.floor(cursor / n), c = cursor % n;
    const moves = { ArrowLeft: [0, -1], ArrowRight: [0, 1], ArrowUp: [-1, 0], ArrowDown: [1, 0] };
    if (moves[e.key]) {
      const [dr, dc] = moves[e.key];
      if (showCursor) cursor = Math.min(n - 1, Math.max(0, r + dr)) * n + Math.min(n - 1, Math.max(0, c + dc));
      showCursor = true;
      z.redraw();
      return true;
    }
    if ((e.key === " " || e.key === "Enter") && showCursor) { cycle(cursor); return true; }
    return false;
  },

  undo() {
    if (solved || !history.length) return false;
    const [i, v] = history.pop();
    cells[i] = v;
    save();
    z.redraw();
    return true;
  },

  pause() { stopClock(); save(); },

  resume() {
    if (level === 0 && puzzleKey !== "daily-" + dayNumber(today())) open();
    z.redraw();
  },
});
