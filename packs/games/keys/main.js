// Keys: a typing speed test. Type the words as they appear; the timer starts with the first key.
// WPM counts the characters of correctly typed words (and their spaces) ÷ 5 per minute,
// raw WPM counts every character typed, and accuracy is correct keystrokes ÷ all keystrokes.
// Code mode types short snippets instead: each line ends with Enter, and indentation is skipped.
// The text is a list of tokens (words, or the pieces of a code line between spaces), each ending
// in a space or, at the end of a code line, a line break.

const MODES = [
  { type: "time", n: 15 }, { type: "time", n: 30 }, { type: "time", n: 60 }, { type: "time", n: 120 },
  { type: "words", n: 10 }, { type: "words", n: 25 }, { type: "words", n: 50 }, { type: "words", n: 100 },
];
const DEFAULT_MODE = 1;            // 30 seconds
const MAX_EXTRA = 10;              // letters typed past the end of a word
const LINES = 3;                   // lines of text on screen
const RESTART_WINDOW = 1500;       // ms between Tab and Enter
const ADVANCE = 0.618;             // SF Mono's width per character, in font sizes

// Key sounds (NovelKeys Creams, from kbsim by Thomas Lai, MIT): a press on key down and a release on
// key up, like a real board. Letters sound by their keyboard row; Space, Enter and Backspace have their own.
const ROWS = {};
["`1234567890-=~!@#$%^&*()_+", "qwertyuiop[]\\{}|", "asdfghjkl;':\"", "zxcvbnm,./<>?"].forEach((keys, i) => { for (const k of keys) ROWS[k] = i + 1; });
const OWN_SOUND = { " ": "space", "Enter": "enter", "Backspace": "backspace" };
const SOUND_FILES = ["press-r1", "press-r2", "press-r3", "press-r4", "press-space", "press-enter", "press-backspace",
  "release", "release-space", "release-enter", "release-backspace"].map(n => "sounds/" + n + ".wav");

function pressSound(e) {
  if (e.repeat) return;
  const own = OWN_SOUND[e.key];
  z.sound.play("sounds/press-" + (own || "r" + (e.key === "Tab" ? 2 : ROWS[e.key] || 4)) + ".wav");
}

function releaseSound(e) {
  const own = OWN_SOUND[e.key];
  z.sound.play("sounds/release" + (own ? "-" + own : "") + ".wav");
}

const LIST = String(z.data("words.txt")).split("\n").map(w => w.trim()).filter(Boolean);
// Snippets are separated by blank lines; each is a list of { indent, text } lines.
const SNIPPETS = String(z.data("code.txt")).split(/\n\s*\n/).map(block => block.split("\n")
  .filter(line => line.trim())
  .map(line => ({ indent: line.length - line.trimStart().length, text: line.trim() })))
  .filter(lines => lines.length);

let mode = DEFAULT_MODE;
let punctuation = false;
let numbers = false;
let code = false;
let bests = {};                    // best WPM per mode, by modeKey()

let words = [];                    // the target tokens
let seps = [];                     // what follows each token: " " (Space) or "\n" (Enter, code only)
let indents = [];                  // columns skipped before a token that starts a code line
let typed = [];                    // what was typed for each token so far
let cur = 0;                       // the token being typed
let lastSnippet = -1;
let capitalizeNext = true;         // for punctuation: the next word starts a sentence

let started = false, finished = false;
let accumulated = 0;               // ms typed before the last pause
let runningSince = null;           // Date.now() when the current stretch began, null while paused
let keystrokes = 0, correctKeys = 0;
let samples = [];                  // one per second: { wpm, raw, errors }
let secondChars = 0, secondErrors = 0;
let result = null;                 // the finished test's numbers
let tabAt = 0;

// Animated positions, in points: the caret and the scroll (in lines).
let caretX = 0, caretY = 0, scroll = 0, snapNext = true;
let blinkOn = true, blinkTime = 0;
let loopMs = 0;
let lastCounter = "";

// ───────────── Words ─────────────

function pick(prev) {
  let w;
  do { w = LIST[Math.floor(Math.random() * LIST.length)]; } while (w === prev && LIST.length > 1);
  return w;
}

