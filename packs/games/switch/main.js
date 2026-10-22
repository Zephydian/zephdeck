// Switch: flip a light and its four neighbours until the whole board is dark.
// Every board is made by flipping a solved (dark) board at random, so it can always be solved,
// and "par" is the number of flips used to make it (the best solution is never longer).

const N = 5;
const LEVELS = [
  { name: "Easy", flips: 4 },
  { name: "Medium", flips: 8 },
  { name: "Hard", flips: 12 },
];
const MAX_UNDO = 100;

// Sounds (Kenney, CC0), played only while game sounds are on (Settings, and this game's speaker).
const SOUND_NAMES = ["press", "win"];
const sound = (name, volume) => z.sound.play("sounds/" + name + ".wav", { volume: volume == null ? 1 : volume });
const preloadSounds = () => z.sound.preload(SOUND_NAMES.map(n => "sounds/" + n + ".wav"));


let level = 0;       // index into LEVELS
let board = [];      // N*N booleans, true = lit
let moves = 0;
let par = 0;
let history = [];    // cells flipped, for undo
let cursor = 12;     // keyboard focus (starts in the middle)
let solved = false;
let showCursor = false;  // the focus ring appears once the arrow keys are used
let marked = [];         // cells ringed by Hint (one) or Give up (all of a solution)
let gaveUp = false;

// ───────────── Rules ─────────────

function flip(cells, i) {
  const r = Math.floor(i / N), c = i % N;
  for (const [dr, dc] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const rr = r + dr, cc = c + dc;
    if (rr >= 0 && rr < N && cc >= 0 && cc < N) cells[rr * N + cc] = !cells[rr * N + cc];
  }
}

function newBoard() {
  const flips = LEVELS[level].flips;
  // Pick distinct cells (flipping one twice would cancel out), and never hand out a dark board.
  do {
    board = Array(N * N).fill(false);
    const picked = new Set();
    while (picked.size < flips) picked.add(Math.floor(Math.random() * N * N));
    picked.forEach(i => flip(board, i));
  } while (board.every(on => !on));
  par = flips;
  moves = 0;
  history = [];
  solved = false;
  gaveUp = false;
  marked = [];
  z.overlay(null);
  setActions();
  update();
}

function press(i) {
  if (solved) return;
  sound("press", 0.8);
  marked = marked.filter(c => c !== i);
  flip(board, i);
  history.push(i);
  if (history.length > MAX_UNDO) history.shift();
  moves++;
  if (board.every(on => !on)) win();
  update();
}

function win() {
  sound("win");
  solved = true;
  setActions();
  const stats = z.storage.get("stats") || {};
  const key = LEVELS[level].name;
  const best = stats[key];
  const isBest = best == null || moves < best;
  if (isBest) stats[key] = moves;
  stats.solved = (stats.solved || 0) + 1;
  z.storage.set("stats", stats);
  const underPar = moves <= par ? "At or under par!" : `Par is ${par}.`;
  z.overlay({
    title: isBest && best != null ? "New best!" : "All dark!",
    subtitle: `${moves} ${moves === 1 ? "move" : "moves"}. ${underPar}`,
    buttons: [{ label: "Next board", prominent: true, action: newBoard }],
  });
}

// ───────────── Hint and Give up ─────────────

// The fewest presses that turn this board dark. Pressing a cell flips it and its neighbours, so
// this is a set of equations over on/off (each press once at most); 5×5 has four answers to choose from.
function solution() {
  const size = N * N;
  // rows[i] = which presses flip cell i, plus whether cell i is lit (the last column).
  const rows = [];
  for (let i = 0; i < size; i++) {
    const row = Array(size + 1).fill(0);
    const r = Math.floor(i / N), c = i % N;
    for (const [dr, dc] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const rr = r + dr, cc = c + dc;
      if (rr >= 0 && rr < N && cc >= 0 && cc < N) row[rr * N + cc] = 1;
    }
    row[size] = board[i] ? 1 : 0;
    rows.push(row);
  }
  const pivotOf = [];
  let rank = 0;
  for (let col = 0; col < size && rank < size; col++) {
    const p = rows.findIndex((row, k) => k >= rank && row[col]);
    if (p < 0) continue;
    [rows[rank], rows[p]] = [rows[p], rows[rank]];
    for (let k = 0; k < size; k++) {
      if (k !== rank && rows[k][col]) for (let j = col; j <= size; j++) rows[k][j] ^= rows[rank][j];
    }
    pivotOf[rank] = col;
    rank++;
  }
  const free = [];
  for (let col = 0, k = 0; col < size; col++) { if (pivotOf[k] === col) k++; else free.push(col); }
  let best = null;
  for (let mask = 0; mask < 1 << free.length; mask++) {
    const x = Array(size).fill(0);
    free.forEach((col, b) => { x[col] = (mask >> b) & 1; });
    for (let k = rank - 1; k >= 0; k--) {
      let v = rows[k][size];
      for (let j = pivotOf[k] + 1; j < size; j++) if (rows[k][j]) v ^= x[j];
      x[pivotOf[k]] = v;
    }
    const presses = x.flatMap((v, i) => (v ? [i] : []));
    if (!best || presses.length < best.length) best = presses;
  }
  return best || [];
}

