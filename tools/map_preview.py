#!/usr/bin/env python3
"""Validate a BREACHLINE map JSON and render a top-down preview PNG.
Usage: python3 tools/map_preview.py maps/outpost.json out.png"""
import json, sys
from PIL import Image, ImageDraw

COLORS = {
    '#': (90, 80, 70), 'X': (110, 110, 110), 'W': (60, 120, 160), '-': (150, 140, 120), '|': (150, 140, 120),
    '+': (150, 140, 120), 'D': (160, 90, 40), 'w': (200, 140, 60), '=': (170, 170, 170), 'c': (140, 110, 60),
    'C': (110, 80, 40), 'k': (40, 120, 60), 'v': (200, 60, 60), 'o': (60, 60, 160), 'P': (130, 130, 130),
    'L': (255, 230, 120), 'h': (220, 40, 40), 't': (90, 90, 90), 'g': (200, 200, 60), 'j': (60, 160, 60), 'y': (30, 30, 30),
    'B': (120, 70, 40), 's': (255, 60, 200),
    '.': (215, 200, 170), ',': (180, 170, 150), '^': (230, 220, 120), ' ': (215, 200, 170),
}
VALID = set(COLORS)

def main():
    m = json.load(open(sys.argv[1]))
    g = m["grid"]
    w = len(g[0])
    ok = True
    for i, row in enumerate(g):
        if len(row) != w:
            print(f"row {i} has length {len(row)} (expected {w}): {row!r}"); ok = False
        bad = set(row) - VALID
        if bad:
            print(f"row {i} has invalid chars {bad}"); ok = False
    if not all(c in '#X' for c in g[0] + g[-1]) or not all(r[0] in '#X' and r[-1] in '#X' for r in g):
        print("border is not closed"); ok = False
    S = 16
    img = Image.new("RGB", (w * S, len(g) * S))
    d = ImageDraw.Draw(img)
    for r, row in enumerate(g):
        for c, ch in enumerate(row):
            d.rectangle([c * S, r * S, c * S + S - 1, r * S + S - 1], fill=COLORS.get(ch, (255, 0, 255)))
    def rect(rc, col, label):
        c0, r0, c1, r1 = rc[:4]
        d.rectangle([c0 * S, r0 * S, (c1 + 1) * S - 1, (r1 + 1) * S - 1], outline=col, width=3)
        d.text((c0 * S + 4, r0 * S + 2), label, fill=col)
    for k, v in m.get("sites", {}).items():
        rect(v, (255, 40, 40), "SITE " + k)
    rect(m["spawn"]["atk"], (255, 120, 0), "ATK")
    rect(m["spawn"]["def"], (0, 120, 255), "DEF")
    for p in m.get("platforms", []):
        rect(p, (255, 0, 255), "plat %.1f" % p[4])
    for p in m.get("ramps", []):
        rect(p, (0, 255, 255), "ramp " + p[6])
    img.save(sys.argv[2])
    print("OK" if ok else "ERRORS", f"{w}x{len(g)}")

main()