function makeWord(prev) {
  if (numbers && Math.random() < 0.12) {
    const digits = 1 + Math.floor(Math.random() * 4);
    let s = String(1 + Math.floor(Math.random() * 9));
    while (s.length < digits) s += Math.floor(Math.random() * 10);
    return s;
  }
  let w = pick(prev);
  if (!punctuation) return w;
  if (capitalizeNext) { w = w[0].toUpperCase() + w.slice(1); capitalizeNext = false; }
  const r = Math.random();
  if (r < 0.03) return '"' + w + '"';
  if (r < 0.05) return "(" + w + ")";
  if (r < 0.13) { capitalizeNext = true; return w + "."; }
  if (r < 0.15) { capitalizeNext = true; return w + "?"; }
  if (r < 0.16) { capitalizeNext = true; return w + "!"; }
  if (r < 0.25) return w + ",";
  if (r < 0.26) return w + ";";
  return w;
}

function push(word, sep, indent) {
  words.push(word); seps.push(sep); indents.push(indent); typed.push("");
}

function addWords(count) {
  for (let i = 0; i < count; i++) push(makeWord(words[words.length - 1]), " ", 0);
}

// Code: whole snippets, until at least `count` more lines (or, with `exact`, exactly that many).
function addLines(count, exact) {
  let added = 0;
  while (added < count) {
    const left = count - added;
    let k, tries = 0;
    do { k = Math.floor(Math.random() * SNIPPETS.length); tries++; }
    while ((k === lastSnippet || (exact && SNIPPETS[k].length > left)) && tries < 200);
    lastSnippet = k;
    for (const line of SNIPPETS[k].slice(0, exact ? left : undefined)) {
      const parts = line.text.split(" ");
      parts.forEach((part, j) => push(part, j === parts.length - 1 ? "\n" : " ", j === 0 ? line.indent : 0));
      added++;
    }
  }
}

function linesDone() {
  let n = 0;
  for (let i = 0; i < cur; i++) if (seps[i] === "\n") n++;
  return n;
}

function newTest() {
  words = []; seps = []; indents = []; typed = []; cur = 0; capitalizeNext = true; lastSnippet = -1;
  const m = MODES[mode];
  if (code) addLines(m.type === "words" ? m.n : 12, m.type === "words");
  else addWords(m.type === "words" ? m.n : 60);
  if (punctuation && !code && m.type === "words") {
    // A word test ends a sentence.
    const last = words.length - 1;
    words[last] = words[last].replace(/[.,;?!]$/, "") + ".";
  }
  started = false; finished = false;
  accumulated = 0; runningSince = null;
  keystrokes = 0; correctKeys = 0;
  samples = []; secondChars = 0; secondErrors = 0;
  result = null; tabAt = 0;
  scroll = 0; snapNext = true;
  blinkOn = true; blinkTime = 0;
  z.hint("Type to start · Tab + Enter restart");
  showBest();
  setLoop(16);
  z.redraw();
}

// ───────────── Timing and scores ─────────────

function now() { return Date.now(); }
function elapsed() { return accumulated + (runningSince == null ? 0 : now() - runningSince); }

function correctChars(includeCurrent) {
  let n = 0;
  for (let i = 0; i < cur; i++) if (typed[i] === words[i]) n += words[i].length + 1;
  if (includeCurrent && cur < words.length && words[cur].startsWith(typed[cur])) n += typed[cur].length;
  return n;
}

function wpm(chars, ms) { return ms > 0 ? (chars / 5) / (ms / 60000) : 0; }

function sample() {
  const t = (samples.length + 1) * 1000;
  samples.push({ wpm: wpm(correctChars(true), t), raw: secondChars * 12, errors: secondErrors });
  secondChars = 0; secondErrors = 0;
}

function modeKey() {
  const m = MODES[mode];
  return m.type + m.n + (code ? "c" : (punctuation ? "p" : "") + (numbers ? "n" : ""));
}

function showBest() {
  const b = bests[modeKey()];
  z.score(b ? "best " + b : "");
}

