// Weave: the grid is made of hidden words on a theme. Drag across neighbouring letters (up, down,
// left, right) to trace a word; every letter belongs to exactly one word. One puzzle a day; past days
// can be replayed. Hint shows the next letter of a word you haven't found.

const PUZZLES = z.data("puzzles.json");     // [{ t: theme, g: 36 letters, w: [[word, [cells]]] }]
const FIRST_DAY = new Date(2026, 9, 20);    // the first daily; the archive goes back to here
const N = 6;

// Soft colours for found words (the same palette as Crowns), in light and dark versions.
const LIGHT = ["#f6c9cf", "#bfdcf5", "#cfe6c4", "#f3e0b5", "#dccdf0", "#f7d2b8", "#bfe8de"];
const DARK = ["#7a4a52", "#3f5f7d", "#4f6b45", "#7a6538", "#5e4d7a", "#7d5a40", "#3e6f63"];

let mode = 0;                               // 0 today, 1 archive
let day = 0;
let puzzle = null;
let found = [];                             // word indexes, in the order found
let hints = {};                             // word index → letters revealed
let trace = null;                           // cells being traced
let done = false, gaveUp = false;
let elapsed = 0, runningSince = null, finalTime = 0;

// ───────────── Days ─────────────

function dayNumber(date) {
  return Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - new Date(2026, 0, 1)) / 86400000);
}
const todayNumber = () => dayNumber(new Date());
const firstNumber = () => dayNumber(FIRST_DAY);

function dateLabel(d) {
  const date = new Date(2026, 0, 1 + d);
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()] + " " + date.getDate() + " "
    + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][date.getMonth()];
}

function hoursToMidnight() {
  const now = new Date(), next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  return Math.max(1, Math.ceil((next - now) / 3600000));
}

// ───────────── Puzzles ─────────────

const puzzleFor = d => PUZZLES[(((d - firstNumber()) % PUZZLES.length) + PUZZLES.length) % PUZZLES.length];

function results() { return z.storage.get("results") || {}; }

function load(d) {
  day = d;
  puzzle = puzzleFor(d);
  const saved = results()[d];
  if (saved) {
    found = saved.found || []; hints = saved.hints || {}; done = !!saved.done; gaveUp = !!saved.gaveUp;
    elapsed = saved.elapsed || 0; finalTime = saved.time || 0;
  } else {
    found = []; hints = {}; done = false; gaveUp = false; elapsed = 0; finalTime = 0;
  }
  trace = null; runningSince = null;
  z.overlay(null);
  setActions();
  if (done) showDone(); else z.loop.start(1000);
  z.redraw();
}

function save() {
  const all = results();
  all[day] = { found, hints, done, gaveUp, elapsed: time(), time: finalTime };
  z.storage.set("results", all);
}

// ───────────── Time ─────────────

function time() { return elapsed + (runningSince == null ? 0 : Date.now() - runningSince); }
function startClock() { if (!done && runningSince == null) runningSince = Date.now(); }
function stopClock() { if (runningSince != null) { elapsed += Date.now() - runningSince; runningSince = null; } }
function clock(ms) {
  const s = Math.floor(ms / 1000);
  return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
}

// ───────────── Words ─────────────

// The word a cell belongs to once found, or -1.
function foundAt(cell) {
  for (const k of found) if (puzzle.w[k][1].includes(cell)) return k;
  return -1;
}

const hintCount = () => Object.values(hints).reduce((s, n) => s + n, 0);

function finishTrace() {
  const cells = trace;
  trace = null;
  if (!cells || cells.length < 2) return;
  const spelled = cells.map(c => puzzle.g[c]).join("");
  for (let k = 0; k < puzzle.w.length; k++) {
    if (found.includes(k)) continue;
    const [word, path] = puzzle.w[k];
    if (path.length === cells.length && path.every((c, i) => c === cells[i])) {
      found.push(k);
      save();
      if (found.length === puzzle.w.length) finish();
      return;
    }
    if (word === spelled) { z.toast("Right word, but it's hidden somewhere else"); return; }
  }
}

function hint() {
  if (done) return;
  startClock();
  // The next letter of the first word not found yet (a whole word revealed counts as found).
  const k = puzzle.w.findIndex((_, i) => !found.includes(i));
  if (k < 0) return;
  hints[k] = (hints[k] || 0) + 1;
  if (hints[k] >= puzzle.w[k][0].length) { found.push(k); if (found.length === puzzle.w.length) { save(); finish(); return; } }
  save();
  z.redraw();
}

