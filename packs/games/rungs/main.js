// Rungs: answer five clues, then put the answers in order so each word changes one letter from the
// next, like the rungs of a ladder. Once they're in order, the top and bottom rungs unlock with one
// shared clue. One puzzle a day; past days can be replayed.

const PUZZLES = z.data("puzzles.json");     // [{ w: seven words top to bottom, c: clues for w[1..5], e: the ends' clue }]

// Sounds (Kenney, CC0), played only while game sounds are on (Settings, and this game's speaker).
const SOUND_NAMES = ["giveup", "hint", "move", "right", "type", "unlock", "win", "wrong"];
const sound = (name, volume) => z.sound.play("sounds/" + name + ".wav", { volume: volume == null ? 1 : volume });
const preloadSounds = () => z.sound.preload(SOUND_NAMES.map(n => "sounds/" + n + ".wav"));

const FIRST_DAY = new Date(2026, 9, 20);    // the first daily; the archive goes back to here

let mode = 0;                               // 0 today, 1 archive
let day = 0;
let puzzle = null, L = 4;
let order = [];                             // the middle rows as shown, top to bottom: indexes 1..5 into puzzle.w
let typed = {};                             // row index (0..6) → letters typed
let selected = 1;
let unlocked = false, done = false;
let hintsUsed = 0, gaveUp = false;
let wrong = -1;                             // a row just filled in wrong (shown red until the next key)
let drag = null;                            // { row, startY, y, moved }
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

// The same shuffle for everyone on a day, never already in order.
function shuffled(d) {
  let seed = d * 7919 + 17;
  const rand = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  for (;;) {
    const a = [1, 2, 3, 4, 5];
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    if (!inOrder(a)) return a;
  }
}

function results() { return z.storage.get("results") || {}; }

function load(d) {
  day = d;
  puzzle = puzzleFor(d);
  L = puzzle.w[0].length;
  const saved = results()[d];
  if (saved) {
    order = saved.order; typed = saved.typed || {}; unlocked = !!saved.unlocked; done = !!saved.done;
    hintsUsed = saved.hints || 0; gaveUp = !!saved.gaveUp;
    elapsed = saved.elapsed || 0; finalTime = saved.time || 0;
  } else {
    order = shuffled(d); typed = {}; unlocked = false; done = false; elapsed = 0; finalTime = 0;
    hintsUsed = 0; gaveUp = false;
  }
  selected = order[0]; wrong = -1; drag = null; runningSince = null;
  z.overlay(null);
  setActions();
  if (done) showDone(); else z.loop.start(1000);
  z.redraw();
}

function save() {
  const all = results();
  all[day] = { order, typed, unlocked, done, elapsed: time(), time: finalTime, hints: hintsUsed, gaveUp };
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

// ───────────── Rules ─────────────

const oneApart = (a, b) => { let d = 0; for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) d++; return d === 1; };
const solvedRow = k => (typed[k] || "") === puzzle.w[k];

function inOrder(rows) {
  for (let i = 1; i < rows.length; i++) if (!oneApart(puzzle.w[rows[i - 1]], puzzle.w[rows[i]])) return false;
  return true;
}

// Which end goes on top depends on which way up the middle rows were sorted.
const topRow = () => (order[0] === 1 ? 0 : 6);
const bottomRow = () => (order[0] === 1 ? 6 : 0);

function checkUnlock() {
  if (unlocked || !order.every(solvedRow) || !inOrder(order)) return;
  unlocked = true;
  sound("unlock");
  selected = topRow();
  z.toast("In order! Now the top and bottom");
}

function checkDone() {
  if (!unlocked || !solvedRow(0) || !solvedRow(6)) return;
  stopClock();
  done = true;
  finalTime = elapsed;
  sound("win");
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
  if (hintsUsed && !gaveUp) parts.push(hintsUsed + (hintsUsed === 1 ? " hint" : " hints"));
  if (day === todayNumber()) {
    parts.push(gaveUp ? "Streak reset" : "Streak " + (z.storage.get("streak") || { count: 0 }).count);
    parts.push("Next daily in " + hoursToMidnight() + " h");
  }
  z.overlay({
    title: gaveUp ? "Here’s the ladder" : "Climbed in " + clock(finalTime),
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
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !done, help: "Show a letter, or put a rung in its place", onPress: useHint },
    { id: "giveUp", label: "Give up", symbol: "eye", enabled: !done,
      help: daily ? "Show the ladder (counts as a loss)" : "Show the ladder",
      confirm: daily
        ? { title: "Give up today’s puzzle?", message: "You’ll see the whole ladder. This counts as a loss and resets your streak.", button: "Give Up" }
        : { title: "Give up?", message: "You’ll see the whole ladder.", button: "Give Up" },
      onPress: giveUp },
  ]);
}