function finish() {
  const m = MODES[mode];
  let ms = elapsed();
  if (m.type === "time") ms = m.n * 1000;
  if (runningSince != null) { accumulated = elapsed(); runningSince = null; }
  finished = true;
  // A last partial second still goes on the graph.
  if (ms - samples.length * 1000 > 200 || samples.length === 0) {
    const part = Math.max(ms - samples.length * 1000, 1) / 1000;
    samples.push({ wpm: wpm(correctChars(true), ms), raw: secondChars * 12 / part, errors: secondErrors });
  }

  let correct = 0, incorrect = 0, extra = 0, missed = 0;
  const last = Math.min(cur, words.length - 1);
  for (let i = 0; i <= last; i++) {
    const w = words[i], t = typed[i];
    for (let j = 0; j < Math.max(w.length, t.length); j++) {
      if (j >= w.length) extra++;
      else if (j >= t.length) { if (i < cur) missed++; }
      else if (t[j] === w[j]) correct++;
      else incorrect++;
    }
  }
  const speed = Math.round(wpm(correctChars(true), ms));
  const key = modeKey();
  const isBest = speed > 0 && speed > (bests[key] || 0);
  if (isBest) { bests[key] = speed; z.storage.set("bests", bests); }
  z.best.submitScore(speed);
  result = {
    wpm: speed,
    raw: Math.round(wpm(keystrokes, ms)),
    acc: keystrokes ? Math.round(correctKeys / keystrokes * 100) : 0,
    correct, incorrect, extra, missed,
    seconds: ms / 1000,
    isBest,
    best: bests[key] || speed,
  };
  z.hint("Tab + Enter to start again");
  showBest();
  setLoop(0);
  z.redraw();
}

// ───────────── Typing ─────────────

function begin() {
  started = true;
  runningSince = now();
  setLoop(16);
}

// Space or Enter: moves on only if it's the separator this token ends with (a code line ends
// with Enter); the other one counts as a mistake.
function separator(sep) {
  if (!started || typed[cur] === "") return;   // nothing to finish yet
  if (seps[cur] !== sep) { keystrokes++; secondChars++; secondErrors++; return; }
  commitWord();
}

function commitWord() {
  keystrokes++;
  secondChars++;
  if (typed[cur] === words[cur]) correctKeys++; else secondErrors++;
  cur++;
  const m = MODES[mode];
  if (m.type === "words" && cur >= words.length) { cur = words.length; finish(); return; }
  if (m.type === "time" && cur > words.length - 40) { if (code) addLines(8, false); else addWords(30); }
}

function typeChar(c) {
  if (!started) begin();
  const w = words[cur], t = typed[cur];
  if (t.length >= w.length + MAX_EXTRA) return;
  keystrokes++;
  secondChars++;
  if (t.length < w.length && c === w[t.length]) correctKeys++; else secondErrors++;
  typed[cur] = t + c;
  const m = MODES[mode];
  if (m.type === "words" && cur === words.length - 1 && typed[cur] === w) { cur = words.length; finish(); }
}

function backspace(wholeWord) {
  if (typed[cur].length > 0) {
    typed[cur] = wholeWord ? "" : typed[cur].slice(0, -1);
    return;
  }
  // Back into the previous word, only if it has a mistake.
  if (cur > 0 && typed[cur - 1] !== words[cur - 1]) {
    cur--;
    if (wholeWord) typed[cur] = "";
  }
}

function restart() { newTest(); }

// ───────────── Layout ─────────────

function layout() {
  const w = z.width, h = z.height;
  const pad = Math.max(14, w * 0.05);
  const size = code ? Math.min(20, Math.max(13, w / 21)) : Math.min(24, Math.max(15, w / 18));
  const adv = size * ADVANCE;
  const cols = Math.max(10, Math.floor((w - pad * 2) / adv));
  const lineH = size * 1.65;
  const top = Math.round(h * 0.46 - lineH * LINES / 2);
  return { w, h, pad, size, adv, cols, lineH, top };
}

// Each token's place: its line and first column. A code line starts a new line at its indent;
// anything too long for `cols` wraps (a wrapped code line keeps its indent).
function wrap(cols) {
  const places = [];
  let line = 0, indent = indents[0] || 0, col = indent;
  for (let i = 0; i < words.length; i++) {
    const len = Math.max(words[i].length, typed[i].length);
    if (i > 0 && seps[i - 1] === "\n") { line++; indent = indents[i]; col = indent; }
    else if (col > indent && col + len > cols) { line++; col = indent; }
    places.push({ line, col });
    col += len + 1;
  }
  return places;
}