function finish() {
  stopClock();
  done = true;
  finalTime = elapsed;
  if (day === todayNumber() && gaveUp) {
    z.storage.set("streak", { count: 0, last: day });
  } else if (day === todayNumber()) {
    const streak = z.storage.get("streak") || { count: 0, last: null };
    if (streak.last !== day) {
      streak.count = streak.last === day - 1 ? streak.count + 1 : 1;
      streak.last = day;
      z.storage.set("streak", streak);
    }
  }
  save();
  setActions();
  showDone();
}

function showDone() {
  z.loop.stop();
  const parts = [];
  const h = hintCount();
  if (!gaveUp) parts.push(h ? h + (h === 1 ? " hint" : " hints") : "No hints");
  if (day === todayNumber()) {
    parts.push(gaveUp ? "Streak reset" : "Streak " + (z.storage.get("streak") || { count: 0 }).count);
    parts.push("Next daily in " + hoursToMidnight() + " h");
  }
  z.overlay({
    title: gaveUp ? "Here are the words" : "Woven in " + clock(finalTime),
    subtitle: parts.join(" · "),
    buttons: [{ label: day > firstNumber() ? "Play an earlier day" : "Close", prominent: true, action() {
      if (day > firstNumber()) { mode = 1; setMenu(); load(day - 1); } else z.overlay(null);
    } }],
  });
  z.redraw();
}

// ───────────── Hint and Give up ─────────────

function setActions() {
  const daily = day === todayNumber();
  z.actions([
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !done, help: "Show the next letter of a word (H)", onPress: hint },
    { id: "giveUp", label: "Give up", symbol: "eye", enabled: !done,
      help: daily ? "Show every word (counts as a loss)" : "Show every word",
      confirm: daily
        ? { title: "Give up today’s puzzle?", message: "You’ll see every word. This counts as a loss and resets your streak.", button: "Give Up" }
        : { title: "Give up?", message: "You’ll see every word.", button: "Give Up" },
      onPress() {
        if (done) return;
        puzzle.w.forEach((_, k) => { if (!found.includes(k)) found.push(k); });
        gaveUp = true;
        finish();
      } },
  ]);
}

// ───────────── Layout and drawing ─────────────

function layout() {
  const pad = 14;
  const top = 104;
  const side = Math.min(z.width - pad * 2, z.height - top - pad);
  const size = side / N;
  return { pad, top, size, x: (z.width - size * N) / 2, y: top + (z.height - top - pad - size * N) / 2 };
}

function cellAt(x, y) {
  const L = layout();
  const c = Math.floor((x - L.x) / L.size), r = Math.floor((y - L.y) / L.size);
  if (r < 0 || r >= N || c < 0 || c >= N) return -1;
  // Only near the middle of a cell, so diagonal swipes don't catch the corners.
  const dx = x - (L.x + (c + 0.5) * L.size), dy = y - (L.y + (r + 0.5) * L.size);
  return Math.abs(dx) < L.size * 0.42 && Math.abs(dy) < L.size * 0.42 ? r * N + c : -2;
}

const isNeighbour = (a, b) => (Math.abs(a - b) === 1 && Math.floor(a / N) === Math.floor(b / N)) || Math.abs(a - b) === N;

