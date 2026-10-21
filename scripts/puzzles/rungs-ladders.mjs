// Finds word ladders for Rungs: seven common words of the same length (4 or 5 letters), each one
// letter different from the next. The middle five can only be put in order one way (apart from
// upside down), so sorting them has one answer. Writing the clues is done by hand.
//
//   node scripts/puzzles/rungs-ladders.mjs 4 300 > ladders4.txt
//
// Prints one ladder per line, top to bottom, from the app's word lists (app/Zephydian/Resources/Words/).

import { readFileSync } from "node:fs";

const [len = "4", want = "300", seedArg = "20261024"] = process.argv.slice(2);
const L = Number(len);
const list = name => readFileSync(new URL("../../app/Zephydian/Resources/Words/" + name, import.meta.url), "utf8")
  .split("\n").map(w => w.trim()).filter(Boolean);
const common = new Set(list("wheel-words.txt")), valid = new Set(list("wheel-valid.txt"));
// No plurals or past tenses ("cats", "fared"): they make weak rungs and clumsy clues.
const plain = w => !(w.endsWith("s") && valid.has(w.slice(0, -1))) && !(w.endsWith("es") && valid.has(w.slice(0, -2)))
  && !(w.endsWith("ed") && (valid.has(w.slice(0, -1)) || valid.has(w.slice(0, -2))));
// Five-letter words also have to be on Five's answer list (everyday words, picked by hand).
const five = new Set(list("five-answers.txt"));
const words = [...common].filter(w => w.length === L && plain(w) && (L !== 5 || five.has(w)));

let seed = Number(seedArg);
const rand = () => {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

const diff = (a, b) => { let d = 0, at = -1; for (let i = 0; i < L; i++) if (a[i] !== b[i]) { d++; at = i; } return d === 1 ? at : -1; };
const near = new Map(words.map(w => [w, []]));
for (let i = 0; i < words.length; i++) {
  for (let j = i + 1; j < words.length; j++) {
    if (diff(words[i], words[j]) >= 0) { near.get(words[i]).push(words[j]); near.get(words[j]).push(words[i]); }
  }
}

function ladder() {
  const start = words[Math.floor(rand() * words.length)];
  const path = [start];
  while (path.length < 7) {
    const options = near.get(path[path.length - 1]).filter(w => !path.includes(w)
      // Each new word may only touch the previous one, so the order is the only one.
      && path.slice(0, -1).every(p => diff(p, w) < 0));
    if (!options.length) return null;
    path.push(options[Math.floor(rand() * options.length)]);
  }
  // Steps should change different letters, not the same spot every time.
  const spots = new Set();
  for (let k = 1; k < 7; k++) spots.add(diff(path[k - 1], path[k]));
  return spots.size >= Math.min(3, L) ? path : null;
}

const seen = new Set(), out = [];
for (let tries = 0; out.length < Number(want) && tries < 2000000; tries++) {
  const p = ladder();
  if (!p) continue;
  const key = [...p].sort().join();
  if (seen.has(key)) continue;
  seen.add(key);
  out.push(p.join(" "));
}
process.stdout.write(out.join("\n") + "\n");
