#!/usr/bin/env python3
"""Checks a rep-counter threshold against every recording we have, before it ships.

Two gates in `PoseRepCounter` were tuned on one recording each and both went
wrong on the next one: the close-up check never fired at all, and the crouch
check refused honest push-ups. This is the guard against a third. Any change to
`crouchHipLift`, `crouchKneeSplay`, `tooCloseWidth` or `blindDescentTop` should
be run through here first.

Usage:

    swiftc -O tools/posedump.swift -o /tmp/posedump
    /tmp/posedump "<recording>.MP4" <cropX> <cropY> <cropW> <cropH> 30 > /tmp/v18.csv
    python3 tools/replay-check.py /tmp

The crop is the camera window inside the recording, found by looking for the
green tracking border: see the header of posedump.swift. The segment labels
below are read off the frames by eye, once per recording, and are the only
judgement in here - everything else is measured.
"""

import csv
import statistics as st
import sys
from pathlib import Path

# (csv name, label, start second, end second, is this the cheat?)
SEGMENTS = [
    ("v16", "crouch, hands down, arms bending", 0, 999, True),
    ("v18", "crouch again, mid-set", 10, 16, True),
    ("v18", "honest, close, knees down", 4, 10, False),
    ("v18", "honest, the stretch a gate wrongly refused", 27, 31, False),
    ("v14", "honest, far too close to count", 0, 999, False),
    ("v15", "honest, knee push-ups", 0, 999, False),
    ("v22", "honest", 0, 999, False),
    ("v23", "honest, textbook", 0, 999, False),
]

CROUCH_HIP_LIFT = 0.25
CROUCH_KNEE_SPLAY = 0.35
AGREEMENT = 0.7


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def load(folder, name):
    path = Path(folder) / f"{name}.csv"
    if not path.exists():
        return None
    return list(csv.DictReader(path.open()))


def verdict(values, says):
    """The counter's own three hurdles: a pile of samples, a median past the
    line, and most of the samples agreeing with the median."""
    if len(values) < 3:
        return False
    if not says(st.median(values)):
        return False
    return sum(1 for v in values if says(v)) / len(values) >= AGREEMENT


def windows(rows, start, end):
    """One judgement per second of footage, over the descending frames only -
    the same window the gate judges, approximated by the lower 40% of elbow
    angles in each second."""
    rows = [r for r in rows if start <= float(r["t"]) < end]
    if not rows:
        return
    t, last = float(rows[0]["t"]), float(rows[-1]["t"])
    while t + 1.0 <= last + 1e-9:
        second = [r for r in rows if t <= float(r["t"]) < t + 1.0]
        angles = [(number(r["elbow"]), r) for r in second if number(r["elbow"]) is not None]
        t += 0.5
        if len(angles) < 6:
            continue
        angles.sort(key=lambda pair: pair[0])
        down = [r for _, r in angles[: max(1, int(0.4 * len(angles)))]]
        hips, splays = [], []
        for r in down:
            hip, knee, width = number(r["hipY"]), number(r["kneeY"]), number(r["swidth"])
            if hip is not None and knee is not None and width:
                hips.append((hip - knee) / width)
            kneeSpread, hipSpread = number(r["kneeSpread"]), number(r["hipSpread"])
            if kneeSpread is not None and hipSpread is not None:
                splays.append(kneeSpread - hipSpread)
        if len(hips) >= 3 and len(splays) >= 3:
            yield hips, splays


def main(folder):
    missing, failures = [], []
    print(f"crouch gate: hips above knees < {CROUCH_HIP_LIFT}, knees wider than hips > {CROUCH_KNEE_SPLAY}\n")
    for name, label, start, end, is_cheat in SEGMENTS:
        rows = load(folder, name)
        if rows is None:
            missing.append(name)
            continue
        judged = refused = 0
        for hips, splays in windows(rows, start, end):
            judged += 1
            if verdict(hips, lambda v: v < CROUCH_HIP_LIFT) and verdict(
                splays, lambda v: v > CROUCH_KNEE_SPLAY
            ):
                refused += 1
        if not judged:
            note = "nothing judgeable (legs out of shot)"
        elif is_cheat:
            note = f"caught {refused}/{judged}"
            if refused == 0:
                failures.append(f"{name} {label}: the cheat went uncaught")
        else:
            note = "clean" if refused == 0 else f"REFUSED {refused}/{judged} HONEST REPS"
            if refused:
                failures.append(f"{name} {label}: {refused} honest windows refused")
        print(f"  {'cheat ' if is_cheat else 'honest'}  {name:4s} {label:44s} {note}")

    if missing:
        print(f"\nno csv for: {', '.join(sorted(set(missing)))} (run posedump over those recordings)")
    if failures:
        print("\nFAILED:")
        for line in failures:
            print(f"  - {line}")
        return 1
    print("\nOK: every cheat caught, no honest rep refused.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/tmp"))
