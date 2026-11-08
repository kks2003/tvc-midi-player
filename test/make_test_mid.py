#!/usr/bin/env python3
"""Tesztdal készítése (saját, szerzői jogtól mentes anyag): C-dúr skála
negyedekben, majd négy akkord (C, F, G7, C) egy hosszú basszushanggal, és egy
tempóváltás.  Kimenet: examples/teszt.mid"""
import os, struct, sys

def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.insert(0, 0x80 | (n & 0x7F))
        n >>= 7
    return bytes(out)

def track(events):
    """events: [(tick, bytes)] -> MTrk chunk"""
    events.sort(key=lambda e: e[0])
    body, last = bytearray(), 0
    for t, b in events:
        body += vlq(t - last) + b
        last = t
    body += vlq(0) + b"\xFF\x2F\x00"
    return b"MTrk" + struct.pack(">I", len(body)) + body

Q = 480
def note(ev, t, length, n, vel=100, ch=0):
    ev.append((t, bytes((0x90 | ch, n, vel))))
    ev.append((t + length, bytes((0x80 | ch, n, 0))))

conductor = [(0, b"\xFF\x51\x03" + (500000).to_bytes(3, "big"))]   # 120 BPM
melody, chords = [], []
t = 0
for n in (60, 62, 64, 65, 67, 69, 71, 72):            # skála, 8 x negyed
    note(melody, t, Q - 40, n)
    t += Q
conductor.append((t, b"\xFF\x51\x03" + (750000).to_bytes(3, "big")))  # 80 BPM
for ch in ((60, 64, 67), (60, 65, 69), (59, 62, 65, 67), (60, 64, 67)):
    for n in ch:
        note(chords, t, 2 * Q - 60, n, 90, 1)
    t += 2 * Q
note(chords, t - 8 * Q, 8 * Q, 36, 80, 1)              # C2 basszus (65 Hz)
note(chords, t, Q, 42, 0x7F, 9)                        # dob: alapból kimarad
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "examples", "teszt.mid")
with open(out, "wb") as f:
    f.write(b"MThd" + struct.pack(">IHHH", 6, 1, 3, Q))
    f.write(track(conductor) + track(melody) + track(chords))
print(out)