function draw(g) {
  const L = layout(), dark = z.theme.dark, palette = dark ? DARK : LIGHT;
  const centre = i => [L.x + (i % N + 0.5) * L.size, L.y + (Math.floor(i / N) + 0.5) * L.size];

  // The day, the time and the theme.
  if (mode === 1) {
    g.text("‹", L.pad + 6, 16, { size: 20, weight: "semibold", color: day > firstNumber() ? "accent" : "secondary", align: "center" });
    g.text(dateLabel(day), L.pad + 22, 16, { size: 13, weight: "medium", color: "secondary" });
    g.text("›", L.pad + 120, 16, { size: 20, weight: "semibold", color: day < todayNumber() ? "accent" : "secondary", align: "center" });
  } else {
    g.text("Today · " + dateLabel(day), L.pad, 16, { size: 13, weight: "medium", color: "secondary" });
  }
  g.text(clock(done ? finalTime : time()), z.width - L.pad, 16, { size: 13, weight: "semibold", color: "text", align: "right", font: "mono" });
  g.text("Theme: " + puzzle.t, L.pad, 42, { size: 14, weight: "bold", color: "text" });

  // The words as blanks: found ones spelled out, hinted letters shown.
  let x = L.pad, y = 70;
  const slot = 10.5;
  puzzle.w.forEach(([word], k) => {
    const width = word.length * slot;
    if (x + width > z.width - L.pad) { x = L.pad; y += 22; }
    const shown = found.includes(k) ? word.length : (hints[k] || 0);
    for (let j = 0; j < word.length; j++) {
      const cx = x + j * slot + slot / 2;
      if (j < shown) g.text(word[j].toUpperCase(), cx, y, { size: 12, weight: "bold", color: found.includes(k) ? "text" : "accent", align: "center", font: "mono" });
      else g.line(cx - 3.5, y + 6, cx + 3.5, y + 6, { stroke: "secondary", lineWidth: 1.5, cap: "round" });
    }
    x += width + 14;
  });

  // Found words: their colour under the letters, joined like a thread.
  for (const k of found) {
    const color = palette[k % palette.length];
    const pts = puzzle.w[k][1].map(centre);
    g.path(pts, { stroke: color, lineWidth: L.size * 0.7, cap: "round" });
  }
  // The trace so far.
  if (trace && trace.length) g.path(trace.map(centre), { stroke: "accent", lineWidth: L.size * 0.5, cap: "round" });
  if (trace && trace.length === 1) { const [cx, cy] = centre(trace[0]); g.circle(cx, cy, L.size * 0.25, { fill: "accent" }); }

  // Letters, and the cells of hinted letters.
  for (let i = 0; i < N * N; i++) {
    const [cx, cy] = centre(i);
    const k = foundAt(i);
    for (const [hk, n] of Object.entries(hints)) {
      if (found.includes(Number(hk))) continue;
      const cells = puzzle.w[hk][1].slice(0, n);
      if (cells.includes(i)) g.circle(cx, cy, L.size * 0.36, { stroke: "accent", lineWidth: 2 });
    }
    const inTrace = trace && trace.includes(i);
    g.text(puzzle.g[i].toUpperCase(), cx, cy, { size: L.size * 0.42, weight: "bold", color: inTrace ? "#ffffff" : k >= 0 ? (dark ? "#ffffff" : "#1c1c1e") : "text", align: "center" });
  }
}

// ───────────── Menu ─────────────

function setMenu() {
  z.menu({
    title: "Day",
    items: ["Today", "Archive"],
    selected: mode,
    onSelect(i) {
      mode = i;
      load(i === 0 ? todayNumber() : Math.max(firstNumber(), todayNumber() - 1));
    },
  });
}

zephydian.game({
  start() {
    setMenu();
    load(todayNumber());
  },

  draw,

  tick() {
    if (mode === 0 && day !== todayNumber()) { load(todayNumber()); return; }
    z.redraw();
  },

  pointer(e) {
    if (done) return;
    if (e.type === "down") {
      if (e.y < 30 && mode === 1) {
        if (e.x < 40 && day > firstNumber()) load(day - 1);
        else if (e.x > 110 && e.x < 150 && day < todayNumber()) load(day + 1);
        return;
      }
      const i = cellAt(e.x, e.y);
      if (i < 0 || foundAt(i) >= 0) return;
      startClock();
      trace = [i];
    } else if (e.type === "move" && trace) {
      const i = cellAt(e.x, e.y);
      if (i < 0 || foundAt(i) >= 0) return;
      const head = trace[trace.length - 1];
      if (i === head) return;
      if (trace.length > 1 && i === trace[trace.length - 2]) trace.pop();          // back one step
      else if (!trace.includes(i) && isNeighbour(head, i)) trace.push(i);
    } else if (e.type === "up" && trace) {
      finishTrace();
    }
    z.redraw();
  },

  key(e) {
    if (done || e.key !== "h") return false;
    hint();
    return true;
  },

  pause() { stopClock(); trace = null; if (!done) save(); },

  resume() {
    if (mode === 0 && day !== todayNumber()) load(todayNumber());
    z.redraw();
  },
});
