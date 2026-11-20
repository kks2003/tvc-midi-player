#!/usr/bin/env python3
# tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
# Copyright (C) 2026 kks2003 és a közreműködők
#
# Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
# Foundation által kiadott GNU General Public License 2. vagy (választás
# szerint) bármely későbbi változata szerint. A programot a hasznosság
# reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
#
"""midi2tvc.py - Standard MIDI fájl (.mid) -> TVC lejátszó adat (song.bin).

A kimenet formátumát a player.asm eleje írja le. Röviden: 8 bájtos fejléc,
128 bejegyzéses PITCH-tábla, majd tick-alapú (képkockánkénti, ~49,7 Hz)
eseménylista.

Üzemmódok:
  mono  egyszólamúsítás: minden pillanatban egy hang szól (a legmagasabb,
        a legmélyebb vagy a legutóbb leütött, --prio)
  arp   akkordok arpeggióval: legfeljebb --max-notes hang, a lejátszó
        --arp-speed tickenként lép közöttük

  poly  többszólamú (player_poly.asm): 3 négyszög szólam + zajcsatorna,
        szoftveres keverés a DAC-módba kapcsolt hangerőregiszteren; a
        szólamokat a legmagasabb, a legmélyebb, majd a következő legmagasabb
        hang kapja

Dob (10. MIDI csatorna, --drums synth, alap): a GM dobhangok szintetizált
dobokká alakulnak (lábdob és tamok: lefelé csúszó hang; pergő, cin, crash:
zaj a DAC-módba kapcsolt hangerőregiszteren). Egy dobütés 1..6 tickre
átveszi a csatornát.

Csak a Python szabványos könyvtárát használja.
"""
import argparse
import math
import os
import struct
import sys

TVC_CLOCK = 195312.5          # f = 195312,5 / (4096 - PITCH)
FRAME_RATE = 49.76            # a kurzor-IT (képkocka) frekvenciája
DRUM_CHANNEL = 9              # a 10. MIDI csatorna


# --------------------------------------------------------------------------
# MIDI olvasás
# --------------------------------------------------------------------------
def read_vlq(data, pos):
    value = 0
    while True:
        b = data[pos]
        pos += 1
        value = (value << 7) | (b & 0x7F)
        if not b & 0x80:
            return value, pos


def parse_midi(data):
    """-> (division, [ (tick, order, kind, ch, a, b) ... ]) az összes sávból.

    kind: 'on', 'off', 'cc', 'tempo'.  'order' a sávon belüli sorrend, hogy az
    azonos időpontú események sorrendje megmaradjon.
    """
    if data[:4] != b"MThd":
        raise ValueError("nem Standard MIDI fájl (hiányzik az MThd)")
    hlen, fmt, ntrks, division = struct.unpack(">IHHH", data[4:14])
    if division & 0x8000:
        raise ValueError("SMPTE időalapú MIDI nem támogatott")
    pos = 8 + hlen
    events = []
    order = 0
    for _ in range(ntrks):
        while pos + 8 <= len(data) and data[pos:pos + 4] != b"MTrk":
            # ismeretlen chunk átlépése
            clen = struct.unpack(">I", data[pos + 4:pos + 8])[0]
            pos += 8 + clen
        if pos + 8 > len(data):
            break
        tlen = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        p = pos + 8
        end = min(p + tlen, len(data))
        pos = p + tlen
        tick = 0
        status = 0
        while p < end:
            delta, p = read_vlq(data, p)
            tick += delta
            b = data[p]
            if b & 0x80:
                status = b
                p += 1
            elif status == 0:
                raise ValueError("futó státusz előzmény nélkül")
            if status == 0xFF:
                mtype = data[p]
                mlen, p = read_vlq(data, p + 1)
                if mtype == 0x51 and mlen == 3:
                    tempo = (data[p] << 16) | (data[p + 1] << 8) | data[p + 2]
                    events.append((tick, order, "tempo", 0, tempo, 0))
                elif mtype == 0x2F:
                    p += mlen
                    break
                p += mlen
                status = 0
                order += 1
                continue
            if status in (0xF0, 0xF7):
                slen, p = read_vlq(data, p)
                p += slen
                status = 0
                continue
            hi, ch = status & 0xF0, status & 0x0F
            if hi in (0xC0, 0xD0):
                if hi == 0xC0:
                    events.append((tick, order, "prog", ch, data[p], 0))
                    order += 1
                p += 1
                continue
            a, v = data[p], data[p + 1]
            p += 2
            if hi == 0x90 and v > 0:
                events.append((tick, order, "on", ch, a, v))
            elif hi == 0x80 or hi == 0x90:
                events.append((tick, order, "off", ch, a, 0))
            elif hi == 0xE0:
                events.append((tick, order, "pb", ch, a, v))
            elif hi == 0xB0:
                events.append((tick, order, "cc", ch, a, v))
            order += 1
    events.sort(key=lambda e: (e[0], e[1]))
    return division, events


def tick_to_seconds(division, events):
    """MIDI tick -> másodperc függvény a tempótérkép alapján."""
    tempo_map = [(0, 0.0, 500000)]   # (tick, sec, us/negyed)
    for tick, _, kind, _, tempo, _ in events:
        if kind != "tempo":
            continue
        t0, s0, tp = tempo_map[-1]
        s = s0 + (tick - t0) * tp / (division * 1e6)
        if tick == t0:
            tempo_map[-1] = (t0, s0, tempo)
        else:
            tempo_map.append((tick, s, tempo))

    def conv(tick):
        lo, hi = 0, len(tempo_map) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if tempo_map[mid][0] <= tick:
                lo = mid
            else:
                hi = mid - 1
        t0, s0, tp = tempo_map[lo]
        return s0 + (tick - t0) * tp / (division * 1e6)
    return conv


def collect_notes(division, events, channels, transpose, speed):
    """-> [(start_sec, end_sec, note, velocity, ch, program)] a kitartó pedállal
    együtt (program: a hang leütésekor érvényes hangszer, 0..127)."""
    conv = tick_to_seconds(division, events)
    open_notes = {}               # (ch, note) -> [(start, vel), ...]
    sustain = [False] * 16
    held = {}                     # pedál miatt kitartott: (ch, note) -> [(start, vel)]
    volume = [100] * 16
    expression = [127] * 16
    program = [0] * 16
    notes = []

    def finish(ch, note, start, vel, end):
        vel, pg = vel
        notes.append((start, end, note, vel * volume[ch] * expression[ch] / (127 * 127), ch, pg))

    for tick, _, kind, ch, a, b in events:
        t = conv(tick) / speed
        if kind == "tempo":
            continue
        if channels is not None and ch not in channels:
            continue
        if kind == "prog":
            program[ch] = a
            continue
        if kind == "cc":
            if a == 7:
                volume[ch] = b
            elif a == 11:
                expression[ch] = b
            elif a == 64:
                down = b >= 64
                if sustain[ch] and not down:
                    for (c, n), lst in list(held.items()):
                        if c == ch:
                            for st, v in lst:
                                finish(c, n, st, v, t)
                            del held[(c, n)]
                sustain[ch] = down
            elif a in (120, 123):     # all sound / notes off
                for (c, n), lst in list(open_notes.items()) + list(held.items()):
                    if c == ch:
                        for st, v in lst:
                            finish(c, n, st, v, t)
                for d in (open_notes, held):
                    for key in [k for k in d if k[0] == ch]:
                        del d[key]
            continue
        note = a + transpose
        if not 0 <= note <= 127:
            continue
        key = (ch, note)
        if kind == "on":
            # ugyanaz a hang pedál alatt újra leütve: a régi véget ér
            if key in held:
                for st, v in held.pop(key):
                    finish(ch, note, st, v, t)
            open_notes.setdefault(key, []).append((t, (b, program[ch])))
        else:
            lst = open_notes.get(key)
            if not lst:
                continue
            st, v = lst.pop(0)
            if not lst:
                del open_notes[key]
            if sustain[ch]:
                held.setdefault(key, []).append((st, v))
            else:
                finish(ch, note, st, v, t)
    end = conv(events[-1][0]) / speed if events else 0.0
    for d in (open_notes, held):
        for (ch, n), lst in d.items():
            for st, v in lst:
                finish(ch, n, st, v, end)
    notes.sort()
    return notes