// The next letter of the selected rung (or the first unfinished one). Once every middle rung is
// answered but they're out of order, a hint moves one rung to its place instead.
function useHint() {
  if (done) return;
  startClock();
  sound("hint");
  const open = k => !solvedRow(k) && (unlocked || (k !== 0 && k !== 6));
  const rows = shownRows().filter(k => k >= 0 && open(k));
  if (rows.length) {
    const k = open(selected) ? selected : rows[0];
    const right = puzzle.w[k], t = typed[k] || "";
    let keep = 0;
    while (keep < t.length && t[keep] === right[keep]) keep++;
    typed[k] = right.slice(0, keep + 1);
    selected = k; wrong = -1;
    if (solvedRow(k)) { checkUnlock(); checkDone(); }
  } else if (!unlocked) {
    // Sorted the way the first rung points (1 at the top, or 5).
    const target = order[0] === 5 || (order.indexOf(5) < order.indexOf(1)) ? [5, 4, 3, 2, 1] : [1, 2, 3, 4, 5];
    const i = target.findIndex((k, j) => order[j] !== k);
    if (i < 0) return;
    moveRow(order.indexOf(target[i]), i);
  } else {
    return;
  }
  hintsUsed++;
  save();
  z.redraw();
}

function giveUp() {
  if (done) return;
  sound("giveup");
  for (let k = 0; k <= 6; k++) typed[k] = puzzle.w[k];
  order = [1, 2, 3, 4, 5];
  unlocked = true;
  gaveUp = true;
  stopClock();
  done = true;
  finalTime = elapsed;
  if (day === todayNumber()) z.storage.set("streak", { count: 0, last: day });
  save();
  setActions();
  showDone();
}

// ───────────── Typing ─────────────

function typeLetter(ch) {
  if (done || solvedRow(selected)) return;
  if ((selected === 0 || selected === 6) && !unlocked) return;
  startClock();
  const t = typed[selected] || "";
  if (t.length >= L) return;
  typed[selected] = t + ch;
  if (typed[selected].length < L) sound("type", 0.5);
  if (typed[selected].length === L) {
    if (solvedRow(selected)) {
      wrong = -1;
      sound("right");
      checkUnlock();
      checkDone();
      // Move on to the next unsolved row.
      const rows = shownRows().filter(k => k >= 0 && !solvedRow(k) && (unlocked || (k !== 0 && k !== 6)));
      if (rows.length && !done) selected = rows[0];
    } else {
      wrong = selected;
      sound("wrong");
    }
  }
  save();
}

// Every row as shown, top to bottom; the ends are -1 until unlocked.
function shownRows() {
  return [unlocked ? topRow() : -1, ...order, unlocked ? bottomRow() : -1];
}

// ───────────── Layout and drawing ─────────────

function layout() {
  const pad = 14, top = 60;
  const rowH = Math.min(46, (z.height - top - pad) / 7);
  const box = Math.min(rowH - 8, (z.width - pad * 2 - 80) / L);
  return { pad, top, rowH, box, x: (z.width - box * L - (L - 1) * 4) / 2 };
}

function rowAt(y) {
  const G = layout();
  const i = Math.floor((y - G.top) / G.rowH);
  return i >= 0 && i < 7 ? i : -1;
}

function draw(g) {
  const G = layout(), dark = z.theme.dark;
  const green = dark ? "#30d158" : "#248a3d";
  const red = dark ? "#ff6961" : "#d70015";
  const cell = dark ? "#ffffff12" : "#0000000a";

  // The day, the time and the clue for the selected row.
  if (mode === 1) {
    g.text("‹", G.pad + 6, 16, { size: 20, weight: "semibold", color: day > firstNumber() ? "accent" : "secondary", align: "center" });
    g.text(dateLabel(day), G.pad + 22, 16, { size: 13, weight: "medium", color: "secondary" });
    g.text("›", G.pad + 120, 16, { size: 20, weight: "semibold", color: day < todayNumber() ? "accent" : "secondary", align: "center" });
  } else {
    g.text("Today · " + dateLabel(day), G.pad, 16, { size: 13, weight: "medium", color: "secondary" });
  }
  g.text(clock(done ? finalTime : time()), z.width - G.pad, 16, { size: 13, weight: "semibold", color: "text", align: "right", font: "mono" });
  const clue = selected === 0 || selected === 6 ? (unlocked ? "Top and bottom: " + puzzle.e : "Sort the rungs to unlock the ends")
    : puzzle.c[selected - 1];
  g.text(clue, G.pad, 42, { size: 13, weight: "semibold", color: "text" });

  const rows = shownRows();
  rows.forEach((k, i) => {
    let y = G.top + i * G.rowH;
    if (drag && drag.moved && k === drag.row) return;     // drawn last, under the pointer
    drawRow(g, G, k, y, { cell, green, red, dark });
  });
  if (drag && drag.moved) drawRow(g, G, drag.row, drag.y - G.rowH / 2, { cell, green, red, dark, lifted: true });
}

