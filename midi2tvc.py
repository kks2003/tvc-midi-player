#!/usr/bin/env python3
"""midi2tvc.py - Standard MIDI fájl (.mid) -> TVC lejátszó adat (song.bin).

A kimenet formátumát a player.asm eleje írja le. Röviden: 8 bájtos fejléc,
128 bejegyzéses PITCH-tábla, majd tick-alapú (képkockánkénti, ~49,7 Hz)
eseménylista.

Üzemmódok:
  mono  egyszólamúsítás: minden pillanatban egy hang szól (a legmagasabb,
        a legmélyebb vagy a legutóbb leütött, --prio)
  arp   akkordok arpeggióval: legfeljebb --max-notes hang, a lejátszó
        --arp-speed tickenként lép közöttük

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
                p += 1
                continue
            a, v = data[p], data[p + 1]
            p += 2
            if hi == 0x90 and v > 0:
                events.append((tick, order, "on", ch, a, v))
            elif hi == 0x80 or hi == 0x90:
                events.append((tick, order, "off", ch, a, 0))
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
    """-> [(start_sec, end_sec, note, velocity, ch)] a kitartó pedállal együtt."""
    conv = tick_to_seconds(division, events)
    open_notes = {}               # (ch, note) -> [(start, vel), ...]
    sustain = [False] * 16
    held = {}                     # pedál miatt kitartott: (ch, note) -> [(start, vel)]
    volume = [100] * 16
    expression = [127] * 16
    notes = []

    def finish(ch, note, start, vel, end):
        notes.append((start, end, note, vel * volume[ch] * expression[ch] / (127 * 127), ch))

    for tick, _, kind, ch, a, b in events:
        t = conv(tick) / speed
        if kind == "tempo":
            continue
        if channels is not None and ch not in channels:
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
            open_notes.setdefault(key, []).append((t, b))
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


def velocity_to_volume(vel, curve, vmin, vmax):
    """MIDI erősség (0..127, a CC7/CC11 már benne) -> 1..15."""
    x = max(0.0, min(1.0, vel / 127.0)) ** curve
    return max(vmin, min(vmax, int(round(vmin + x * (vmax - vmin)))))


def build_ticks(notes, rate):
    """Hangok -> (start_tick, end_tick, note, vel, ch, idx); minden hang
    legalább 1 tick hosszú."""
    out = []
    for i, (s, e, n, v, ch) in enumerate(notes):
        st = int(round(s * rate))
        en = max(st + 1, int(round(e * rate)))
        out.append((st, en, n, v, ch, i))
    return out


def choose(active, mode, prio, max_notes):
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
    pick = sorted(uniq.values(), key=lambda a: -a[0])[:max_notes]
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


def convert(notes, args):
    ticks = build_ticks(notes, args.rate)
    total = max((t[1] for t in ticks), default=0)
    starts = {}
    for t in ticks:
        starts.setdefault(t[0], []).append(t)
    active = {}
    out = bytearray()
    prev = None          # (notes tuple, idx set) az előző tickben
    cur_vol = None
    pending_wait = 0
    stats = {"chords": 0, "notes": 0, "rests": 0}
    for t in range(total + 1):
        for k in [k for k, a in active.items() if a[1] <= t]:
            del active[k]
        for st, en, n, v, ch, idx in starts.get(t, ()):
            active[idx] = (st, en, n, v)
        sel = choose([(a[2], a[3], a[0], i) for i, a in active.items()],
                     args.mode, args.prio, args.max_notes)
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
        pending_wait += 1
    encode_wait(out, pending_wait)
    out.append(0x80)
    if args.loop:
        out.append(0xC0 + 0x0F)           # rövid szünet az ismétlés előtt
    out.append(0xFF)
    return bytes(out), total, stats


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("midi", help="bemeneti .mid fájl")
    ap.add_argument("-o", "--output", default="build/song.bin", help="kimeneti adatfájl")
    ap.add_argument("--title-out", help="a BASIC PRINT sor 32 karakteres címe ide kerül")
    ap.add_argument("--title", help="cím (alapból a fájlnév)")
    ap.add_argument("--mode", choices=("mono", "arp"), default="arp")
    ap.add_argument("--prio", choices=("high", "low", "last"), default="high",
                    help="mono módban melyik hang szóljon (alap: a legmagasabb)")
    ap.add_argument("--max-notes", type=int, default=3, choices=(2, 3, 4),
                    help="arp módban legfeljebb ennyi hang (alap: 3)")
    ap.add_argument("--arp-speed", type=int, default=1,
                    help="arpeggio: ennyi tickenként lép (alap: 1 = ~50 Hz)")
    ap.add_argument("--channels", help="csak ezek a MIDI csatornák (1..16, vesszővel)")
    ap.add_argument("--drums", action="store_true", help="a 10. (dob) csatorna is szóljon")
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
    ap.add_argument("--max-size", type=int, default=20000,
                    help="figyelmeztet, ha az adat ennél nagyobb (a 32k-s TVC miatt)")
    args = ap.parse_args()

    if args.channels:
        channels = {int(c) - 1 for c in args.channels.split(",")}
    else:
        channels = {c for c in range(16) if args.drums or c != DRUM_CHANNEL}
    if not 1 <= args.arp_speed <= 255:
        ap.error("--arp-speed: 1..255")
    if not 0 <= args.decay <= 255:
        ap.error("--decay: 0..255")
    if not 1 <= args.min_volume <= args.max_volume <= 15:
        ap.error("1 <= --min-volume <= --max-volume <= 15")

    with open(args.midi, "rb") as f:
        division, events = parse_midi(f.read())
    notes = collect_notes(division, events, channels, args.transpose, args.speed)
    if not notes:
        sys.exit("a kiválasztott csatornákon nincs hang")
    body, total, stats = convert(notes, args)

    flags = 1 if args.loop else 0
    header = struct.pack("<BBBBHH", flags, args.arp_speed, args.decay,
                         max(0, min(15, args.decay_floor)), 0, 0)
    table = pitch_table(args.tuning)
    data = header + b"".join(struct.pack("<H", p) for p in table) + body

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(data)
    if args.title_out:
        title = args.title if args.title is not None else \
            os.path.splitext(os.path.basename(args.midi))[0]
        t = "".join(c if 32 <= ord(c) < 127 and c != '"' else "_" for c in title)
        with open(args.title_out, "wb") as f:
            f.write(t[:32].ljust(32).encode("ascii"))

    used = sorted({n[2] for n in notes})
    secs = total / args.rate
    print("%s: %d hang, %d:%04.1f, %d tick; %d hang, %d akkord, %d szünet; %d bájt"
          % (os.path.basename(args.midi), len(notes), secs // 60, secs % 60, total,
             stats["notes"], stats["chords"], stats["rests"], len(data)))
    lo, hi = used[0], used[-1]
    print("hangterjedelem: MIDI %d..%d (%.1f..%.1f Hz)"
          % (lo, hi, note_freq(lo, args.tuning), note_freq(hi, args.tuning)))
    if note_freq(lo, args.tuning) < TVC_CLOCK / 4096:
        print("figyelem: a 47,7 Hz alatti hangok egy oktávval feljebb szólnak")
    if len(data) > args.max_size:
        print("figyelem: %d bájt, a 32k-s gépen kevés lehet a hely" % len(data))


if __name__ == "__main__":
    main()