# ---- hangmagasság-hajlítás, vibrato (--bend) ------------------------------------
# A frekvencia egész számokkal: a hangjegy fázisnövekménye * 2^(cent/1200), a
# centek 0..99-re táblából (a webes konverterrel bájtra azonos eredményért).
CENT_RATIO = [65536, 65574, 65612, 65650, 65688, 65726, 65764, 65802, 65840, 65878, 65916, 65954, 65992, 66030, 66068, 66106, 66144, 66183, 66221, 66259, 66297, 66336, 66374, 66412, 66451, 66489, 66528, 66566, 66605, 66643, 66682, 66720, 66759, 66797, 66836, 66874, 66913, 66952, 66990, 67029, 67068, 67107, 67145, 67184, 67223, 67262, 67301, 67340, 67378, 67417, 67456, 67495, 67534, 67573, 67612, 67651, 67691, 67730, 67769, 67808, 67847, 67886, 67926, 67965, 68004, 68043, 68083, 68122, 68161, 68201, 68240, 68280, 68319, 68359, 68398, 68438, 68477, 68517, 68556, 68596, 68635, 68675, 68715, 68755, 68794, 68834, 68874, 68914, 68953, 68993, 69033, 69073, 69113, 69153, 69193, 69233, 69273, 69313, 69353, 69393]
VIB_SIN = [0, 383, 707, 924, 1000, 924, 707, 383, 0, -383, -707, -924, -1000, -924, -707, -383]
VIB_HZ = 5.5                        # a vibrato sebessége
VIB_DEPTH = 50                      # cent teljes modulációnál


def collect_controls(division, events, channels, speed):
    """-> ({cs: [(mp, cent)]} hajlítás, {cs: [(mp, 0..127)]} moduláció).  A
    hajlítási tartomány az RPN 0-ból (alap: 2 félhang)."""
    conv = tick_to_seconds(division, events)
    rng = [2] * 16
    rpn = [[127, 127] for _ in range(16)]
    bends, mods = {}, {}
    for tick, _, kind, ch, a, b in events:
        if channels is not None and ch not in channels:
            continue
        t = conv(tick) / speed
        if kind == "cc":
            if a == 101:
                rpn[ch][0] = b
            elif a == 100:
                rpn[ch][1] = b
            elif a == 6 and rpn[ch] == [0, 0]:
                rng[ch] = b
            elif a == 1:
                mods.setdefault(ch, []).append((t, b))
            elif a == 121:              # minden vezérlő alapra
                bends.setdefault(ch, []).append((t, 0))
                mods.setdefault(ch, []).append((t, 0))
        elif kind == "pb":
            val = ((b << 7) | a) - 8192
            bends.setdefault(ch, []).append((t, int(round(val * rng[ch] * 100 / 8192.0))))
    return bends, mods


def control_ticks(ctl, shift, rate):
    """{cs: [(mp, érték)]} -> {cs: ([tick], [érték])}; a rész előtti értékek a 0. tickre"""
    out = {}
    for ch, lst in ctl.items():
        ts, vs = [], []
        for t, v in lst:
            tk = max(0, int(round((t - shift) * rate)))
            if ts and ts[-1] == tk:
                vs[-1] = v
            else:
                ts.append(tk)
                vs.append(v)
        out[ch] = (ts, vs)
    return out


def control_at(ctl, ch, t):
    """a csatorna vezérlőértéke a t. tickben (0, ha nincs)"""
    c = ctl.get(ch)
    if not c:
        return 0
    ts, vs = c
    lo, hi = 0, len(ts)
    while lo < hi:
        mid = (lo + hi) // 2
        if ts[mid] <= t:
            lo = mid + 1
        else:
            hi = mid
    return vs[lo - 1] if lo else 0


def bent_freq(ftab, note, cents):
    """a hangjegy fázisnövekménye a hajlítással (cent)"""
    n = note + cents // 100
    n = max(0, min(127, n))
    return max(1, min(32767, (ftab[n] * CENT_RATIO[cents % 100] + 32768) >> 16))


def select_range(notes, drum_notes, start, end, speed, trim):
    """A dal egy része: start..end (másodperc az eredeti MIDI idejében, a
    --speed előtt; None = eleje / vége).  A belelógó hangok a határon
    kezdődnek / végződnek, a dobok közül a részben kezdődők maradnak.  trim:
    az első hang előtti csend is kimarad.  -> (hangok, dobhangok, a rész
    kezdete a lejátszás idejében, a legkisebb hossz másodpercben vagy None)"""
    lo = (start or 0.0) / speed
    hi = end / speed if end is not None else float("inf")

    def clip(lst, onset_only):
        out = []
        for s, e, n, v, ch, pg in lst:
            if onset_only:
                if lo <= s < hi:
                    out.append((s, min(e, hi), n, v, ch, pg))
            elif s < hi and e > lo:
                out.append((max(s, lo), min(e, hi), n, v, ch, pg))
        return out
    notes, drum_notes = clip(notes, False), clip(drum_notes, True)
    shift = lo
    if trim:
        onsets = [n[0] for n in notes] + [d[0] for d in drum_notes]
        if onsets:
            shift = min(onsets)
    min_len = None
    if end is not None and not trim:
        min_len = hi - lo                 # a kijelölt rész a csenddel együtt
    move = lambda lst: sorted((s - shift, e - shift, n, v, ch, pg) for s, e, n, v, ch, pg in lst)
    return move(notes), move(drum_notes), shift, min_len


# --------------------------------------------------------------------------
# TVC adatok
# --------------------------------------------------------------------------
def pitch_value(freq):
    return 4096.0 - TVC_CLOCK / freq


def note_freq(n, tuning):
    return tuning * 2.0 ** ((n - 69) / 12.0)


def pitch_table(tuning):
    """128 MIDI hangjegy -> 12 bites PITCH.  A túl mély hangok (47,7 Hz
    alatt) egy-egy oktávval feljebb kerülnek."""
    table = []
    for n in range(128):
        f = note_freq(n, tuning)
        while pitch_value(f) < 0:
            f *= 2
        p = int(round(pitch_value(f)))
        table.append(max(0, min(4094, p)))
    return table


# ---- dobkészlet -------------------------------------------------------------
# dobonként tickenkénti lépések: (hang Hz vagy None, hang hangereje,
# zaj hangereje, zaj hossza ~1,2 ms-os egységekben, legfeljebb 8)
DRUM_KIT = [
    ("lábdob",   [(160, 15, 6, 1), (110, 14, 0, 0), (80, 12, 0, 0), (60, 9, 0, 0)]),
    ("pergő",    [(220, 9, 13, 6), (190, 5, 10, 5), (None, 0, 7, 4)]),
    ("zárt cin", [(None, 0, 8, 1)]),
    ("nyitott cin", [(None, 0, 9, 3), (None, 0, 7, 3), (None, 0, 5, 3), (None, 0, 3, 2)]),
    ("crash",    [(None, 0, 12, 7), (None, 0, 10, 6), (None, 0, 8, 5), (None, 0, 6, 4),
                  (None, 0, 4, 3), (None, 0, 3, 2)]),
    ("mély tam", [(190, 14, 4, 1), (140, 12, 0, 0), (110, 10, 0, 0), (95, 7, 0, 0)]),
    ("közép tam", [(260, 14, 4, 1), (200, 12, 0, 0), (160, 10, 0, 0), (140, 7, 0, 0)]),
    ("magas tam", [(350, 14, 4, 1), (270, 12, 0, 0), (220, 10, 0, 0), (190, 7, 0, 0)]),
    ("taps",     [(None, 0, 12, 2), (None, 0, 11, 3), (None, 0, 6, 3)]),
    ("kolomp",   [(800, 12, 5, 1), (800, 7, 0, 0)]),
    ("ride",     [(None, 0, 6, 2), (None, 0, 4, 2), (None, 0, 3, 2)]),
    ("perem",    [(1200, 10, 8, 1)]),
]
KICK, SNARE, HAT, OPENHAT, CRASH, LOTOM, MIDTOM, HITOM, CLAP, COWBELL, RIDE, RIM = range(12)
GM_DRUMS = {35: KICK, 36: KICK, 37: RIM, 38: SNARE, 40: SNARE, 39: CLAP,
            42: HAT, 44: HAT, 46: OPENHAT, 54: OPENHAT,
            49: CRASH, 52: CRASH, 55: CRASH, 57: CRASH, 51: RIDE, 53: RIDE, 59: RIDE,
            41: LOTOM, 43: LOTOM, 45: MIDTOM, 47: MIDTOM, 48: HITOM, 50: HITOM,
            56: COWBELL}
