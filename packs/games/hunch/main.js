// Hunch: guess what links the words. The first word shows; every wrong guess reveals another, up to
// five. The fewer words you needed, the better. One puzzle a day; past days can be replayed.

const PUZZLES = z.data("puzzles.json");     // [{ a: answer, ok: [key phrases], w: [five words] }]
const FIRST_DAY = new Date(2026, 9, 20);    // the first daily; the archive goes back to here
const WORDS = 5;
const ADVANCE = 14 * 0.618;                 // the typed guess is 14 pt SF Mono

// Little words a guess can leave in or out ("types of trees" = "tree").
const FILLER = new Set(["a", "an", "the", "of", "things", "thing", "types", "type", "kinds", "kind", "that", "are", "is",
  "can", "be", "you", "your", "with", "in", "on", "for", "to", "and", "or", "words", "word", "some", "famous", "stuff"]);

let mode = 0;                               // 0 today, 1 archive
let day = 0;                                // the day shown (days since 1 January 2026)
let puzzle = null;
let shown = 1, guesses = [], typing = "", done = false, won = false;
let hintsUsed = 0, gaveUp = false, usedWords = 0;
let elapsed = 0, runningSince = null, finalTime = 0;
let blink = true;

// ───────────── Days ─────────────

function dayNumber(date) {
  return Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - new Date(2026, 0, 1)) / 86400000);
}
const todayNumber = () => dayNumber(new Date());
const firstNumber = () => dayNumber(FIRST_DAY);

function dateLabel(d) {
  const date = new Date(2026, 0, 1 + d);
  const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return names[date.getDay()] + " " + date.getDate() + " " + months[date.getMonth()];
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
    shown = saved.shown; guesses = saved.guesses || []; done = !!saved.done; won = !!saved.won;
    hintsUsed = saved.hints || 0; gaveUp = !!saved.gaveUp; usedWords = saved.used || 0;
    elapsed = saved.elapsed || 0; finalTime = saved.time || 0;
  } else {
    shown = 1; guesses = []; done = false; won = false; elapsed = 0; finalTime = 0;
    hintsUsed = 0; gaveUp = false; usedWords = 0;
  }
  typing = ""; runningSince = null;
  z.overlay(null);
  setActions();
  if (done) showDone(); else z.loop.start(500);
  z.redraw();
}

function save() {
  const all = results();
  all[day] = { shown, guesses, done, won, elapsed: time(), time: finalTime, hints: hintsUsed, gaveUp, used: usedWords };
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

// ───────────── Guessing ─────────────

function tokens(text) {
  return text.toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9 ]+/g, " ").split(/\s+/)
    .filter(t => t && !FILLER.has(t))
    .map(stem);
}

// One form for singular and plural: "boxes" = "box", "berries" = "berry", "cookies" = "cookie".
function stem(t) {
  if (t.length > 4 && /(ch|sh|x|ss)es$/.test(t)) t = t.slice(0, -2);
  else if (t.length > 3 && t.endsWith("s") && !t.endsWith("ss")) t = t.slice(0, -1);
  return t.endsWith("ie") ? t.slice(0, -2) + "y" : t;
}

// Right when every key word of one of the answer's phrases is in the guess.
function isRight(guess) {
  const g = new Set(tokens(guess));
  return puzzle.ok.some(phrase => {
    const need = tokens(phrase);
    return need.length > 0 && need.every(t => g.has(t));
  });
}

function submit() {
  const guess = typing.trim();
  if (!guess || done) return;
  startClock();
  typing = "";
  if (isRight(guess)) {
    won = true;
    usedWords = shown;
    finish();
    return;
  }
  guesses.push(guess);
  if (shown < WORDS) shown++;
  else { finish(); return; }
  save();
  setActions();
  z.redraw();
}

function finish() {
  stopClock();
  done = true;
  finalTime = elapsed;
  shown = WORDS;
  if (won && day === todayNumber()) {
    const streak = z.storage.get("streak") || { count: 0, last: null };
    if (streak.last !== day) {
      streak.count = streak.last === day - 1 ? streak.count + 1 : 1;
      streak.last = day;
      z.storage.set("streak", streak);
    }
  } else if (!won && day === todayNumber()) {
    z.storage.set("streak", { count: 0, last: day });     // a miss or giving up starts the streak again
  }
  save();
  setActions();
  showDone();
}

function showDone() {
  z.loop.stop();
  const used = usedWords || guesses.length + 1;
  const parts = [];
  if (won && hintsUsed) parts.push(hintsUsed + (hintsUsed === 1 ? " hint" : " hints"));
  if (day === todayNumber()) {
    parts.push(won ? "Streak " + (z.storage.get("streak") || { count: 0 }).count : "Streak reset");
    parts.push("Next daily in " + hoursToMidnight() + " h");
  }
  z.overlay({
    title: won ? "Got it with " + used + (used === 1 ? " word" : " words") + " in " + clock(finalTime) : "The link was: " + puzzle.a,
    subtitle: (won ? "It's " + puzzle.a + ". " : "") + parts.join(" · "),
    buttons: [{ label: day > firstNumber() ? "Play an earlier day" : "Close", prominent: true, action() {
      if (day > firstNumber()) { mode = 1; setMenu(); load(day - 1); } else z.overlay(null);
    } }],
  });
  z.redraw();
}

