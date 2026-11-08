#!/usr/bin/env python3
"""Builds res://assets/sounds/*.ogg from CC0 recordings on OpenGameArt.

Sources (all CC0):
  * The Free Firearm Sound Library  https://opengameart.org/content/the-free-firearm-sound-library
  * Gun reload sounds              https://opengameart.org/content/gun-reload-sounds
  * Handgun reload sound effect    https://opengameart.org/content/handgun-reload-sound-effect
  * Shotgun reload sound effects   https://opengameart.org/content/shotgun-reload-sound-effects
  * 2 Gun Reloads                  https://opengameart.org/content/2-gun-reloads

Usage: python3 tools/build_sounds.py <work_dir>
Downloads into <work_dir> (skips existing files), needs ffmpeg and 7z on PATH.
For each gun: finds the first shot, trims it with its natural tail (cutting before any
following shot), normalises, and writes a near (first person) and far (third person) version.
"""
import os
import subprocess
import sys
import urllib.request
import zipfile

import numpy as np

UA = {"User-Agent": "breachline-asset-fetch/1.0"}
OGA = "https://opengameart.org/sites/default/files/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
SR = 44100

# weapon sound key: (folder, near file, far file, seconds)
SHOTS = {
    "shot_m9": ("Walther PPQ", "X_39P.wav", "X_31P.wav", 1.3),
    "shot_raptor": ("Bersa", "F_47P.wav", "F_41P.wav", 1.0),
    "shot_hawk": ("1911", "A_42P.wav", "A_34P.wav", 1.6),
    "shot_vespa": ("Carl Gustav M45", "G_31P.wav", "G_20P.wav", 1.0),
    "shot_mako": ("PPSh", "P_30P.wav", "P_16P.wav", 1.1),
    "shot_breacher": ("Nova", "O_21P.wav", "O_17P.wav", 2.0),
    "shot_kv74": ("AK-47", "C_28P.wav", "C_31P.wav", 1.6),
    "shot_ar7": ("AR-15", "D_32P.wav", "D_24P.wav", 1.5),
    "shot_hornet": ("SKS", "U_14P.wav", "U_19P.wav", 1.5),
    "shot_sentry": ("Savage 10 .300 Blackout", "T_27P.wav", "T_17P.wav", 1.9),
    "shot_longbow": ("Mosin Nagant", "M_21P.wav", "M_26P.wav", 2.6),
    "shot_thresher": ("1917", "B_24P.wav", "B_16P.wav", 1.5),
}

# other sounds: key: (relative source path, start offset s (None = onset), seconds)
OTHER = {
    "reload_pistol": ("reload.wav", 0.0, None),
    "reload_rifle": ("assaultriflereload1_0.wav", 0.0, None),
    "reload_smg": ("gunreload1.wav", 0.0, None),
    "reload_alt": ("reloads/gun_reload.2.ogg", 0.0, None),
    "bolt": ("shotguncock_0.wav", 0.0, None),
    "pump": ("shotgun/ShotgunSounds/Rack.mp3", 0.0, None),
    "shell_insert": ("shotgun/ShotgunSounds/Subsequent Shells.mp3", None, 0.55),
}


def fetch(url, path):
    if os.path.exists(path):
        return
    print("downloading", url)
    data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900).read()
    with open(path, "wb") as f:
        f.write(data)


def prepare(work):
    os.makedirs(work, exist_ok=True)
    fetch(OGA + "Prepared%20SFX%20Library.7z", os.path.join(work, "firearms.7z"))
    for name in ["assaultriflereload1_0.wav", "gunreload1.wav", "shotguncock_0.wav", "reload.wav"]:
        fetch(OGA + name, os.path.join(work, name))
    fetch(OGA + "shotgunsounds.zip", os.path.join(work, "shotgunsounds.zip"))
    fetch(OGA + "gun_reload_-_starninjas.zip", os.path.join(work, "gunreloads.zip"))
    if not os.path.isdir(os.path.join(work, "Prepared SFX Library")):
        subprocess.run(["7z", "x", "-y", "-o" + work, os.path.join(work, "firearms.7z")], check=True, stdout=subprocess.DEVNULL)
    zipfile.ZipFile(os.path.join(work, "shotgunsounds.zip")).extractall(os.path.join(work, "shotgun"))
    zipfile.ZipFile(os.path.join(work, "gunreloads.zip")).extractall(os.path.join(work, "reloads"))


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, stdout=subprocess.PIPE).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def save_ogg(x, path, quality=6):
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), path], input=x.tobytes(), check=True)


def envelope(x, win=0.003):
    n = max(1, int(win * SR))
    return np.convolve(np.abs(x), np.ones(n) / n, mode="same")


def cut_shot(x, seconds, peak=0.95, next_thresh=0.7, min_gap=0.3):
    env = envelope(x)
    top = env.max()
    onset = int(np.argmax(env > top * 0.2))
    start = max(0, onset - int(0.003 * SR))
    end = min(len(x), start + int(seconds * SR))
    # Stop before a following shot (a new strong transient after min_gap seconds).
    after = env[start + int(min_gap * SR):end]
    later = np.nonzero(after > top * next_thresh)[0]
    if later.size:
        end = start + int(min_gap * SR) + int(later[0]) - int(0.01 * SR)
    y = x[start:end].copy()
    # Remove DC, short fade in, smooth exponential fade over the tail.
    y -= np.mean(y[: int(0.002 * SR)]) if len(y) > 100 else 0.0
    fi = int(0.0015 * SR)
    y[:fi] *= np.linspace(0, 1, fi)
    n = len(y)
    tail_start = int(n * 0.35)
    t = np.linspace(0, 1, n - tail_start)
    y[tail_start:] *= np.exp(-2.5 * t) * (1 - t) ** 0.5
    y *= peak / max(1e-6, np.abs(y).max())
    return y


def punch_up(y, drive=3.0, sub_hz=62.0, sub_gain=0.35):
    """Game-style processing for first-person shots: saturating compression so the body and
    tail carry, plus a short low-frequency thump for weight on small speakers."""
    out = np.tanh(drive * y) / np.tanh(drive)
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    freq = sub_hz * (1.0 + 0.8 * np.exp(-t / 0.02))
    thump = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / 0.035) * sub_gain
    out[:n] += thump[: len(out[:n])]
    return out * (0.97 / max(1e-6, np.abs(out).max()))


def main():
    work = sys.argv[1] if len(sys.argv) > 1 else "/tmp/breachline_sound_src"
    prepare(work)
    os.makedirs(OUT, exist_ok=True)
    lib = os.path.join(work, "Prepared SFX Library")
    for key, (folder, near, far, secs) in SHOTS.items():
        xn = load(os.path.join(lib, folder, near))
        save_ogg(punch_up(cut_shot(xn, secs, 0.97)), os.path.join(OUT, key + ".ogg"))
        xf = load(os.path.join(lib, folder, far))
        save_ogg(punch_up(cut_shot(xf, secs + 0.5, 0.9, 0.85), drive=2.0, sub_gain=0.15), os.path.join(OUT, key + "_far.ogg"))
        print("built", key)
    for key, (rel, offset, secs) in OTHER.items():
        x = load(os.path.join(work, rel))
        if offset is None:
            y = cut_shot(x, secs, 0.9, 0.9, 0.2)
        else:
            y = x[int(offset * SR):]
            y = y * (0.9 / max(1e-6, np.abs(y).max()))
            fo = int(0.03 * SR)
            y[-fo:] *= np.linspace(1, 0, fo)
        save_ogg(y, os.path.join(OUT, key + ".ogg"))
        print("built", key)


if __name__ == "__main__":
    main()