function caretTarget(L, places) {
  const i = Math.min(cur, words.length - 1);
  const p = places[i];
  const col = cur >= words.length ? p.col + Math.max(words[i].length, typed[i].length) : p.col + typed[i].length;
  return { x: L.pad + col * L.adv, line: p.line };
}

// ───────────── Loop ─────────────

function setLoop(ms) {
  if (ms === loopMs) return;
  loopMs = ms;
  if (ms > 0) z.loop.start(ms); else z.loop.stop();
}

function counterText() {
  const m = MODES[mode];
  if (m.type === "time") return String(Math.max(0, Math.ceil(m.n - (started ? elapsed() / 1000 : 0))));
  return Math.min(code ? linesDone() : cur, m.n) + "/" + m.n;
}

function animate(dt) {
  const L = layout();
  const places = wrap(L.cols);
  const target = caretTarget(L, places);
  const topLine = Math.max(0, target.line - 1);
  const ty = target.line * L.lineH;
  if (snapNext) {
    caretX = target.x; caretY = ty; scroll = topLine; snapNext = false;
    return true;
  }
  const f = 1 - Math.exp(-dt / 45);
  const g = 1 - Math.exp(-dt / 90);
  let moving = false;
  const ease = (v, to, k, eps) => {
    if (Math.abs(to - v) < eps) return to;
    moving = true;
    return v + (to - v) * k;
  };
  caretX = ease(caretX, target.x, f, 0.25);
  caretY = ease(caretY, ty, f, 0.25);
  scroll = ease(scroll, topLine, g, 0.005);
  return moving;
}

// ───────────── Drawing ─────────────

function colors() {
  const dark = z.theme.dark;
  return {
    typed: "text",
    untyped: "secondary",
    wrong: dark ? "#ff6961" : "#d70015",
    extra: dark ? "#c2453d" : "#8a1c14",
    caret: "accent",
  };
}

function drawTest(g) {
  const L = layout(), C = colors();
  const places = wrap(L.cols);

  // The counter above the text.
  g.text(counterText(), L.pad, L.top - L.lineH * 0.75,
         { size: L.size * 1.05, weight: "semibold", color: started ? "accent" : "secondary", font: "mono" });

  g.save();
  g.clip(0, L.top, L.w, L.lineH * LINES);
  const first = Math.floor(scroll), lastLine = first + LINES;
  const yOf = line => L.top + (line - scroll) * L.lineH + L.lineH / 2;
  for (let i = 0; i < words.length; i++) {
    const p = places[i];
    if (p.line < first) continue;
    if (p.line > lastLine) break;
    const w = words[i], t = i <= cur ? typed[i] : "";
    const y = yOf(p.line);
    const len = Math.max(w.length, t.length);
    for (let j = 0; j < len; j++) {
      const x = L.pad + (p.col + j) * L.adv;
      let ch, color, underline = false;
      if (j >= w.length) { ch = t[j]; color = C.extra; underline = true; }
      else if (j < t.length) {
        ch = w[j];
        if (t[j] === w[j]) color = C.typed; else { color = C.wrong; underline = true; }
      } else { ch = w[j]; color = C.untyped; }
      g.text(ch, x + L.adv / 2, y, { size: L.size, color, font: "mono", align: "center" });
      if (underline) g.line(x + 1, y + L.size * 0.62, x + L.adv - 1, y + L.size * 0.62, { stroke: color, lineWidth: 1.5, cap: "round" });
    }
    // The end of a code line: a dim ↵ where Enter goes.
    if (seps[i] === "\n") {
      g.text("↵", L.pad + (p.col + len) * L.adv + L.adv / 2, y, { size: L.size * 0.8, color: C.untyped, font: "mono", align: "center" });
    }
    // A finished word with a mistake (or missing letters) is underlined as a whole.
    if (i < cur && t !== w) {
      const x0 = L.pad + p.col * L.adv, x1 = x0 + len * L.adv;
      g.line(x0, y + L.size * 0.78, x1, y + L.size * 0.78, { stroke: C.wrong, lineWidth: 1, cap: "round" });
    }
  }

  // The caret.
  if (!finished) {
    g.save();
    if (!started && !blinkOn) g.alpha(0);
    const cy = L.top + caretY - scroll * L.lineH + L.lineH / 2;
    g.rect(caretX - 1, cy - L.size * 0.62, 2, L.size * 1.24, { fill: C.caret, radius: 1 });
    g.restore();
  }
  g.restore();
}