# ha egy tickre több dob esik, ez dönt (előrébb = fontosabb)
DRUM_PRIORITY = [KICK, SNARE, CLAP, CRASH, LOTOM, MIDTOM, HITOM, OPENHAT, RIDE, COWBELL, RIM, HAT]


def drum_level(v, pct):
    """A dob egy hangereje (0..15) a --drum-volume százalékkal, 15-ön telít."""
    return min(15, int(round(v * pct / 100.0)))


def drum_kit_bytes(pct=100):
    """-> dobonként a lépések bájtjai (a címtáblát build_kit teszi elé)."""
    steps = []
    for _, kit in DRUM_KIT:
        b = bytearray()
        for hz, tvol, nvol, nlen in kit:
            if hz is None:
                lo, hi = 0, 0xFF
            else:
                p = max(0, min(4094, int(round(pitch_value(hz)))))
                lo, hi = p & 0xFF, p >> 8
            b += bytes((drum_level(tvol, pct), lo, hi, (drum_level(nvol, pct) << 4) | min(8, nlen)))
        b.append(0xFF)
        steps.append(bytes(b))
    return steps


def build_kit(kit_offset, pct=100):
    steps = drum_kit_bytes(pct)
    head = 1 + 2 * len(steps)
    out = bytearray([len(steps)])
    pos = kit_offset + head
    for st in steps:
        out += struct.pack("<H", pos)
        pos += len(st)
    for st in steps:
        out += st
    return bytes(out)


def drum_hits(notes, rate, curve):
    """Dob hangok -> {tick: (dob, gyengítés)}"""
    hits = {}
    for s, e, n, v, ch, pg in notes:
        if n not in GM_DRUMS and not 27 <= n <= 87:
            continue
        k = GM_DRUMS.get(n, HAT)
        t = int(round(s * rate))
        att = max(0, min(15, int(round((1.0 - max(0.0, min(1.0, v / 127.0)) ** curve) * 8))))
        old = hits.get(t)
        if old is None or DRUM_PRIORITY.index(k) < DRUM_PRIORITY.index(old[0]) or \
                (k == old[0] and att < old[1]):
            hits[t] = (k, att)
    return hits


# ---- többszólamú motor (player_poly.asm) ----------------------------------------
CPU_CLOCK = 3125000.0
POLY_HANDLER_CYCLES = 253     # a player_poly.asm mintamegszakítása a belépéssel együtt
POLY_VOICES = 3
POLY_DIV_MIN, POLY_DIV_MAX = 17, 64
WAVES = ["square", "pulse", "triangle", "saw", "noise", "sine", "pulse12"]
WAVE_NAMES = {"square": "négyszög", "pulse": "impulzus (25%)", "triangle": "háromszög",
              "saw": "fűrész", "noise": "zaj", "sine": "szinusz",
              "pulse12": "keskeny impulzus (12,5%)"}
TONE_WAVES = [w for w in WAVES if w != "noise"]     # dallamhoz választható
NOISE = WAVES.index("noise")
MAX_SLOTS = 5

# poly dobkészlet: (hullámforma, kezdő hangjegy, vég Hz vagy None = nem csúszik,
#                   hangerő, lecsengés tick/lépés, hossz tick)
# zajnál a hangjegy a 256 bájtos zajtábla bejárási sebessége: ha a frekvencia a
# mintavétel felét eléri, a frekvenciatábla levágja, és a zajból éles sípolás
# lesz (a mintavétel felén).  Alacsony hangjegynél (45..64) mintánként új
# zajtábla-bájt jön, a zaj minden mintavételnél (17..28-as osztó) egyenletes.
POLY_KIT = {
    KICK:    ("square", 50, 45, 15, 1, 5),
    LOTOM:   ("square", 55, 90, 13, 1, 6),
    MIDTOM:  ("square", 59, 120, 13, 1, 6),
    HITOM:   ("square", 63, 160, 13, 1, 6),
    COWBELL: ("square", 79, 780, 10, 1, 4),
    SNARE:   ("noise", 60, None, 13, 1, 8),
    CLAP:    ("noise", 62, None, 12, 1, 6),
    HAT:     ("noise", 57, None, 7, 1, 2),
    OPENHAT: ("noise", 57, None, 8, 2, 10),
    CRASH:   ("noise", 45, None, 11, 3, 30),
    RIDE:    ("noise", 52, None, 6, 2, 8),
    RIM:     ("noise", 64, None, 9, 1, 2),
}


def poly_rates(div):
    """-> (mintafrekvencia, minta/tick, tick/s).  A mintaóra a hangszámláló
    (195312,5 / osztó Hz), a tick ebből számolt egész számú minta (~50 Hz)."""
    sr = TVC_CLOCK / div
    tickn = max(1, min(255, int(round(sr / 50.0))))
    return sr, tickn, sr / tickn


def poly_cpu_load(div, fast_irq=False, fast_mix=False):
    """a keverés CPU-része; fast_irq: a kezelő a 0038h-n (az ugrás elmarad);
    fast_mix: keverőtábla nélkül (-11 ciklus)"""
    return (POLY_HANDLER_CYCLES - (10 if fast_irq else 0) - (11 if fast_mix else 0)) / \
        (CPU_CLOCK / (TVC_CLOCK / div))


def poly_freq_table(tuning, sr):
    out = []
    for n in range(128):
        f = note_freq(n, tuning)
        out.append(max(1, min(32767, int(round(f * 65536 / sr)))))
    return out


def poly_peak(vol):
    """a lejátszó hullámtáblájának csúcsa egy hangerőhöz (8 szint: 1, 3, .. 15)"""
    return 2 * ((vol + 1) >> 1) - 1 if vol > 0 else 0


