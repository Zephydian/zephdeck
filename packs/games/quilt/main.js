// Quilt: split the grid into rectangles (patches). Each patch holds exactly one clue; the clue's
// number is its area, and its mark is its shape: square, tall, wide, or any. Every puzzle has exactly
// one answer (made and checked by scripts/puzzles/quilt.mjs).
//
// A daily puzzle (the same for everyone that day; harder through the week) and unlimited practice.
// Drag from one corner to the other to lay a patch; click a patch to take it away.

const PUZZLES = z.data("puzzles.json");     // level → [{ n, clues: [[cell, area, shape], …], s: [[r, c, w, h], …] }]

// Sounds (Kenney, CC0), played only while game sounds are on (Settings, and this game's speaker).
const SOUND_NAMES = ["giveup", "hint", "lay", "remove", "win", "wrong"];
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

// Soft patch colours (the same palette as Crowns), in light and dark versions.
const LIGHT = ["#f6c9cf", "#bfdcf5", "#cfe6c4", "#f3e0b5", "#dccdf0", "#f7d2b8", "#bfe8de", "#f2eaa8", "#d3d9e2", "#f4b8b0", "#b5dfe3"];
const DARK = ["#7a4a52", "#3f5f7d", "#4f6b45", "#7a6538", "#5e4d7a", "#7d5a40", "#3e6f63", "#6f6a33", "#4f5866", "#7d4a42", "#3c6a70"];

let level = 0;
let n = 5, clues = [], patches = [], answer = [];
let puzzleKey = "";
let history = [];
let solved = false, solvedTime = 0;
let gaveUp = false, hintsUsed = 0;
let elapsed = 0, runningSince = null;
let drag = null;                            // { from, to } cells while drawing a patch
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
  n = p.n;
  clues = p.clues.map(([cell, area, shape]) => ({ cell, area, shape }));
  answer = p.s.map(([r, c, w, h]) => ({ r, c, w, h }));
  puzzleKey = puzzle;
  const saved = z.storage.get(slot(puzzle));
  if (saved && saved.key === puzzle && Array.isArray(saved.patches)) {
    patches = saved.patches; elapsed = saved.elapsed || 0; solved = !!saved.solved; solvedTime = saved.solvedTime || 0;
    gaveUp = !!saved.gaveUp; hintsUsed = saved.hints || 0;
  } else {
    patches = []; elapsed = 0; solved = false; solvedTime = 0; gaveUp = false; hintsUsed = 0;
  }
  history = []; runningSince = null; drag = null;
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
  z.storage.set(slot(puzzleKey), { key: puzzleKey, patches, elapsed: time(), solved, solvedTime, gaveUp, hints: hintsUsed });
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

const inside = (p, cell) => {
  const r = Math.floor(cell / n), c = cell % n;
  return r >= p.r && r < p.r + p.h && c >= p.c && c < p.c + p.w;
};

const shapeOf = (w, h) => (w === h ? "s" : h > w ? "t" : "w");

// The clue a patch holds (its index), or -1 when it holds none or several, plus whether it's right.
function check(p) {
  const held = clues.map((cl, k) => inside(p, cl.cell) ? k : -1).filter(k => k >= 0);
  if (held.length !== 1) return { clue: held.length ? held[0] : -1, ok: false };
  const cl = clues[held[0]];
  const ok = p.w * p.h === cl.area && (cl.shape === "a" || shapeOf(p.w, p.h) === cl.shape);
  return { clue: held[0], ok };
}

function checkSolved() {
  const covered = patches.reduce((s, p) => s + p.w * p.h, 0);
  if (covered !== n * n || !patches.every(p => check(p).ok)) return;
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
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !solved, help: "Take away a wrong patch, or lay a right one", onPress: useHint },
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

const samePatch = (a, b) => a.r === b.r && a.c === b.c && a.w === b.w && a.h === b.h;

// A wrong patch is taken away first; otherwise one right patch is laid (the smallest missing one).
function applyHint() {
  const wrongPatch = patches.findIndex(p => !answer.some(a => samePatch(a, p)));
  if (wrongPatch >= 0) { remember(); patches.splice(wrongPatch, 1); return true; }
  const missing = answer.filter(a => !patches.some(p => samePatch(a, p))).sort((a, b) => a.w * a.h - b.w * b.h);
  if (!missing.length) return false;
  remember();
  patches.push(Object.assign({}, missing[0]));
  return true;
}

function revealSolution() { patches = answer.map(a => Object.assign({}, a)); }

// ───────────── Moves ─────────────

function remember() {
  history.push(patches.map(p => Object.assign({}, p)));
  if (history.length > MAX_UNDO) history.shift();
}

const overlaps = (a, b) => a.r < b.r + b.h && b.r < a.r + a.h && a.c < b.c + b.w && b.c < a.c + a.w;

function rectFrom(a, b) {
  const r1 = Math.floor(a / n), c1 = a % n, r2 = Math.floor(b / n), c2 = b % n;
  return { r: Math.min(r1, r2), c: Math.min(c1, c2), h: Math.abs(r1 - r2) + 1, w: Math.abs(c1 - c2) + 1 };
}

// A new patch takes the place of any it overlaps.
function lay(p) {
  remember();
  patches = patches.filter(q => !overlaps(p, q)).concat([p]);
  // A patch that breaks a rule (no clue, two clues, wrong size or shape) sounds wrong.
  sound(check(p).ok ? "lay" : "wrong");
  save();
  checkSolved();
}