function drawRow(g, G, k, y, s) {
  const isEnd = k === -1 || k === 0 || k === 6;
  const w = G.box * L + (L - 1) * 4;
  const solved = k >= 0 && solvedRow(k);
  if (s.lifted) { g.save(); g.shadow("#00000055", { radius: 8, y: 3 }); }
  g.rect(G.x - 10, y + 3, w + 20, G.rowH - 6, { fill: k === selected && !done ? (s.dark ? "#ffffff1c" : "#00000012") : "background", radius: 10 });
  if (s.lifted) g.restore();
  for (let j = 0; j < L; j++) {
    const x = G.x + j * (G.box + 4), cy = y + G.rowH / 2;
    const ch = k >= 0 ? (typed[k] || "")[j] : null;
    g.rect(x, cy - G.box / 2, G.box, G.box, {
      fill: solved ? s.green + "33" : s.cell, radius: 6,
      stroke: k === wrong ? s.red : undefined, lineWidth: 1.5,
    });
    if (ch) g.text(ch.toUpperCase(), x + G.box / 2, cy, { size: G.box * 0.5, weight: "bold", color: "text", align: "center" });
  }
  const cy = y + G.rowH / 2;
  if (k === -1) g.symbol("lock.fill", G.x + w + 24, cy, 12, { color: "secondary" });
  if (solved) g.symbol("checkmark", G.x - 24, cy, 12, { color: s.green });
  if (!isEnd && !unlocked) g.text("≡", G.x + w + 24, cy, { size: 18, color: "secondary", align: "center" });
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

function moveRow(from, to) {
  sound("move", 0.7);
  const k = order.splice(from, 1)[0];
  order.splice(Math.max(0, Math.min(order.length, to)), 0, k);
  checkUnlock();
  save();
}

zephydian.game({
  start() {
    preloadSounds();
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
      if (mode === 1 && e.y < 30) {
        if (e.x < 40 && day > firstNumber()) load(day - 1);
        else if (e.x > 110 && e.x < 150 && day < todayNumber()) load(day + 1);
        return;
      }
      const i = rowAt(e.y), k = i >= 0 ? shownRows()[i] : -1;
      if (k < 0) return;
      selected = k; wrong = -1;
      if (!unlocked && k !== 0 && k !== 6) drag = { row: k, startY: e.y, y: e.y, moved: false };
    } else if (e.type === "move" && drag) {
      drag.y = e.y;
      if (Math.abs(e.y - drag.startY) > 6) { drag.moved = true; startClock(); }
    } else if (e.type === "up" && drag) {
      if (drag.moved) {
        const G = layout();
        const to = Math.round((drag.y - G.top - G.rowH * 1.5) / G.rowH);
        moveRow(order.indexOf(drag.row), to);
      }
      drag = null;
    }
    z.redraw();
  },

  key(e) {
    if (done) return false;
    const rows = shownRows().filter(k => k >= 0);
    const at = rows.indexOf(selected);
    if (e.key === "ArrowUp" || e.key === "ArrowDown") {
      const step = e.key === "ArrowUp" ? -1 : 1;
      if (e.option && !unlocked && order.includes(selected)) {
        // ⌥↑ / ⌥↓ moves the selected rung.
        const i = order.indexOf(selected);
        startClock();
        moveRow(i, i + step);
      } else if (rows[at + step] !== undefined) {
        selected = rows[at + step];
      }
      wrong = -1;
      z.redraw();
      return true;
    }
    if (e.key === "Backspace") {
      if (!solvedRow(selected)) typed[selected] = (typed[selected] || "").slice(0, -1);
      wrong = -1;
      save();
      z.redraw();
      return true;
    }
    if (e.char && /^[a-z]$/i.test(e.char)) {
      wrong = -1;
      typeLetter(e.char.toLowerCase());
      z.redraw();
      return true;
    }
    return false;
  },

  pause() { stopClock(); drag = null; if (!done) save(); },

  resume() {
    preloadSounds();
    if (mode === 0 && day !== todayNumber()) load(todayNumber());
    z.redraw();
  },
});