def poly_mix_table(knee, ceiling=15, mode="clean", vmax=9, gain=100):
    """A szólamok összege (0..45) -> 4 bites kimenet.
    fast:  mint a clean, de szólamonként (a lejátszó a szólamtáblákba írja,
           keverőtábla nélkül összead): érték -> 0..5
    clean: a három szólam teljes összege (3 x a szólam legnagyobb csúcsa)
           lineárisan 0..15-re, így nem telít (a dobok csúcsán legfeljebb
           egy pillanatra)
    soft:  a térdig 1:1, fölötte lágy telítés: hangosabb, de erősen
           összenyom (szinusznál, háromszögnél torzításként hallható)
    gain: globális hangerő százalékban (a keverés előtt szoroz)"""
    out = []
    full = 3 * poly_peak(vmax)
    for s in range(64):
        g = s * gain / 100.0
        if mode == "fast":
            v = min(ceiling // 3, g * ceiling / float(full))
        elif mode == "clean":
            v = g * ceiling / float(full)
        elif g <= knee:
            v = g
        else:
            v = knee + (ceiling - knee) * (1 - math.exp(-(g - knee) / 12.0))
        out.append(max(0, min(ceiling, int(round(v)))))
    return out


# ---- hangszer-burkológörbék (a midiplay envelope.txt formátuma) -----------------
# A formátum és a működés Varga István midiplay programjából való (GPL 2 vagy
# későbbi; https://github.com/istvan-v/midiplay, midiconv.cpp és daveplay.cpp):
#   <program>[P][D][:<cs>,<hang>][, <program>...] {
#     [L|R|S] <hossz>, <bal>, <jobb>, <hangmagasság>, <torzítás>;  ...
#   }
# A szakasz <hossz> képkocka (1/50 s) alatt lineárisan éri el a bal/jobb
# hangerőt (0..63; *n = szorzás n/128-cal képkockánként). L = ismétlés eleje,
# R = ismétlés vége (a hang elengedése után innen folytatódik), S = egy
# képkockán kitart. D: az elengedés után a görbe végigfut. A negatív számok a
# dobok, a hangmagasság és a torzítás a TVC-n nincs használva.
ENV_FILES = {"midiplay": "midiplay-2.4.txt", "tvc": "tvc-dav2play.txt"}
ENV_TAIL_MAX = 250                  # az elengedés utáni lecsengés legfeljebb (tick)


class EnvelopeError(ValueError):
    pass


def compile_envelopes(text):
    """envelope.txt -> {program: (képkockák [(bal, jobb)], jelzők)}; a
    képkocka bal bájtjában a felső két bit az L/R/S jel, a végjel (0x80,
    0x00 vagy 0xFF).  A dobok (negatív szám) kimaradnak."""
    buf = []
    comment = False
    for c in text:
        if comment and c not in "\r\n\0":
            continue
        comment = False
        if ord(c) <= 32:
            continue
        if c == "#":
            comment = True
            continue
        buf.append(c)
    buf = "".join(buf) + "\0"
    pos = [0]

    def read_char():
        c = buf[pos[0]]
        if c.isdigit() or c in "+-":
            return "0"
        if c != "\0":
            pos[0] += 1
        return c

    def read_number():
        neg = False
        c = buf[pos[0]]
        if c in "+-":
            neg = c == "-"
            pos[0] += 1
            c = buf[pos[0]]
        if not c.isdigit():
            raise EnvelopeError("hibás szám a burkológörbe-fájlban")
        n = 0
        while buf[pos[0]].isdigit():
            n = n * 10 + int(buf[pos[0]])
            pos[0] += 1
        return -n if neg else n

    def expect(ch):
        if read_char() != ch:
            raise EnvelopeError("szintaktikai hiba a burkológörbe-fájlban")

    def tdiv(a, b):                     # C egész osztás (nulla felé kerekít)
        q = abs(a) // abs(b)
        return q if (a >= 0) == (b > 0) else -q

    out = {}
    while buf[pos[0]] != "\0":
        flags = 0x20                    # 0x20 = nincs kitartás, 0x10 = elengedés
        progs = []
        while True:
            n = read_number()
            if not -127 <= n <= 127:
                raise EnvelopeError("hibás programszám a burkológörbe-fájlban")
            progs.append(n)
            c = read_char()
            while c.lower() in ("p", "d"):
                if c.lower() == "d":
                    flags = 0x30
                c = read_char()
            if c == ":":                # második réteg: csatorna, hang (nincs használva)
                expect("0")
                read_number()
                expect(",")
                expect("0")
                read_number()
                c = read_char()
            if c == "{":
                break
            if c != ",":
                raise EnvelopeError("szintaktikai hiba a burkológörbe-fájlban")
        vl, vl_inc, vl_mult = 0x80, 0, 0
        vr, vr_inc, vr_mult = 0x80, 0, 0
        pb, pb_inc = 0x80, 0
        d = 0
        frames = []
        while True:
            if d:
                frames.append(((vl >> 8) & 0xFF, (vr >> 8) & 0xFF, pb >> 8))
                pb += pb_inc
                d -= 1
                vl &= 0x3FFF
                vl = (vl * vl_mult + 64) >> 7 if vl_mult else vl + vl_inc
                vl = 0 if vl < 0 else min(vl, 0x3FFF)
                vr &= 0x3FFF
                vr = (vr * vr_mult + 64) >> 7 if vr_mult else vr + vr_inc
                vr = 0 if vr < 0 else min(vr, 0x3FFF)
                continue
            c = read_char()
            if c == "}":
                break
            expect("0")
            n = read_number()
            if not 0 <= n <= 255:
                raise EnvelopeError("hibás szakaszhossz a burkológörbe-fájlban")
            d = n
            if c != "0" and n:
                m = c.lower()
                if m == "l":
                    if flags != 0x20:
                        raise EnvelopeError("hibás ismétlés a burkológörbe-fájlban")
                    vl |= 0x4000
                    flags = 0x00
                elif m == "r":
                    if flags == 0x10:
                        raise EnvelopeError("hibás ismétlés a burkológörbe-fájlban")
                    vl |= 0xC000 if flags else 0x8000
                    flags = 0x10
                elif m == "s":
                    if flags != 0x20:
                        raise EnvelopeError("hibás ismétlés a burkológörbe-fájlban")
                    vl |= 0xC000
                else:
                    raise EnvelopeError("szintaktikai hiba a burkológörbe-fájlban")
                c = "0"
            if c != "0" or read_char() != ",":
                raise EnvelopeError("szintaktikai hiba a burkológörbe-fájlban")
            for side in (0, 1):         # bal, jobb hangerő
                c = read_char()
                mult = c == "*"
                if mult:
                    c = read_char()
                if c != "0":
                    raise EnvelopeError("szintaktikai hiba a burkológörbe-fájlban")
                v = read_number()
                if not ((1 <= v < 256) if mult else (0 <= v < 64)):
                    raise EnvelopeError("hibás hangerő a burkológörbe-fájlban")
                if side == 0:
                    if mult:
                        vl_mult = v
                    else:
                        vl_mult = 0
                        if not d:
                            vl = (vl & 0xC000) | (v << 8) | 0x80
                        else:
                            x = ((v << 8) | 0x80) - (vl & 0x3FFF)
                            x += -(d >> 1) if x < 0 else d >> 1
                            vl_inc = tdiv(x, d)
                else:
                    if mult:
                        vr_mult = v
                    else:
                        vr_mult = 0
                        if not d:
                            vr = (v << 8) | 0x80
                        else:
                            x = ((v << 8) | 0x80) - (vr & 0x3FFF)
                            x += -(d >> 1) if x < 0 else d >> 1
                            vr_inc = tdiv(x, d)
                if read_char() != ",":
                    raise EnvelopeError("szintaktikai hiba a burkológörbe-fájlban")
            expect("0")                 # hangmagasság (768 = egy oktáv)
            n = read_number()
            if not -2048 <= n <= 2047:
                raise EnvelopeError("hibás hangmagasság a burkológörbe-fájlban")
            pv = (n << 8) | 0x80
            pb_inc = 0
            if not d:
                pb = pv
            elif pv != pb:
                x = pv - pb
                x += -(d >> 1) if x < 0 else d >> 1
                pb_inc = tdiv(x, d)
            expect(",")
            expect("0")                 # torzítás
            read_number()
            expect(";")
        frames.append((0x80, 0x00 if not flags else 0xFF, 0))
        for n in progs:
            if n >= 0:
                out[n] = (frames, flags)
    return out


def load_envelopes(name):
    """'midiplay', 'tvc' (a mellékelt fájlok) vagy egy fájl útvonala"""
    path = name
    if name in ENV_FILES:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "envelopes", ENV_FILES[name])
    with open(path, "rb") as f:
        return compile_envelopes(f.read().decode("utf-8", "replace"))


def envelope_levels(env, held):
    """A hang burkológörbéje képkockánként (0..63)"""
    return [lv for lv, _ in envelope_frames(env, held)]


def envelope_frames(env, held):
    """A hang burkológörbéje képkockánként: (hangerő 0..63, hangmagasság a
    fájl egységében, 768 = egy oktáv), a midiplay lejátszója szerint: held
    képkocka után engedik el.  A lista vége a hang vége."""
    frames, flags = env
    state = flags & 0xB0
    releasing = False
    ptr, loop = 0, None
    out = []
    t = 0
    while len(out) < held + ENV_TAIL_MAX:
        if t == held and not releasing:
            if not state & 0x10:
                break
            releasing = True
            if frames[ptr][0] >= 0xC0:
                ptr += 1
        if ptr >= len(frames):
            break
        b0, b1, pt = frames[ptr]
        if b0 & 0xC0:
            if b1 == 0xFF:
                break
            if not releasing:
                m = b0 & 0xC0
                if m == 0x40:
                    loop = ptr
                    ptr += 1
                elif m == 0x80:
                    if loop is None:
                        break
                    b0, b1, pt = frames[loop]
                    ptr = loop + 1
                else:
                    state = 0x10
            else:
                ptr += 1
            b0 &= 0x3F
        else:
            ptr += 1
        out.append((max(b0, b1), pt))
        t += 1
    return out


def parse_channel_waves(spec):
    """'1=saw,6=triangle' -> {0: 'saw', 5: 'triangle'}"""
    out = {}
    if not spec:
        return out
    for item in spec.split(","):
        ch, _, w = item.partition("=")
        if w not in TONE_WAVES:
            raise ValueError("ismeretlen hullámforma: %r (lehet: %s)" % (w, ", ".join(TONE_WAVES)))
        out[int(ch) - 1] = w
    return out


