// Dusk: fill the grid with suns and moons. Every row and column has as many suns as moons, never
// three alike next to each other, and "=" / "×" between two cells means same / different.
// Every puzzle has exactly one solution (made and checked by scripts/puzzles/dusk.mjs).
//
// A daily puzzle (the same for everyone that day; harder through the week) and unlimited practice.
// Click a cell: sun, then moon, then empty (right-click goes the other way).

const PUZZLES = z.data("puzzles.json");     // level → [{ g, h, v, s: the answer }]

// Sounds (Kenney, CC0), played only while game sounds are on (Settings, and this game's speaker).
const SOUND_NAMES = ["clear", "giveup", "hint", "mistake", "moon", "sun", "win"];
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
const EMPTY = 0, SUN = 1, MOON = 2;
const MAX_UNDO = 300;

let level = 0;
let n = 6, given = [], cells = [], hLinks = [], vLinks = [], answer = [];
let puzzleKey = "";
let history = [];
let solved = false, solvedTime = 0;
let gaveUp = false, hintsUsed = 0;
let elapsed = 0, runningSince = null;
let cursor = 0, showCursor = false;
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

function load(key, index, puzzle) {
  const p = PUZZLES[key][index];
  n = Math.round(Math.sqrt(p.g.length));
  given = [...p.g].map(ch => ".sm".indexOf(ch));
  hLinks = [...p.h];
  vLinks = [...p.v];
  answer = [...p.s].map(ch => ".sm".indexOf(ch));
  puzzleKey = puzzle;
  const saved = z.storage.get(slot(puzzle));
  if (saved && saved.key === puzzle && saved.cells.length === n * n) {
    cells = saved.cells; elapsed = saved.elapsed || 0; solved = !!saved.solved; solvedTime = saved.solvedTime || 0;
    gaveUp = !!saved.gaveUp; hintsUsed = saved.hints || 0;
  } else {
    cells = given.slice(); elapsed = 0; solved = false; solvedTime = 0; gaveUp = false; hintsUsed = 0;
  }
  history = []; runningSince = null; cursor = 0; showCursor = false;
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

// Cells and links that break a rule, and rows/columns with too many of one kind.
function mistakes() {
  const bad = new Set(), badH = new Set(), badV = new Set(), lines = new Set();
  const at = (r, c) => cells[r * n + c];
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      const i = r * n + c, v = cells[i];
      if (!v) continue;
      if (c + 2 < n && at(r, c + 1) === v && at(r, c + 2) === v) [i, i + 1, i + 2].forEach(k => bad.add(k));
      if (r + 2 < n && at(r + 1, c) === v && at(r + 2, c) === v) [i, i + n, i + 2 * n].forEach(k => bad.add(k));
      if (c < n - 1 && hLinks[i] !== "." && cells[i + 1]) {
        if ((hLinks[i] === "=") !== (cells[i + 1] === v)) { badH.add(i); bad.add(i); bad.add(i + 1); }
      }
      if (r < n - 1 && vLinks[i] !== "." && cells[i + n]) {
        if ((vLinks[i] === "=") !== (cells[i + n] === v)) { badV.add(i); bad.add(i); bad.add(i + n); }
      }
    }
  }
  // More than half of one kind in a row or column.
  for (let k = 0; k < n; k++) {
    for (const v of [SUN, MOON]) {
      let row = 0, col = 0;
      for (let j = 0; j < n; j++) { if (at(k, j) === v) row++; if (at(j, k) === v) col++; }
      if (row > n / 2) { lines.add("r" + k); for (let j = 0; j < n; j++) if (at(k, j) === v) bad.add(k * n + j); }
      if (col > n / 2) { lines.add("c" + k); for (let j = 0; j < n; j++) if (at(j, k) === v) bad.add(j * n + k); }
    }
  }
  return { bad, badH, badV, lines };
}

function checkSolved() {
  if (cells.some(v => !v)) return;
  const m = mistakes();
  if (m.bad.size) return;
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
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !solved, help: "Fix a wrong cell, or fill one in", onPress: useHint },
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

// A wrong sun or moon is put right first; otherwise an empty cell is filled in.
function applyHint() {
  let i = cells.findIndex((v, k) => v && !given[k] && v !== answer[k]);
  if (i < 0) i = cells.findIndex(v => !v);
  if (i < 0) return false;
  history.push([i, cells[i]]);
  cells[i] = answer[i];
  return true;
}

function revealSolution() { cells = answer.slice(); }

// ───────────── Moves ─────────────