function removeAt(cell) {
  const k = patches.findIndex(p => inside(p, cell));
  if (k < 0) return;
  remember();
  patches.splice(k, 1);
  sound("remove", 0.7);
  save();
}

// ───────────── Layout and drawing ─────────────

function layout() {
  const top = 34, pad = 14;
  const side = Math.min(z.width - pad * 2, z.height - top - pad);
  const size = side / n;
  return { x: (z.width - size * n) / 2, y: top + (z.height - top - pad - size * n) / 2, size };
}

function cellAt(x, y, clamp) {
  const L = layout();
  let c = Math.floor((x - L.x) / L.size), r = Math.floor((y - L.y) / L.size);
  if (clamp) { c = Math.min(n - 1, Math.max(0, c)); r = Math.min(n - 1, Math.max(0, r)); }
  return r >= 0 && r < n && c >= 0 && c < n ? r * n + c : -1;
}

// The clue's shape mark: a small outline of a square, a tall or a wide rectangle, or a diamond for any.
function shapeMark(g, cx, cy, s, shape, color) {
  if (shape === "a") {
    g.path([[cx, cy - s * 0.55], [cx + s * 0.55, cy], [cx, cy + s * 0.55], [cx - s * 0.55, cy]], { stroke: color, lineWidth: 1.4, closed: true });
    return;
  }
  const [w, h] = shape === "s" ? [s * 0.8, s * 0.8] : shape === "t" ? [s * 0.55, s] : [s, s * 0.55];
  g.rect(cx - w / 2, cy - h / 2, w, h, { stroke: color, lineWidth: 1.4, radius: 1.5 });
}

function draw(g) {
  const L = layout(), dark = z.theme.dark, palette = dark ? DARK : LIGHT;
  const red = dark ? "#ff6961" : "#d70015";
  const line = dark ? "#ffffff22" : "#00000020";
  const ink = dark ? "#ffffff" : "#1c1c1e";

  const label = level === 0 ? "Daily · " + ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][today().getDay()] + " · " + n + "×" + n
    : LEVELS[level].name + " · " + n + "×" + n;
  g.text(label, L.x, 16, { size: 13, weight: "medium", color: "secondary" });
  g.text(clock(solved ? solvedTime : time()), L.x + L.size * n, 16, { size: 13, weight: "semibold", color: "text", align: "right", font: "mono" });

  // The empty grid.
  g.rect(L.x, L.y, L.size * n, L.size * n, { fill: dark ? "#ffffff0d" : "#00000008", radius: 8 });
  for (let k = 1; k < n; k++) {
    g.line(L.x + k * L.size, L.y + 4, L.x + k * L.size, L.y + n * L.size - 4, { stroke: line, lineWidth: 1 });
    g.line(L.x + 4, L.y + k * L.size, L.x + n * L.size - 4, L.y + k * L.size, { stroke: line, lineWidth: 1 });
  }

  // Patches: the colour of the clue they hold (grey without one), a red outline when wrong.
  for (const p of patches) {
    const { clue, ok } = check(p);
    const x = L.x + p.c * L.size + 2, y = L.y + p.r * L.size + 2, w = p.w * L.size - 4, h = p.h * L.size - 4;
    g.rect(x, y, w, h, { fill: clue >= 0 ? palette[clue % palette.length] : (dark ? "#ffffff22" : "#0000001a"), radius: 6 });
    if (!ok) g.rect(x + 1, y + 1, w - 2, h - 2, { stroke: red, lineWidth: 2, radius: 5 });
  }

  // The patch being drawn.
  if (drag) {
    const p = rectFrom(drag.from, drag.to);
    g.rect(L.x + p.c * L.size + 2, L.y + p.r * L.size + 2, p.w * L.size - 4, p.h * L.size - 4, { stroke: "accent", lineWidth: 2.5, radius: 6 });
    g.text(p.w + "×" + p.h, L.x + (p.c + p.w) * L.size - 6, L.y + p.r * L.size + 12, { size: 11, weight: "semibold", color: "accent", align: "right" });
  }

  // Clues: the area, with the shape mark under it.
  for (const cl of clues) {
    const cx = L.x + (cl.cell % n + 0.5) * L.size, cy = L.y + (Math.floor(cl.cell / n) + 0.5) * L.size;
    g.text(String(cl.area), cx, cy - L.size * 0.1, { size: L.size * 0.36, weight: "bold", color: ink, align: "center" });
    shapeMark(g, cx, cy + L.size * 0.24, L.size * 0.2, cl.shape, dark ? "#ffffffaa" : "#00000088");
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
    if (e.type === "down") {
      const i = cellAt(e.x, e.y);
      if (i < 0) return;
      startClock();
      drag = { from: i, to: i, moved: false };
    } else if (e.type === "move" && drag) {
      const i = cellAt(e.x, e.y, true);
      if (i !== drag.to) { drag.to = i; drag.moved = true; }
    } else if (e.type === "up" && drag) {
      const { from, to, moved } = drag;
      drag = null;
      // A click (no drag) on a patch takes it away; a drag lays a new one.
      if (!moved || from === to) removeAt(from); else lay(rectFrom(from, to));
    }
    z.redraw();
  },

  undo() {
    if (solved || !history.length) return false;
    patches = history.pop();
    save();
    z.redraw();
    return true;
  },

  pause() { stopClock(); drag = null; save(); },

  resume() {
    preloadSounds();
    if (level === 0 && puzzleKey !== "daily-" + dayNumber(today())) open();
    z.redraw();
  },
});