def poly_envelope_ticks(ticks, args, vmin, vmax):
    """Hangszer-burkológörbékkel: hangonként a hangerő tickenként (None =
    állandó), és a hang új vége (az elengedés utáni lecsengéssel együtt)."""
    env = getattr(args, "envelope_data", None)
    if not env:
        return ticks, {}
    seqs, out = {}, []
    floor = max(0, min(15, args.decay_floor))
    for st, en, n, v, ch, idx, pg in ticks:
        base = velocity_to_volume(v, args.curve, vmin, vmax)
        pit = None
        if pg in env:
            fr = envelope_frames(env[pg], en - st)
            seq = [(x * base * 2 + 63) // 126 for x, _ in fr]
            if any(p for _, p in fr):
                pit = [int(round(p * 25 / 16.0)) for _, p in fr]     # cent
        elif args.decay:            # a lejátszó lecsengése, itt kiszámolva
            seq = [max(min(base, floor), base - k // args.decay) for k in range(en - st)]
        else:
            seq = [base] * (en - st)
        while seq and not seq[-1]:
            seq.pop()
        if not seq:
            continue
        seqs[idx] = (seq, en, pit)
        out.append((st, st + len(seq), n, v, ch, idx, pg))
    return out, seqs


def convert_poly(notes, drums, args, sr, tick_rate, ftab, ch_waves):
    ticks = build_ticks(notes, tick_rate)
    vmax = args.poly_volume
    vmin = max(1, min(vmax, int(round(args.min_volume * vmax / 15.0))))
    ticks, seqs = poly_envelope_ticks(ticks, args, vmin, vmax)
    total = max([t[1] for t in ticks] + [t + max(8, POLY_KIT[k][5] if k in POLY_KIT else 8) for t, (k, _) in drums.items()] + [1] +
                ([int(round(args.min_len * tick_rate))] if args.min_len else []))
    starts = {}
    for t in ticks:
        starts.setdefault(t[0], []).append(t)
    out = bytearray()
    pending = [0]
    stats = {"notes": 0, "drums": len(drums), "voices_max": 0, "peak_sum": 0}
    lvl = [0] * POLY_VOICES           # a szólamok hangereje a megszólaláskor (felső becslés)
    slots = []                        # hullámforma-helyek a megjelenés sorrendjében

    def slot_of(wave):
        w = WAVES.index(wave)
        if w not in slots:
            if len(slots) >= MAX_SLOTS:
                raise ValueError("legfeljebb %d féle hullámforma használható egyszerre" % MAX_SLOTS)
            slots.append(w)
        return slots.index(w)

    def emit(b):
        encode_wait_poly(out, pending[0])
        pending[0] = 0
        out.extend(b)

    active = {}
    cur = [None] * POLY_VOICES        # (idx, note)
    reserved = [0] * POLY_VOICES      # dob foglalja eddig a tickig
    vslot = [0] * POLY_VOICES         # a szólam hullámforma-helye a lejátszóban
    vfreq = [None] * POLY_VOICES      # a szólam fázisnövekménye a lejátszóban
    bend_on = bool(getattr(args, "bend", False))
    bends, mods = getattr(args, "bend_ctl", None) or ({}, {})
    slot_of(args.wave)                # az alap hullámforma a 0. hely

    def set_wave(v, wave):
        sl = slot_of(wave)
        if vslot[v] != sl:
            emit(bytes((0xBB + v, sl)))
            vslot[v] = sl

    for t in range(total + 1):
        for k in [k for k, a in active.items() if a[1] <= t]:
            del active[k]
        for st, en, n, v, ch, idx, pg in starts.get(t, ()):
            active[idx] = (st, en, n, v, ch)
        # lejárt dobfoglalások: a szólam elhallgat
        for v in range(POLY_VOICES):
            if reserved[v] and reserved[v] <= t:
                reserved[v] = 0
                emit(bytes((0xB0 + v,)))
                cur[v] = None
                lvl[v] = 0
        # a hangok sorrendje: legmagasabb, legmélyebb, majd a többi lefelé
        # (burkológörbével az elengedett, még lecsengő hangok csak a szabad
        # szólamokra jutnak, a lenyomva tartottak után)
        uniq, tails = {}, []
        for idx, (st, en, n, v, ch) in active.items():
            if idx in seqs and t >= seqs[idx][1]:
                tails.append((st, idx, n))
            elif n not in uniq or st > uniq[n][0]:
                uniq[n] = (st, idx, v)
        ordered = sorted(uniq, reverse=True)
        prio = ordered[:1] + ordered[-1:] + ordered[1:-1] if len(ordered) > 1 else ordered
        cands = [(uniq[n][1], n) for n in prio]
        for st, idx, n in sorted(tails, reverse=True):
            if n not in uniq:
                cands.append((idx, n))
        # dob ezen a ticken: szabad szólam, különben a középső (nem dallam, nem basszus)
        if t in drums:
            k, att = drums[t]
            kit = POLY_KIT.get(k)
            if kit:
                wave, note, end_hz, vol, dec, dur = kit
                keep = set(prio[:2])
                cand = [v for v in range(POLY_VOICES) if not reserved[v] and cur[v] is None]
                cand += [v for v in range(POLY_VOICES) if not reserved[v] and cur[v] is not None
                         and cur[v][1] not in keep]
                cand += [v for v in range(POLY_VOICES) if reserved[v]]     # egy futó dob helyére
                if prio:
                    cand += [v for v in range(POLY_VOICES) if not reserved[v]
                             and cur[v] is not None and cur[v][1] == prio[-1]]
                if cand:
                    v = cand[0]
                    slide = 0
                    if end_hz is not None:
                        f1 = int(round(end_hz * 65536 / sr))
                        slide = int(round((f1 - ftab[note]) / float(dur))) & 0xFFFF
                    vol = max(1, drum_level(vol, args.drum_volume) - att)
                    set_wave(v, wave)
                    emit(bytes((0xB8 + v, note, (vol << 4) | dec, slide & 0xFF, slide >> 8)))
                    stats["slides"] = stats.get("slides", 0) + 1
                    lvl[v] = vol
                    reserved[v] = t + dur
                    cur[v] = None
        free = [v for v in range(POLY_VOICES) if not reserved[v]]
        want = cands[:len(free)]
        want_idx = dict(want)
        stats["voices_max"] = max(stats["voices_max"], len(want))
        # a megmaradó hangok a helyükön maradnak
        new_cur = {}
        for v in free:
            if cur[v] is not None and cur[v][0] in want_idx:
                new_cur[v] = cur[v]
        placed = {c[0] for c in new_cur.values()}
        fresh = set()
        empty = [v for v in free if v not in new_cur]
        for idx, n in want_idx.items():
            if idx in placed:
                continue
            v = empty.pop(0)
            vel, ch = active[idx][3], active[idx][4]
            if idx in seqs:
                vol = seqs[idx][0][t - active[idx][0]]
            else:
                vol = velocity_to_volume(vel, args.curve, vmin, vmax)
            set_wave(v, ch_waves.get(ch, args.wave))
            emit(bytes((0x80 + 16 * v + vol, n)))
            lvl[v] = vol
            vfreq[v] = ftab[n]
            stats["notes"] += 1
            new_cur[v] = (idx, n)
            placed.add(idx)
            fresh.add(v)
        for v in free:
            if v not in new_cur and cur[v] is not None:
                emit(bytes((0xB0 + v,)))
                lvl[v] = 0
            cur[v] = new_cur.get(v)
            # burkológörbe: ha a hangerő változik, a hang újra (a fázis marad)
            if cur[v] is not None and v not in fresh and cur[v][0] in seqs:
                idx, n = cur[v]
                lev = seqs[idx][0][t - active[idx][0]]
                if lev != lvl[v]:
                    emit(bytes((0x80 + 16 * v + lev, n)))
                    lvl[v] = lev
                    vfreq[v] = ftab[n]
            # hajlítás, vibrato, a burkológörbe hangmagassága: B3+s lo hi
            if bend_on and cur[v] is not None:
                idx, n = cur[v]
                st, ch = active[idx][0], active[idx][4]
                c = control_at(bends, ch, t)
                m = control_at(mods, ch, t)
                if m:
                    k = int(t * VIB_HZ * 16 / tick_rate) % 16
                    c += int(round(m * VIB_DEPTH * VIB_SIN[k] / (127 * 1000.0)))
                sq = seqs.get(idx)
                if sq and sq[2] and t - st < len(sq[2]):
                    c += sq[2][t - st]
                f = bent_freq(ftab, n, c)
                if f != vfreq[v]:
                    emit(bytes((0xB3 + v, f & 0xFF, f >> 8)))
                    vfreq[v] = f
                    stats["bends"] = stats.get("bends", 0) + 1
        stats["peak_sum"] = max(stats["peak_sum"], sum(poly_peak(x) for x in lvl))
        pending[0] += 1
    encode_wait_poly(out, pending[0])
    out += bytes([0xB0, 0xB1, 0xB2])
    if args.loop:
        # ismétlés előtt a szólamok a kezdő hullámformára, mert a lejátszó a
        # dal elejére ugrik, és ott a konverter a 0. helyet feltételezi
        for v in range(POLY_VOICES):
            if vslot[v] != 0:
                out += bytes((0xBB + v, 0))
        if args.loop_pause:
            n = int(round(args.loop_pause * tick_rate))
            encode_wait_poly(out, n)      # beállított szünet az ismétlés előtt
            total += n
    out.append(0xFF)
    return bytes(out), total, stats, slots


def encode_wait_poly(out, n):
    while n > 0:
        if n <= 63:
            out.append(0xBF + n)
            return
        k = min(n, 65535)
        out += bytes((0xBF, k & 0xFF, k >> 8))
        n -= k


def velocity_to_volume(vel, curve, vmin, vmax):
    """MIDI erősség (0..127, a CC7/CC11 már benne) -> 1..15."""
    x = max(0.0, min(1.0, vel / 127.0)) ** curve
    return max(vmin, min(vmax, int(round(vmin + x * (vmax - vmin)))))


def gain_volume(vol, gain):
    """az egyszólamú lejátszó hangereje (1..15) a globális hangerővel; 15-ön
    megáll (a négyszögjel ott sem torzul, csak a dinamika szűkül)"""
    return max(1, min(15, int(round(vol * gain / 100.0))))


def max_gain(full, peak):
    """a torzítás nélküli legnagyobb globális hangerő százalékban"""
    return int(100 * full // peak) if peak else 100


def build_ticks(notes, rate):
    """Hangok -> (start_tick, end_tick, note, vel, ch, idx, program); minden
    hang legalább 1 tick hosszú."""
    out = []
    for i, (s, e, n, v, ch, pg) in enumerate(notes):
        st = int(round(s * rate))
        en = max(st + 1, int(round(e * rate)))
        out.append((st, en, n, v, ch, i, pg))
    return out


def choose(active, mode, prio, max_notes, keep_bass=False):
    """Az aktív hangokból a megszólalók kiválasztása.
    active: [(note, vel, start_tick, idx)] -> [(note, vel, idx)]"""
    if not active:
        return []
    if mode == "mono":
        if prio == "high":
            best = max(active, key=lambda a: (a[0], a[2]))
        elif prio == "low":
            best = min(active, key=lambda a: (a[0], -a[2]))
        else:                                   # last
            best = max(active, key=lambda a: (a[2], a[0]))
        return [(best[0], best[1], best[3])]
    # arp: a legmagasabb hangok, hangmagasság szerint növekvő sorrendben
    uniq = {}
    for n, v, st, idx in active:
        if n not in uniq or st > uniq[n][2]:
            uniq[n] = (n, v, st, idx)
    ordered = sorted(uniq.values(), key=lambda a: -a[0])
    pick = ordered[:max_notes]
    if keep_bass and len(ordered) > max_notes:
        # a legmélyebb hang (basszus) mindig szóljon, mellé a legmagasabbak
        pick = ordered[:max_notes - 1] + [ordered[-1]]
    pick.sort(key=lambda a: a[0])
    return [(n, v, idx) for n, v, st, idx in pick]


def encode_wait(out, n):
    while n > 0:
        if n <= 63:
            out.append(0xBF + n)
            return
        k = min(n, 65535)
        out += bytes((0xA0, k & 0xFF, k >> 8))
        n -= k


def convert(notes, args, drums=None):
    ticks = build_ticks(notes, args.rate)
    drums = drums or {}
    total = max([t[1] for t in ticks] + [t + 6 for t in drums] +
                ([int(round(args.min_len * args.rate))] if args.min_len else []))
    starts = {}
    for t in ticks:
        starts.setdefault(t[0], []).append(t)
    active = {}
    out = bytearray()
    prev = None          # (notes tuple, idx set) az előző tickben
    cur_vol = None
    pending_wait = 0
    stats = {"chords": 0, "notes": 0, "rests": 0, "drums": len(drums), "max_vol": 0}
    for t in range(total + 1):
        for k in [k for k, a in active.items() if a[1] <= t]:
            del active[k]
        for st, en, n, v, ch, idx, pg in starts.get(t, ()):
            active[idx] = (st, en, n, v)
        sel = choose([(a[2], a[3], a[0], i) for i, a in active.items()],
                     args.mode, args.prio, args.max_notes, args.arp_bass)
        key = (tuple(s[0] for s in sel), frozenset(s[2] for s in sel))
        if key != prev:
            new_attack = prev is None or any(s[2] not in prev[1] for s in sel)
            if tuple(s[0] for s in sel) != (prev[0] if prev else None) or new_attack:
                encode_wait(out, pending_wait)
                pending_wait = 0
                if not sel:
                    out.append(0x80)
                    stats["rests"] += 1
                else:
                    vol = velocity_to_volume(max(s[1] for s in sel), args.curve,
                                             args.min_volume, args.max_volume)
                    stats["max_vol"] = max(stats["max_vol"], vol)
                    vol = gain_volume(vol, args.gain)
                    if vol != cur_vol:
                        out.append(0x90 | vol)
                        cur_vol = vol
                    if len(sel) == 1:
                        out.append(sel[0][0])
                        stats["notes"] += 1
                    else:
                        out.append(0x80 | len(sel))
                        out += bytes(s[0] for s in sel)
                        stats["chords"] += 1
            prev = key
        if t in drums:
            encode_wait(out, pending_wait)
            pending_wait = 0
            k, att = drums[t]
            out += bytes((0xA1 + k, att))
        pending_wait += 1
    encode_wait(out, pending_wait)
    out.append(0x80)
    if args.loop and args.loop_pause:
        n = int(round(args.loop_pause * args.rate))
        encode_wait(out, n)               # beállított szünet az ismétlés előtt
        total += n
    out.append(0xFF)
    return bytes(out), total, stats


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("midi", help="bemeneti .mid fájl")
    ap.add_argument("-o", "--output", default="build/song.bin", help="kimeneti adatfájl")
    ap.add_argument("--title-out", help="a BASIC PRINT sor 32 karakteres címe ide kerül")
    ap.add_argument("--title", help="cím (alapból a fájlnév)")
    ap.add_argument("--mode", choices=("mono", "arp", "poly"), default="arp",
                    help="poly: többszólamú motor (a build.sh a player_poly.asm-et fordítja)")
    ap.add_argument("--poly-volume", type=int, default=9,
                    help="poly: egy szólam legnagyobb hangereje (alap: 9)")
    ap.add_argument("--poly-mix", choices=("clean", "soft", "fast"), default="clean",
                    help="poly: keverés; clean = a három szólam összege arányosan 0..15-re, "
                         "nem telít (alap); soft = hangosabb, a térd fölött lágyan telít; "
                         "fast = mint a clean, de keverőtábla nélkül (-11 ciklus mintánként, "
                         "szólamonként 6 szint)")
    ap.add_argument("--poly-knee", type=int, default=10,
                    help="poly, --poly-mix soft: a keverőtábla eddig lineáris (alap: 10)")
    ap.add_argument("--poly-div", type=int, default=19,
                    help="poly: a mintaóra osztója, mintafrekvencia = 195312,5 / osztó "
                         "(alap: 19 = 10 280 Hz; 23 = 8 492 Hz, több szabad CPU)")
    ap.add_argument("--wave", choices=TONE_WAVES, default="square",
                    help="poly: hullámforma (square, pulse = 25%%-os impulzus, triangle, saw, sine, pulse12 = 12,5%%-os)")
    ap.add_argument("--channel-wave", metavar="CS=HULLÁM,...",
                    help="poly: csatornánkénti hullámforma, pl. 1=saw,6=sine")
    ap.add_argument("--prio", choices=("high", "low", "last"), default="high",
                    help="mono módban melyik hang szóljon (alap: a legmagasabb)")
    ap.add_argument("--max-notes", type=int, default=3, choices=(2, 3, 4),
                    help="arp módban legfeljebb ennyi hang (alap: 3)")
    ap.add_argument("--arp-bass", action="store_true",
                    help="arp módban a legmélyebb hang (basszus) mindig benne van")
    ap.add_argument("--arp-speed", type=int, default=1,
                    help="arpeggio: ennyi tickenként lép (alap: 1 = ~50 Hz)")
    ap.add_argument("--channels", help="csak ezek a MIDI csatornák (1..16, vesszővel)")
    ap.add_argument("--drums", choices=("synth", "pitched", "off"), default="synth",
                    help="a 10. csatorna: synth = szintetizált dobok (alap), "
                         "pitched = dallamhangként, off = kimarad")
    ap.add_argument("--transpose", type=int, default=0, help="félhangokban")
    ap.add_argument("--tuning", type=float, default=440.0, help="az A4 frekvenciája")
    ap.add_argument("--speed", type=float, default=1.0, help="tempószorzó")
    ap.add_argument("--rate", type=float, default=FRAME_RATE, help="tick/s (alap: %(default)s)")
    ap.add_argument("--decay", type=int, default=0,
                    help="lecsengés: ennyi tickenként csökken a hangerő eggyel (0 = nincs)")
    ap.add_argument("--decay-floor", type=int, default=6, help="a lecsengés alsó határa")
    ap.add_argument("--curve", type=float, default=0.7, help="erősség -> hangerő görbe kitevője")
    ap.add_argument("--min-volume", type=int, default=6)
    ap.add_argument("--max-volume", type=int, default=15)
    ap.add_argument("--loop", action="store_true", help="a dal végtelenítve szól")
    ap.add_argument("--bend", action="store_true",
                    help="többszólamú mód: hangmagasság-hajlítás (pitch bend, RPN-tartomány), vibrato "
                         "a modulációs kerékről és a burkológörbék hangmagassága")
    ap.add_argument("--cards", default="", metavar="LISTA",
                    help="többszólamú mód: hangkártya-meghajtók vesszővel (sn = SN76489: GameCard, "
                         "Multichip; sid = a TVC256k++ vSID-je; saa = SAA1099, opl = YM3812 (OPL2): "
                         "Multichip); ha a program indításkor talál "
                         "ilyen kártyát, azon szól")
    ap.add_argument("--fast-irq", action="store_true",
                    help="többszólamú mód: a mintakezelő a 0038h-ra kerül (-10 ciklus mintánként; "
                         "a 0038h..0088h területet a lejátszás alatt használja, a végén visszaállítja)")
    ap.add_argument("--envelopes", metavar="NÉV|FÁJL",
                    help="többszólamú mód: hangszer-burkológörbék a midiplay formátumában "
                         "('midiplay' vagy 'tvc' = a mellékelt fájlok, vagy egy envelope.txt)")
    ap.add_argument("--gain", default="100", metavar="SZÁZALÉK",
                    help="globális hangerő százalékban (alap: 100); 'max' = a legnagyobb, "
                         "ami még nem torzít")
    ap.add_argument("--drum-volume", type=float, default=100, metavar="SZÁZALÉK",
                    help="a szintetizált dob hangereje százalékban (alap: 100, a 15-ös szint felett telít)")
    ap.add_argument("--loop-pause", type=float, default=0, metavar="MP",
                    help="ismétlésnél ennyi másodperc szünet a dal vége után "
                         "(alap: 0 = az ismétlés szünet nélkül folytatódik)")
    ap.add_argument("--from", dest="start", type=float, default=None, metavar="MP",
                    help="csak a dal ettől a ponttól (másodperc az eredeti MIDI idejében)")
    ap.add_argument("--to", dest="end", type=float, default=None, metavar="MP",
                    help="csak a dal eddig a pontig (másodperc az eredeti MIDI idejében)")
    ap.add_argument("--trim", action="store_true",
                    help="az első hang előtti csend kimarad (és a --to előtti csend is)")
    ap.add_argument("--background", action="store_true",
                    help="egycsatornás lejátszó: háttérben szól, a BASIC közben fut "
                         "(EXT 0 leállítja, EXT 1 újraindítja)")
    ap.add_argument("--max-size", type=int, default=20000,
                    help="figyelmeztet, ha az adat ennél nagyobb (a 32k-s TVC miatt)")
    args = ap.parse_args()
    gain_auto = args.gain == "max"
    try:
        args.gain = 100.0 if gain_auto else float(args.gain)
    except ValueError:
        ap.error("--gain: százalék vagy 'max'")
    if not 1 <= args.gain <= 1000:
        ap.error("--gain: 1..1000")

    if args.channels:
        channels = {int(c) - 1 for c in args.channels.split(",")}
    else:
        channels = set(range(16))
    use_drums = args.drums == "synth" and DRUM_CHANNEL in channels
    if args.drums != "pitched":
        channels.discard(DRUM_CHANNEL)
    if not 1 <= args.arp_speed <= 255:
        ap.error("--arp-speed: 1..255")
    if not 0 <= args.decay <= 255:
        ap.error("--decay: 0..255")
    if not 1 <= args.min_volume <= args.max_volume <= 15:
        ap.error("1 <= --min-volume <= --max-volume <= 15")
    args.envelope_data = None
    args.cards = [c for c in args.cards.split(",") if c]
    for c in args.cards:
        if c not in CARDS:
            ap.error("--cards: ismeretlen kártya: %s (lehet: %s)" % (c, ", ".join(CARDS)))
    if args.envelopes:
        try:
            args.envelope_data = load_envelopes(args.envelopes)
        except (OSError, EnvelopeError) as e:
            ap.error("--envelopes: %s" % e)
        if args.mode != "poly":
            print("figyelem: a burkológörbék csak a többszólamú lejátszóval működnek")

    with open(args.midi, "rb") as f:
        division, events = parse_midi(f.read())
    notes = collect_notes(division, events, channels, args.transpose, args.speed)
    drum_notes = collect_notes(division, events, {DRUM_CHANNEL}, 0, args.speed) if use_drums else []
    if args.start is not None and args.end is not None and args.end <= args.start:
        ap.error("--to legyen nagyobb, mint --from")
    notes, drum_notes, shift, args.min_len = select_range(notes, drum_notes, args.start, args.end,
                                                          args.speed, args.trim)
    if args.bend:
        args.bend_raw = collect_controls(division, events, channels, args.speed)
        args.bend_shift = shift
    drums = drum_hits(drum_notes, args.rate, args.curve) if use_drums else {}
    if not notes and not drums:
        sys.exit("a kiválasztott csatornákon (és részben) nincs hang")
    if args.mode == "poly":
        if args.background:
            print("figyelem: a háttér-mód csak az egycsatornás lejátszóval működik (a poly a teljes CPU-t használja)")
        write_poly(args, notes, drums, gain_auto)
        return
    body, total, stats = convert(notes, args, drums)
    top = max_gain(15, stats["max_vol"])
    if gain_auto:
        args.gain = top
        body, total, stats = convert(notes, args, drums)
    print("hangerő: %g%% (torzítás nélkül legfeljebb %d%%)" % (args.gain, top))

    flags = (1 if args.loop else 0) | (2 if args.background else 0)
    table = pitch_table(args.tuning)
    kit_offset = 8 + 256 + len(body) if drums else 0
    header = struct.pack("<BBBBHH", flags, args.arp_speed, args.decay,
                         max(0, min(15, args.decay_floor)), 0, kit_offset)
    data = header + b"".join(struct.pack("<H", p) for p in table) + body
    if drums:
        data += build_kit(kit_offset, args.drum_volume * args.gain / 100.0)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(data)
    write_title(args)
    write_features(args, MONO_FEATURES, {n for n, on in (("FEAT_DRUMS", bool(drums)),
                                                         ("FEAT_BG", args.background)) if on})

    report(args, notes, total, args.rate, stats, len(data))


# a TVC karakterkészlete: Á É Í Ó Ö Ő Ú Ü Ű = 80h..88h, á .. ű = 90h..98h
TVC_ACCENTS = {c: 0x80 + i for i, c in enumerate("ÁÉÍÓÖŐÚÜŰ")}
TVC_ACCENTS.update({c: 0x90 + i for i, c in enumerate("áéíóöőúüű")})
TVC_ACCENTS.update({"Õ": 0x85, "Û": 0x88, "õ": 0x95, "û": 0x98})    # gyakori elírások
TVC_ACCENTS.update({c: ord("-") for c in "–—‐‑"})                    # gondolatjelek
TVC_ACCENTS.update({c: ord("'") for c in "‘’‚“”„«»"})                 # idézőjelek


def tvc_title(title):
    """A cím 32 bájton a BASIC PRINT sorához: ASCII, a magyar ékezetes
    betűk TVC-kóddal, más ékezetes betű ékezet nélkül, a többi '_'."""
    import unicodedata
    out = bytearray()
    for c in title:
        if c in TVC_ACCENTS:
            out.append(TVC_ACCENTS[c])
            continue
        if not (32 <= ord(c) < 127):
            c = unicodedata.normalize("NFKD", c)[0]
        out.append(ord(c) if 32 <= ord(c) < 127 and c != '"' else 0x5F)
        if len(out) >= 32:
            break
    return bytes(out[:32]).ljust(32, b" ")


def ascii_name(name):
    """ékezet nélküli fájlnév: Árvíztűrő -> Arvizturo"""
    import unicodedata
    t = unicodedata.normalize("NFKD", name)
    return "".join(c for c in t if c.isascii() and (c.isalnum() or c in "-_"))


# A lejátszók kapcsolható részei (build/features.inc, a lejátszó IF blokkjai):
# a .cas-ba csak a dalhoz kellő kód kerül.  A sorrend és a szöveg a webes
# konverterével (midi2tvc.js featuresInc) azonos.
POLY_FEATURES = ["FEAT_DRUMS", "FEAT_WAVE_PULSE", "FEAT_WAVE_TRI", "FEAT_WAVE_SAW",
                 "FEAT_WAVE_NOISE", "FEAT_WAVE_SINE", "FEAT_IRQ0038", "FEAT_PITCH",
                 "FEAT_CARDS", "FEAT_SN", "FEAT_SID", "FEAT_SAA", "FEAT_OPL", "FEAT_FASTMIX", "FEAT_WAVE_PULSE12",
                 "FEAT_DECAY", "FEAT_WAVECHG", "FEAT_LOOP"]
CARDS = ["sn", "sid", "saa", "opl"]                      # --cards: a lejátszóba kerülő kártyameghajtók
MONO_FEATURES = ["FEAT_DRUMS", "FEAT_BG"]


def features_inc(names, on):
    return "".join("%s equ %d\n" % (n, 1 if n in on else 0) for n in names)


def write_features(args, names, on):
    path = os.path.join(os.path.dirname(os.path.abspath(args.output)), "features.inc")
    with open(path, "w") as f:
        f.write(features_inc(names, on))
    print("a lejátszóba kerül: %s" % (", ".join(n[5:].lower() for n in names if n in on) or "csak az alap"))


def write_title(args):
    if args.title_out:
        title = args.title if args.title is not None else \
            os.path.splitext(os.path.basename(args.midi))[0]
        with open(args.title_out, "wb") as f:
            f.write(tvc_title(title))


def write_poly(args, notes, drums_sec, gain_auto=False):
    if not POLY_DIV_MIN <= args.poly_div <= POLY_DIV_MAX:
        sys.exit("--poly-div: %d..%d" % (POLY_DIV_MIN, POLY_DIV_MAX))
    sr, tickn, tick_rate = poly_rates(args.poly_div)
    # a dobütések a poly tick-rácsra
    drums = {}
    for (t, hit) in drums_sec.items():
        tt = int(round(t / args.rate * tick_rate))
        old = drums.get(tt)
        if old is None or DRUM_PRIORITY.index(hit[0]) < DRUM_PRIORITY.index(old[0]):
            drums[tt] = hit
    ftab = poly_freq_table(args.tuning, sr)
    if args.bend:
        args.bend_ctl = (control_ticks(args.bend_raw[0], args.bend_shift, tick_rate),
                         control_ticks(args.bend_raw[1], args.bend_shift, tick_rate))
    try:
        ch_waves = parse_channel_waves(args.channel_wave)
        body, total, stats, slots = convert_poly(notes, drums, args, sr, tick_rate, ftab, ch_waves)
    except ValueError as e:
        sys.exit(str(e))
    top = max_gain(3 * poly_peak(args.poly_volume), stats["peak_sum"])
    if args.poly_mix == "fast":
        top = 100                           # szólamonként telítene
    if gain_auto:
        args.gain = top
    print("hangerő: %g%% (torzítás nélkül legfeljebb %d%%)" % (args.gain, top))
    header = struct.pack("<BBBBHBB", (1 if args.loop else 0) | (2 if args.poly_mix == "fast" else 0), 0 if args.envelope_data else args.decay,
                         max(0, min(15, args.decay_floor)), args.poly_div, 0, tickn, len(slots))
    header += bytes(slots + [0] * (MAX_SLOTS - len(slots))) + bytes((args.poly_volume, 0, 0))
    data = header + bytes(poly_mix_table(args.poly_knee, mode=args.poly_mix, vmax=args.poly_volume,
                                         gain=args.gain)) + \
        b"".join(struct.pack("<H", f) for f in ftab) + body
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(data)
    write_title(args)
    used = {WAVES[w] for w in slots}
    write_features(args, POLY_FEATURES, {n for n, on in (
        ("FEAT_DRUMS", stats.get("slides", 0) > 0), ("FEAT_WAVE_PULSE", "pulse" in used),
        ("FEAT_WAVE_TRI", "triangle" in used), ("FEAT_WAVE_SAW", "saw" in used),
        ("FEAT_WAVE_NOISE", "noise" in used), ("FEAT_WAVE_SINE", "sine" in used),
        ("FEAT_IRQ0038", args.fast_irq), ("FEAT_PITCH", stats.get("bends", 0) > 0),
        ("FEAT_CARDS", bool(args.cards)), ("FEAT_SN", "sn" in args.cards),
        ("FEAT_SID", "sid" in args.cards), ("FEAT_SAA", "saa" in args.cards),
        ("FEAT_OPL", "opl" in args.cards), ("FEAT_FASTMIX", args.poly_mix == "fast"),
        ("FEAT_WAVE_PULSE12", "pulse12" in used),
        ("FEAT_DECAY", (0 if args.envelope_data else args.decay) > 0 or stats.get("slides", 0) > 0),
        ("FEAT_WAVECHG", len(slots) > 1), ("FEAT_LOOP", args.loop)) if on})
    print("poly: %.0f Hz mintavétel (osztó %d), %.2f tick/s, a keverés a CPU %.0f%%-a; "
          "hullámformák: %s; táblák: %d bájt a program után"
          % (sr, args.poly_div, tick_rate, 100 * poly_cpu_load(args.poly_div, args.fast_irq, args.poly_mix == "fast"),
             ", ".join(WAVE_NAMES[WAVES[w]] for w in slots), 256 * (2 + 8 * len(slots))))
    stats.setdefault("chords", 0)
    stats.setdefault("rests", 0)
    report(args, notes, total, tick_rate, stats, len(data))


def report(args, notes, total, rate, stats, size):
    used = sorted({n[2] for n in notes})
    secs = total / rate
    print("%s: %d hang, %d:%04.1f, %d tick; %d hang, %d akkord, %d szünet, %d dobütés; %d bájt"
          % (os.path.basename(args.midi), len(notes), secs // 60, secs % 60, total,
             stats["notes"], stats["chords"], stats["rests"], stats["drums"], size))
    lo, hi = (used[0], used[-1]) if used else (60, 60)
    if used:
        print("hangterjedelem: MIDI %d..%d (%.1f..%.1f Hz)"
              % (lo, hi, note_freq(lo, args.tuning), note_freq(hi, args.tuning)))
    if used and args.mode != "poly" and note_freq(lo, args.tuning) < TVC_CLOCK / 4096:
        print("figyelem: a 47,7 Hz alatti hangok egy oktávval feljebb szólnak")
    if size > args.max_size:
        print("figyelem: %d bájt, a 32k-s gépen kevés lehet a hely" % size)


if __name__ == "__main__":
    main()
