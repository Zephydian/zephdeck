#!/usr/bin/env python3
"""Builds the games' sound files from Kenney's CC0 audio packs (https://kenney.nl), as listed in map.json.

usage: python3 -I scripts/sounds/build.py <folder with the unzipped kenney_* packs> [demo folder]

Each sound is decoded with macOS's afconvert, made mono 44.1 kHz, trimmed of silence at both ends,
given a short fade-out and evened out in loudness, then written as WAV to:
  - packs/games/<id>/assets/sounds/          (packs)
  - packs/sounds/<id>-sounds/assets/         (sound sets for built-in games installed from the Library)
  - app/Zephdeck/Resources/Sounds/<id>-<sound>.wav (built-in games that come installed: Snake, Stackr,
    Five; the app's resources end up in one folder, so their names carry the game's id)
With a demo folder, it also writes demo-<id>.wav: every sound of a game in turn, for listening.
"""
import json, os, subprocess, sys, tempfile, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACKS = {"switch", "crowns", "dusk", "thread", "quilt", "rungs", "hunch", "weave"}
IN_APP = {"snake", "stackr", "five"}
RATE = 44100
JINGLE_WORDS = ("win", "lose", "level", "right")


def locate(kenney, source):
    """map.json names a pack and a file; the file may sit in a subfolder of the pack (jingles do)."""
    pack, name = source.split("/")[0], os.path.basename(source)
    for dirpath, _, files in os.walk(os.path.join(kenney, pack)):
        if name in files:
            return os.path.join(dirpath, name)
    raise SystemExit(f"not found: {source}")


def decode(path):
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "x.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", path, out], check=True)
        with wave.open(out) as w:
            data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768
    return data


def tidy(x, event):
    loud = np.flatnonzero(np.abs(x) > 0.004)
    if len(loud):
        x = x[max(0, loud[0] - int(RATE * 0.002)): loud[-1] + int(RATE * 0.03)]
    fade = min(len(x), int(RATE * 0.02))
    x = x.copy()
    x[-fade:] *= np.linspace(1, 0, fade)
    # Even loudness: short effects to the same level, jingles a little softer so wins don't startle.
    rms = np.sqrt(np.mean(x ** 2)) or 1
    target = 0.07 if event.startswith(JINGLE_WORDS) else 0.11
    x *= target / rms
    peak = np.abs(x).max()
    if peak > 0.9:
        x *= 0.9 / peak
    return x


def write(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def folder(game):
    if game in PACKS:
        return os.path.join(ROOT, "packs/games", game, "assets/sounds")
    if game in IN_APP:
        return os.path.join(ROOT, "app/Zephdeck/Resources/Sounds")
    return os.path.join(ROOT, "packs/sounds", game + "-sounds", "assets")


def filename(game, event):
    return f"{game}-{event}.wav" if game in IN_APP else f"{event}.wav"


def main():
    kenney = sys.argv[1]
    demo = sys.argv[2] if len(sys.argv) > 2 else None
    table = json.load(open(os.path.join(os.path.dirname(__file__), "map.json")))
    for game, events in table.items():
        if game.startswith("_"):
            continue
        clips = []
        for event, source in events.items():
            x = tidy(decode(locate(kenney, source)), event)
            write(os.path.join(folder(game), filename(game, event)), x)
            clips.append(x)
        size = sum(os.path.getsize(os.path.join(folder(game), filename(game, e))) for e in events)
        print(f"{game:8} {len(events)} sounds, {size // 1024} KB → {os.path.relpath(folder(game), ROOT)}")
        if demo:
            gap = np.zeros(int(RATE * 0.55))
            write(os.path.join(demo, f"demo-{game}.wav"), np.concatenate([np.concatenate([c, gap]) for c in clips]))


if __name__ == "__main__":
    main()
