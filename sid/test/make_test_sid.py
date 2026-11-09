#!/usr/bin/env python3
"""Kis teszt-SID (PSID v2) készítése: 8 hangos fűrészfog-skála, 32 képkockánként
új hang. A végén a $D400-as regiszterírásokból ellenőrizhető a lejátszó.
    python3 test/make_test_sid.py kimenet.sid [--cia T] [--songs N]
--cia T: CIA-időzítésű (speed bit = 1), az init a $DC04/$DC05-be T-t ír
(985248 / (T + 1) Hz). --songs N: N dal, a dal sorszáma a kezdőhang (A = dal - 1).
"""
import argparse, struct

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--cia", type=int, default=0)
ap.add_argument("--songs", type=int, default=1)
args = ap.parse_args()

LOAD = 0x1000
code = bytearray()
labels, fix = {}, []
def b(*xs): code.extend(xs)
def lab(n): labels[n] = LOAD + len(code)
def w(n): fix.append((len(code), n)); code.extend(b"\0\0")
def rel(n): fix.append((len(code), "rel:" + n)); code.append(0)

b(0x4C); w("init")
b(0x4C); w("play")
lab("init")
b(0x29, 0x07, 0x85, 0xFC)              # AND #7, STA idx: a dal szerinti kezdőhang
b(0xA9, 0x0F, 0x8D, 0x18, 0xD4)        # LDA #$0F, STA $D418
b(0xA9, 0x09, 0x8D, 0x05, 0xD4)        # AD
b(0xA9, 0xA0, 0x8D, 0x06, 0xD4)        # SR
b(0xA9, 0x00, 0x85, 0xFB)              # cnt=0 (zp $FB)
if args.cia:
    b(0xA9, args.cia & 255, 0x8D, 0x04, 0xDC, 0xA9, args.cia >> 8, 0x8D, 0x05, 0xDC)
b(0x60)
lab("play")
b(0xE6, 0xFB, 0xA5, 0xFB, 0x29, 0x1F)  # INC cnt; LDA cnt; AND #$1F
b(0xD0); rel("skip")
b(0xA6, 0xFC)                          # LDX idx
b(0xBD); w("flo"); b(0x8D, 0x00, 0xD4) # LDA flo,X; STA $D400
b(0xBD); w("fhi"); b(0x8D, 0x01, 0xD4)
b(0x20); w("gate")                     # JSR gate
b(0xE8, 0x8A, 0x29, 0x07, 0xAA, 0x86, 0xFC)  # INX TXA AND #7 TAX STX idx
b(0x60)
lab("skip")
b(0xC9, 0x10); b(0xD0); rel("ret")
b(0xA9, 0x20, 0x8D, 0x04, 0xD4)        # gate off
lab("ret"); b(0x60)
lab("gate")
b(0xA9, 0x21, 0x8D, 0x04, 0xD4, 0x60)
notes = [0x1167, 0x1389, 0x15ED, 0x173B, 0x1A13, 0x1D45, 0x20DA, 0x22CE]   # C4..C5 (PAL)
lab("flo"); b(*[n & 255 for n in notes])
lab("fhi"); b(*[n >> 8 for n in notes])
for pos, n in fix:
    if n.startswith("rel:"):
        d = labels[n[4:]] - (LOAD + pos + 1)
        assert -128 <= d < 128
        code[pos] = d & 255
    else:
        code[pos:pos + 2] = struct.pack("<H", labels[n])

hdr = bytearray(0x7C)
hdr[0:4] = b"PSID"
struct.pack_into(">HHHHHHHI", hdr, 4, 2, 0x7C, LOAD, 0, LOAD + 3, args.songs, 1,
                 0xFFFFFFFF if args.cia else 0)
hdr[0x16:0x16 + 9] = b"TVC teszt"
hdr[0x36:0x36 + 6] = b"Claude"
hdr[0x56:0x56 + 4] = b"2026"
open(args.out, "wb").write(bytes(hdr) + bytes(code))