function drawResults(g) {
  const L = layout(), C = colors(), r = result;
  const pad = L.pad, w = L.w, h = L.h;
  const big = Math.min(44, Math.max(30, w / 9));
  let y = Math.max(28, h * 0.09);

  // WPM and accuracy.
  g.text("wpm", pad, y, { size: 13, weight: "medium", color: "secondary" });
  g.text("acc", pad + w * 0.36, y, { size: 13, weight: "medium", color: "secondary" });
  y += big * 0.75;
  g.text(String(r.wpm), pad, y, { size: big, weight: "bold", color: "accent", font: "rounded" });
  g.text(r.acc + "%", pad + w * 0.36, y, { size: big, weight: "bold", color: "accent", font: "rounded" });
  g.text(r.isBest ? "new best" : "best " + r.best, w - pad, y - big * 0.28,
         { size: 13, weight: r.isBest ? "semibold" : "regular", color: r.isBest ? "accent" : "secondary", align: "right" });
  if (r.isBest) g.symbol("crown.fill", w - pad - 66, y - big * 0.28, 12, { color: "accent" });

  // The graph: WPM over the test (accent), raw WPM per second (faint) and seconds with errors (red marks).
  const gx = pad + 22, gw = w - pad - gx, gy = y + big * 0.75, gh = Math.max(70, h * 0.28);
  drawGraph(g, gx, gy, gw, gh, C);

  // The details.
  y = gy + gh + 34;
  const col = (w - pad * 2) / 3;
  const stat = (x, align, label, value) => {
    g.text(label, x, y, { size: 12, color: "secondary", align });
    g.text(value, x, y + 20, { size: 16, weight: "semibold", color: "text", font: "mono", align });
  };
  stat(pad, "left", "raw", String(r.raw));
  stat(pad + col, "left", "characters", r.correct + "/" + r.incorrect + "/" + r.extra + "/" + r.missed);
  stat(w - pad, "right", "time", (Math.round(r.seconds * 10) / 10) + "s");
  g.text("correct / wrong / extra / missed", pad + col, y + 38, { size: 10, color: "secondary" });
}

function drawGraph(g, x, y, w, h, C) {
  const n = samples.length;
  let top = 10;
  for (const s of samples) top = Math.max(top, s.wpm, s.raw);
  top = Math.ceil(top * 1.1 / 10) * 10;

  g.line(x, y + h, x + w, y + h, { stroke: "secondary", lineWidth: 0.5 });
  g.line(x, y, x + w, y, { stroke: "fill", lineWidth: 0.5 });
  g.text(String(top), x - 6, y, { size: 10, color: "secondary", align: "right", font: "mono" });
  g.text("0", x - 6, y + h, { size: 10, color: "secondary", align: "right", font: "mono" });
  g.text("1s", x, y + h + 12, { size: 10, color: "secondary", font: "mono" });
  g.text(Math.round(result.seconds) + "s", x + w, y + h + 12, { size: 10, color: "secondary", align: "right", font: "mono" });
  if (n === 0) return;

  const px = i => n === 1 ? x + w / 2 : x + (i / (n - 1)) * w;
  const py = v => y + h - Math.min(v, top) / top * h;
  const line = key => samples.map((s, i) => [px(i), py(s[key])]);
  if (n > 1) {
    g.path(line("raw"), { stroke: z.theme.dark ? "#ffffff40" : "#00000035", lineWidth: 1.5, cap: "round" });
    g.path(line("wpm"), { stroke: "accent", lineWidth: 2.5, cap: "round" });
  }
  samples.forEach((s, i) => {
    if (n === 1) g.circle(px(i), py(s.wpm), 3, { fill: "accent" });
    if (!s.errors) return;
    const ex = px(i), ey = py(s.raw), d = 3;
    g.line(ex - d, ey - d, ex + d, ey + d, { stroke: C.wrong, lineWidth: 1.5, cap: "round" });
    g.line(ex - d, ey + d, ex + d, ey - d, { stroke: C.wrong, lineWidth: 1.5, cap: "round" });
  });
}