function setActions() {
  z.actions([
    { id: "hint", label: "Hint", symbol: "lightbulb", enabled: !solved, help: "Ring a light worth pressing", onPress() {
      if (solved) return;
      const presses = solution();
      if (presses.length) marked = [presses[0]];
      z.redraw();
    } },
    { id: "giveUp", label: "Give up", symbol: "eye", enabled: !solved, help: "Show the presses that clear this board",
      confirm: { title: "Give up?", message: "You’ll see which lights to press to clear this board.", button: "Give Up" },
      onPress() {
        if (solved) return;
        marked = solution();
        gaveUp = true;
        solved = true;
        setActions();
        z.overlay({
          title: "Here’s how",
          subtitle: `Press the ${marked.length} ringed ${marked.length === 1 ? "light" : "lights"} to clear it.`,
          buttons: [{ label: "Next board", prominent: true, action: newBoard }, { label: "Look", action() { z.overlay(null); } }],
        });
        update();
      } },
  ]);
}

// ───────────── Saving and the header ─────────────

function update() {
  const best = (z.storage.get("stats") || {})[LEVELS[level].name];
  z.score(`${moves} · par ${par}` + (best != null ? ` · best ${best}` : ""));
  z.storage.set("game", { level, board, moves, par, history, cursor, solved });
  z.redraw();
}

function setMenu() {
  z.menu({
    title: "Difficulty",
    items: LEVELS.map(l => `${l.name} (par ${l.flips})`),
    selected: level,
    onSelect(i) {
      level = i;
      z.storage.set("level", level);
      setMenu();
      newBoard();
    },
  });
}

// ───────────── Layout ─────────────

function layout() {
  const size = Math.min(z.width, z.height) - 16;
  const cell = size / N;
  return { cell, x0: (z.width - size) / 2, y0: (z.height - size) / 2 };
}

function cellAt(x, y) {
  const { cell, x0, y0 } = layout();
  const c = Math.floor((x - x0) / cell), r = Math.floor((y - y0) / cell);
  return r >= 0 && r < N && c >= 0 && c < N ? r * N + c : -1;
}

// ───────────── The game ─────────────

zephdeck.game({
  start() {
    preloadSounds();
    const saved = z.storage.get("game");
    if (saved && Array.isArray(saved.board) && saved.board.length === N * N) {
      ({ level, board, moves, par, history, cursor, solved } = saved);
      setMenu();
      if (solved) { solved = false; newBoard(); } else { setActions(); update(); }
    } else {
      level = z.storage.get("level") || 0;
      setMenu();
      newBoard();
    }
  },

  draw(g) {
    const { cell, x0, y0 } = layout();
    const gap = Math.max(4, cell * 0.08), radius = cell * 0.22;
    board.forEach((on, i) => {
      const x = x0 + (i % N) * cell + gap / 2, y = y0 + Math.floor(i / N) * cell + gap / 2, s = cell - gap;
      g.rect(x, y, s, s, { radius, fill: on ? "accent" : "fill" });
      if (on) {
        // A soft highlight, so lit cells glow a little (and differ by more than color alone).
        g.circle(x + s / 2, y + s / 2, s * 0.16, { fill: "rgba(255, 255, 255, 0.55)" });
      }
    });
    // Hinted cells (or, after giving up, the whole answer) get a ring.
    for (const i of marked) {
      const x = x0 + (i % N) * cell + gap / 2, y = y0 + Math.floor(i / N) * cell + gap / 2, s = cell - gap;
      g.rect(x + 3, y + 3, s - 6, s - 6, { radius: radius - 2, stroke: board[i] ? "#ffffff" : "accent", lineWidth: 3 });
    }
    if (!showCursor) return;
    // Keyboard focus ring
    const x = x0 + (cursor % N) * cell + gap / 2 - 2, y = y0 + Math.floor(cursor / N) * cell + gap / 2 - 2;
    g.rect(x, y, cell - gap + 4, cell - gap + 4, { radius: radius + 2, stroke: "text", lineWidth: 2 });
  },

  click(e) {
    const i = cellAt(e.x, e.y);
    if (i < 0) return;
    cursor = i;
    showCursor = false;
    press(i);
  },

  key(e) {
    const r = Math.floor(cursor / N), c = cursor % N;
    if (e.key.startsWith("Arrow") || e.key === " ") showCursor = true;
    switch (e.key) {
      case "ArrowUp": cursor = Math.max(r - 1, 0) * N + c; break;
      case "ArrowDown": cursor = Math.min(r + 1, N - 1) * N + c; break;
      case "ArrowLeft": cursor = r * N + Math.max(c - 1, 0); break;
      case "ArrowRight": cursor = r * N + Math.min(c + 1, N - 1); break;
      case " ": press(cursor); return true;
      case "r": newBoard(); return true;
      default: return false;
    }
    z.redraw();
    return true;
  },

  undo() {
    if (solved || history.length === 0) return false;
    const i = history.pop();
    flip(board, i);
    moves = Math.max(0, moves - 1);
    update();
    return true;
  },
});