// ───────────── Hint and Give up ─────────────

// Hint shows the next word without using a guess; giving up shows the answer (a loss on a daily).
function setActions() {
  const daily = day === todayNumber();
  z.actions([
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !done && shown < WORDS, help: "Show the next word, without using a guess",
      onPress() {
        if (done || shown >= WORDS) return;
        startClock();
        shown++;
        hintsUsed++;
        save();
        setActions();
        z.redraw();
      } },
    { id: "giveUp", label: "Give up", symbol: "eye", enabled: !done,
      help: daily ? "Show the answer (counts as a loss)" : "Show the answer",
      confirm: daily
        ? { title: "Give up today’s puzzle?", message: "You’ll see the answer. This counts as a loss and resets your streak.", button: "Give Up" }
        : { title: "Give up?", message: "You’ll see the answer.", button: "Give Up" },
      onPress() { if (done) return; gaveUp = true; won = false; finish(); } },
  ]);
}

// ───────────── Drawing ─────────────

// As many letters as fit in the box.
const maxLetters = () => Math.max(10, Math.floor((layout().w - 26) / ADVANCE));

function layout() {
  const pad = 16, w = z.width - pad * 2;
  return { pad, w, rowH: Math.min(42, (z.height - 170) / WORDS), top: 44 };
}

function draw(g) {
  const L = layout(), dark = z.theme.dark;
  const box = dark ? "#ffffff12" : "#0000000a";
  const red = dark ? "#ff6961" : "#d70015";

  // The day (with ‹ › in the archive) and the time.
  if (mode === 1) {
    g.text("‹", L.pad + 6, 18, { size: 20, weight: "semibold", color: day > firstNumber() ? "accent" : "secondary", align: "center" });
    g.text(dateLabel(day), L.pad + 22, 18, { size: 13, weight: "medium", color: "secondary" });
    g.text("›", L.pad + 120, 18, { size: 20, weight: "semibold", color: day < todayNumber() ? "accent" : "secondary", align: "center" });
  } else {
    g.text("Today · " + dateLabel(day), L.pad, 18, { size: 13, weight: "medium", color: "secondary" });
  }
  g.text(clock(done ? finalTime : time()), z.width - L.pad, 18, { size: 13, weight: "semibold", color: "text", align: "right", font: "mono" });

  // The five words: shown ones in capitals, the rest as empty bars.
  for (let k = 0; k < WORDS; k++) {
    const y = L.top + k * (L.rowH + 6);
    g.rect(L.pad, y, L.w, L.rowH, { fill: box, radius: 10 });
    g.text(String(k + 1), L.pad + 16, y + L.rowH / 2, { size: 12, weight: "semibold", color: "secondary", align: "center" });
    if (k < shown) {
      g.text(puzzle.w[k].toUpperCase(), L.pad + 34, y + L.rowH / 2, { size: 16, weight: "bold", color: "text" });
    }
  }

  // Wrong guesses, then the guess being typed.
  let y = L.top + WORDS * (L.rowH + 6) + 8;
  if (guesses.length) {
    g.text("Not: " + guesses.join(", "), L.pad, y + 6, { size: 12, color: red });
    y += 20;
  }
  if (!done) {
    g.rect(L.pad, y, L.w, 38, { stroke: "accent", lineWidth: 1.5, radius: 10 });
    if (typing) g.text(typing, L.pad + 12, y + 19, { size: 14, color: "text", font: "mono" });
    else g.text("What links them?", L.pad + 12, y + 19, { size: 14, color: "secondary" });
    if (blink) {
      const x = L.pad + 12 + typing.length * ADVANCE;
      g.rect(x, y + 10, 2, 18, { fill: "accent", radius: 1 });
    }
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
    blink = !blink;
    z.redraw();
  },

  click(e) {
    if (mode !== 1 || e.y > 34) return;
    // The archive's ‹ and ›.
    if (e.x < 40 && day > firstNumber()) load(day - 1);
    else if (e.x > 110 && e.x < 150 && day < todayNumber()) load(day + 1);
  },

  key(e) {
    if (done) return false;
    if (e.key === "Enter") { submit(); return true; }
    if (e.key === "Backspace") {
      typing = e.option ? typing.replace(/\S+\s*$/, "") : typing.slice(0, -1);
    } else if (e.char && !e.command && typing.length < maxLetters()) {
      if (!typing && e.char === " ") return true;
      startClock();
      typing += e.char;
    } else {
      return false;
    }
    blink = true;
    z.redraw();
    return true;
  },

  pause() { stopClock(); if (!done) save(); },

  resume() {
    if (mode === 0 && day !== todayNumber()) load(todayNumber());
    z.redraw();
  },
});