function cycle(i, backwards) {
  if (solved || given[i]) return;
  startClock();
  history.push([i, cells[i]]);
  if (history.length > MAX_UNDO) history.shift();
  cells[i] = (cells[i] + (backwards ? 2 : 1)) % 3;
  if (!cells[i]) sound("clear", 0.6);
  else sound(mistakes().bad.has(i) ? "mistake" : cells[i] === SUN ? "sun" : "moon");
  save();
  checkSolved();
  z.redraw();
}

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
  const red = dark ? "#ff6961" : "#d70015";
  const sun = dark ? "#ffb340" : "#f08a00";
  const moon = dark ? "#7fb2ff" : "#3a78d8";
  const plain = dark ? "#ffffff10" : "#00000008";
  const fixed = dark ? "#ffffff24" : "#0000001a";
  const line = dark ? "#ffffff22" : "#00000020";
  const m = mistakes();

  const label = level === 0 ? "Daily · " + ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][today().getDay()] + " · " + n + "×" + n
    : LEVELS[level].name + " · " + n + "×" + n;
  g.text(label, L.x, 16, { size: 13, weight: "medium", color: "secondary" });
  g.text(clock(solved ? solvedTime : time()), L.x + L.size * n, 16, { size: 13, weight: "semibold", color: "text", align: "right", font: "mono" });

  // Cells: a darker background for the fixed ones, a soft red one for mistakes.
  for (let i = 0; i < n * n; i++) {
    const x = L.x + (i % n) * L.size, y = L.y + Math.floor(i / n) * L.size;
    g.rect(x + 1.5, y + 1.5, L.size - 3, L.size - 3, { fill: given[i] ? fixed : plain, radius: 6 });
    if (m.bad.has(i)) {
      g.save();
      g.clip(x + 1.5, y + 1.5, L.size - 3, L.size - 3, { radius: 6 });
      for (let k = -L.size; k < L.size; k += 7) g.line(x + k, y + L.size, x + k + L.size, y, { stroke: red + "40", lineWidth: 2 });
      g.restore();
    }
    const cx = x + L.size / 2, cy = y + L.size / 2;
    if (cells[i] === SUN) g.symbol("sun.max.fill", cx, cy, L.size * 0.5, { color: m.bad.has(i) ? red : sun });
    if (cells[i] === MOON) g.symbol("moon.fill", cx, cy, L.size * 0.44, { color: m.bad.has(i) ? red : moon });
  }
  g.rect(L.x, L.y, L.size * n, L.size * n, { stroke: line, lineWidth: 1, radius: 8 });

  // = and × on the line between two cells.
  const badge = (cx, cy, kind, wrong) => {
    const r = Math.max(7, L.size * 0.17);
    g.circle(cx, cy, r, { fill: z.theme.background });
    g.circle(cx, cy, r, { stroke: wrong ? red : line, lineWidth: 1 });
    g.text(kind === "=" ? "=" : "×", cx, cy - 0.5, { size: r * 1.35, weight: "bold", color: wrong ? red : "secondary", align: "center" });
  };
  for (let i = 0; i < n * n; i++) {
    const r = Math.floor(i / n), c = i % n;
    if (c < n - 1 && hLinks[i] !== ".") badge(L.x + (c + 1) * L.size, L.y + (r + 0.5) * L.size, hLinks[i], m.badH.has(i));
    if (r < n - 1 && vLinks[i] !== ".") badge(L.x + (c + 0.5) * L.size, L.y + (r + 1) * L.size, vLinks[i], m.badV.has(i));
  }

  if (showCursor && !solved) {
    const x = L.x + (cursor % n) * L.size, y = L.y + Math.floor(cursor / n) * L.size;
    g.rect(x + 2, y + 2, L.size - 4, L.size - 4, { stroke: "accent", lineWidth: 2.5, radius: 6 });
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

zephdeck.game({
  start() {
    preloadSounds();
    const saved = z.storage.get("level");
    if (typeof saved === "number" && saved >= 0 && saved < LEVELS.length) level = saved;
    setMenu();
    // Pick up an unfinished practice puzzle where it was left; otherwise today's daily or a new one.
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

  click(e) {
    const i = cellAt(e.x, e.y);
    if (i < 0) return;
    showCursor = false;
    cycle(i, e.button === "right");
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
    if ((e.key === " " || e.key === "Enter") && showCursor) { cycle(cursor, e.shift); return true; }
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
    preloadSounds();
    if (level === 0 && puzzleKey !== "daily-" + dayNumber(today())) open();
    z.redraw();
  },
});