// ───────────── The game ─────────────

function loadSettings() {
  const s = z.storage.get("settings") || {};
  if (typeof s.mode === "number" && s.mode >= 0 && s.mode < MODES.length) mode = s.mode;
  punctuation = !!s.punctuation;
  numbers = !!s.numbers;
  code = !!s.code;
  bests = z.storage.get("bests") || {};
}

function saveSettings() { z.storage.set("settings", { mode, punctuation, numbers, code }); }

function setMenu() {
  z.menu({
    title: "Test",
    items: MODES.map(m => m.type === "time" ? m.n + " s" : m.n + (code ? " lines" : " words")),
    selected: mode,
    onSelect(i) { mode = i; saveSettings(); restart(); },
    // Code has its own symbols and numbers, so it switches the other two off, and they switch it off.
    toggles: [{ label: "Punctuation", on: punctuation }, { label: "Numbers", on: numbers }, { label: "Code", on: code },
              { label: "Sound", on: z.sound.on() }],
    onToggle(i, on) {
      if (i === 3) { z.sound.set(on); return; }   // the same switch as the header's speaker
      if (i === 2) {
        code = on;
        if (on) { punctuation = false; numbers = false; }
      } else {
        if (i === 0) punctuation = on; else numbers = on;
        if (on) code = false;
      }
      saveSettings();
      setMenu();                                 // the switches' ticks, and "words" ↔ "lines"
      restart();
    },
  });
}

zephydian.game({
  start() {
    z.sound.preload(SOUND_FILES);
    loadSettings();
    setMenu();
    newTest();
  },

  draw(g) {
    if (finished && result) drawResults(g); else drawTest(g);
  },

  tick(dt) {
    if (finished) { setLoop(0); return; }
    let redraw = false;
    if (started && !finished) {
      const e = elapsed();
      while (e >= (samples.length + 1) * 1000) sample();
      const m = MODES[mode];
      if (m.type === "time" && e >= m.n * 1000) { finish(); return; }
    }
    const moving = animate(dt);
    if (moving) redraw = true;
    const counter = counterText();
    if (counter !== lastCounter) { lastCounter = counter; redraw = true; }
    if (!started) {
      // The caret blinks until the first key.
      blinkTime += dt;
      if (blinkTime >= 530) { blinkTime = 0; blinkOn = !blinkOn; redraw = true; }
    }
    if (redraw) z.redraw();
    // Smooth while the caret or the text moves; slower otherwise (the counter, the blink).
    setLoop(moving ? 16 : started ? 100 : 530);
  },

  key(e) {
    pressSound(e);
    const t = now();
    if (e.key === "Tab") { tabAt = t; return true; }
    if (e.key === "Enter" && tabAt && t - tabAt < RESTART_WINDOW) { tabAt = 0; restart(); return true; }
    tabAt = 0;
    if (finished) return e.key === "Enter";
    if (e.key === "Enter" && !code) return true;

    if (e.key === "Enter") {
      separator("\n");
    } else if (e.key === "Backspace") {
      if (started) backspace(e.option);
    } else if (e.key === " ") {
      separator(" ");
    } else if (e.char && !e.command) {
      typeChar(e.char);
    } else {
      return false;
    }
    blinkOn = true; blinkTime = 0;
    if (!finished) { setLoop(16); z.redraw(); }
    return true;
  },

  keyUp(e) {
    releaseSound(e);
    return true;
  },

  // The header's speaker button: the menu's Sound switch follows it.
  soundChanged() { setMenu(); },

  pause() {
    if (runningSince != null) { accumulated += now() - runningSince; runningSince = null; }
  },

  resume() {
    z.sound.preload(SOUND_FILES);   // the sound engine is ready before the next key
    if (started && !finished && runningSince == null) runningSince = now();
    snapNext = true;
    z.redraw();
  },
});
