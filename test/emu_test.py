#!/usr/bin/env python3
"""Végponttól végpontig tartó teszt a valódi TVC ROM-mal, az Ep128web
emulátormagjával (ep128emu, natívan fordítva).

    python3 test/emu_test.py --ep128web ../Ep128web --roms ep128emu_roms-2.0.11.bin

Lépések: tesztdal (test/make_test_mid.py) -> build.sh -> .cas a FILE:
eszközre (/files) -> TVC 64k+ boot -> load "teszt" (autorun) ->
hangfelvétel és portnapló -> ellenőrzések.  Kell: g++, gcc, sjasmplus, és
írási jog a /files könyvtárba (az Ep128web FILE: eszköze oda mutat).
"""
import argparse, glob, os, shutil, struct, subprocess, sys, tempfile, wave

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, REPO)
import midi2tvc  # noqa: E402


def build_emulator(root, objdir):
    """Az Ep128web build.sh-jában felsorolt forrásokat natívan lefordítja."""
    E = os.path.join(root, "ep128emu")
    if not os.path.exists(os.path.join(E, "src", "tvc64vm.cpp")):
        sys.exit("hiányzik az ep128emu almodul: git -C %s submodule update --init" % root)
    # az Ep128web javításai (ugyanúgy, mint a build.sh)
    for patch in sorted(glob.glob(os.path.join(root, "patches", "*.patch"))):
        if subprocess.call(["git", "-C", E, "apply", "--check", patch],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
            subprocess.check_call(["git", "-C", E, "apply", patch])
    txt = open(os.path.join(root, "build.sh")).read()
    block = txt.split('SOURCES="')[1].split('"')[0]
    srcs = []
    for l in block.split():
        if l.startswith("$(ls ") or l.endswith(")"):       # $(ls minta) a build.sh-ban
            l = l.replace("$(ls", "").rstrip(")")
            if l:
                srcs += sorted(glob.glob(os.path.join(root, l)))
        elif l.endswith((".cpp", ".c")):
            srcs.append(l.replace("$E", E))
    srcs = [s if os.path.isabs(s) else os.path.join(root, s) for s in srcs]
    srcs.append(os.path.join(HERE, "emu_harness.cpp"))
    inc = ["-I" + os.path.join(root, p) for p in
           ("test/native_shim", "web/stubs", "web/src", "web/src/twodfx/include", "web/src/lua")]
    inc += ["-I" + E + "/src", "-I" + E + "/z80", "-I" + E]
    cxx = ["g++", "-std=gnu++17", "-O2", "-w", "-fpermissive", "-DHAVE_STDINT_H", "-DZ80_ENABLE_CMOS",
           "-DCPC_LSB_FIRST=1", "-DENABLE_SDEXT", "-DHAVE_LUA_H"] + inc
    tdx = os.path.join(root, "web/src/twodfx")
    os.makedirs(objdir, exist_ok=True)
    objs = []
    for s in srcs:
        o = os.path.join(objdir, s.replace("/", "_") + ".o")
        if "/web/src/lua/" in s:
            cmd = ["gcc", "-O2", "-w", "-DLUA_COMPAT_5_2"]
        elif "/web/src/twodfx/" in s and s.endswith(".c"):
            cmd = ["gcc", "-O2", "-std=c99", "-w"] + ["-I" + os.path.join(tdx, d) for d in
                   ("include", "core", "assets", "firmware_eggs", "firmware_eggs/portable")]
        elif s.endswith(".c"):
            cmd = ["gcc", "-std=gnu11", "-O2", "-w", "-DHAVE_STDINT_H", "-DLFS_NO_ASSERT"] + inc
        else:
            cmd = cxx + (["-Dmain=ep_unused_emscripten_main"] if s.endswith("web/src/main.cpp") else [])
        if not os.path.exists(o) or os.path.getmtime(o) < os.path.getmtime(s):
            subprocess.check_call(cmd + ["-c", s, "-o", o])
        objs.append(o)
    # a TVC256k++ kártya mentendő változóinak listája (az Ep128web build.sh
    # generálja); a teszt nem használja a kártyát, elég egy üres lista
    stub = os.path.join(objdir, "cardstate_stub.c")
    with open(stub, "w") as f:
        f.write("struct card_state_region { void *p; unsigned n; };\n"
                "const struct card_state_region card_state_regions[1] = {{0, 0}};\n"
                "const unsigned card_state_region_count = 0;\n")
    subprocess.check_call(["gcc", "-c", stub, "-o", stub + ".o"])
    objs.append(stub + ".o")
    exe = os.path.join(objdir, "emu_harness")
    subprocess.check_call(["g++"] + objs + ["-o", exe])
    return exe


def zero_cross_freq(samples, rate):
    """Alapfrekvencia a középszint-átlépésekből (négyszögjelre pontos)."""
    if len(samples) < 16:
        return 0.0
    lo, hi = min(samples), max(samples)
    if hi - lo < 200:
        return 0.0
    mid = (lo + hi) / 2
    ups = [i for i in range(1, len(samples)) if samples[i - 1] < mid <= samples[i]]
    if len(ups) < 3:
        return 0.0
    return (len(ups) - 1) * rate / (ups[-1] - ups[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ep128web", default=os.path.join(REPO, "..", "Ep128web"))
    ap.add_argument("--roms", required=True, help="ep128emu_roms-2.0.11.bin")
    ap.add_argument("--keep", help="a felvétel (wav) és a portnapló ide kerül")
    args = ap.parse_args()

    out = args.keep or tempfile.mkdtemp(prefix="tvcmidi_")
    os.makedirs(out, exist_ok=True)
    exe = build_emulator(os.path.abspath(args.ep128web), os.path.join(tempfile.gettempdir(), "tvcmidi_emu_obj"))

    mid = os.path.join(out, "teszt.mid")
    subprocess.check_call([sys.executable, os.path.join(HERE, "make_test_mid.py"), mid], stdout=subprocess.DEVNULL)
    subprocess.check_call([os.path.join(REPO, "build.sh"), mid, "--mode", "arp", "--decay", "4"])
    os.makedirs("/files", exist_ok=True)
    shutil.copy(os.path.join(REPO, "build", "teszt.cas"), "/files/teszt.cas")

    bad = 0
    def check(name, ok, info=""):
        nonlocal bad
        print("%s: %s%s" % ("OK  " if ok else "HIBA", name, (" (" + info + ")") if info else ""))
        bad += 0 if ok else 1

    # 1. a teljes dal (~10 s) + utána csend
    wav, plog = os.path.join(out, "teszt.wav"), os.path.join(out, "teszt_ports.txt")
    res = subprocess.check_output([exe, args.roms, "teszt", "16", wav, plog]).decode()
    print(res.strip())
    sym = {}
    for line in open(os.path.join(REPO, "build", "teszt.sym")):
        if ": EQU " in line:
            k, v = line.split(": EQU ")
            sym[k.strip()] = int(v, 16)
    lo, hi = sym["start"], sym["song"]
    writes = []
    for line in open(plog):
        fr, pc, port, val = line.split()
        writes.append((int(fr), int(pc, 16), int(port, 16), int(val, 16)))
    mine = [w for w in writes if lo <= w[1] < hi]
    dlo, dhi = sym["drum_start"], sym["drum_code_end"]
    drum_w = [w for w in mine if dlo <= w[1] < dhi]
    mine = [w for w in mine if not dlo <= w[1] < dhi]      # a dallam írásai
    check("a lejátszó írja a hangportokat (04h/05h/06h)", len(mine) > 20, "%d írás" % len(mine))
    check("az IT-vektor visszaállt (PUSH AF / LD A,70h)", res.split("isr=")[1].startswith("f5 3e 70"))

    # a kiadott PITCH-ek: a lejátszó 04h, majd 05h írásai
    table = midi2tvc.pitch_table(440.0)
    inv = {p: n for n, p in enumerate(table)}
    seq, lo8, first = [], None, None
    for fr, pc, port, val in mine:
        if port == 4:
            lo8 = val
        elif port == 5 and lo8 is not None and val & 0x10:
            p = lo8 | ((val & 0x0F) << 8)
            if first is None:
                first = fr
            seq.append((fr - first, inv.get(p, -p)))
            lo8 = None
    scale = []
    for _, n in seq:
        if not scale or scale[-1] != n:
            scale.append(n)
    check("a skála hangjai sorban szólnak", scale[:8] == [60, 62, 64, 65, 67, 69, 71, 72],
          "kapott: %s" % scale[:8])
    # arpeggio (--max-notes 3): az első akkordból (C2 + C-dúr) a három
    # legmagasabb hang, C4-E4-G4 váltakozik tickenként
    chord_part = [n for fr, n in seq if 8 * 25 + 5 <= fr < 8 * 25 + 60]
    check("arpeggio: C4-E4-G4 tickenként váltakozik",
          len(chord_part) > 30 and all(chord_part[i] != chord_part[i + 1] for i in range(len(chord_part) - 1))
          and set(chord_part) == {60, 64, 67}, "kapott: %s" % chord_part[:9])
    # időzítés: a skála 8 hangja 120 BPM-en 4 s = ~199 tick
    t_c5 = next(fr for fr, n in seq if n == 72)
    check("időzítés: a C5 a 7*0,5 s = 3,5 s-nál (174 tick) szólal meg", abs(t_c5 - 174) <= 1,
          "%d tick" % t_c5)

    # a második akkord (F-dúr: C4-F4-A4) a dob közben is megszólal
    second = {n for fr, n in seq if 8 * 25 + 80 <= fr < 8 * 25 + 150}
    check("a dob mellett a dallam halad (2. akkord: C4-F4-A4)", {60, 65, 69} <= second,
          "kapott: %s" % sorted(second))

    # dob: zajlöket (05h b4 = 0) a dobkódból, és a lábdob 160 Hz-es hangja
    noise_frames = {fr for fr, pc, port, val in drum_w if port == 5 and not val & 0x10}
    check("dob: zajlöketek (DAC-mód) a pergő/cin/crash ütéseknél", len(noise_frames) >= 10,
          "%d tick" % len(noise_frames))
    kick = int(round(midi2tvc.pitch_value(160)))
    kicks = [fr for i, (fr, pc, port, val) in enumerate(drum_w)
             if port == 4 and val == kick & 0xFF and i + 1 < len(drum_w)
             and drum_w[i + 1][2] == 5 and drum_w[i + 1][3] & 0x0F == kick >> 8]
    check("dob: lábdob (160 Hz-ről induló csúszás) 3 ütés", len(kicks) == 3, "%d" % len(kicks))

    # a hangfelvétel: az első skálahang (C4 = 261,6 Hz) frekvenciája
    with wave.open(wav) as w:
        rate = w.getframerate()
        data = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
    start = next((i for i in range(len(data)) if abs(data[i] - data[0]) > 200), None)
    check("szól a hang", start is not None)
    if start is not None:
        seg = data[start + rate // 20: start + rate * 4 // 10]
        f = zero_cross_freq(seg, rate)
        want = midi2tvc.TVC_CLOCK / (4096 - table[60])
        check("az első hang frekvenciája", abs(f - want) < 1.0, "%.2f Hz, várt %.2f Hz" % (f, want))
        tail = data[-rate:]
        check("a dal végén csend", max(tail) - min(tail) < 200)
        # zaj: 5 ms-os ablakokban a középszint-átlépések száma (a dallam
        # legmagasabb hangja 523 Hz, ez ~5 átlépés / 5 ms)
        win = rate // 200
        best = 0
        for i in range(start, len(data) - win, win):
            seg = data[i:i + win]
            m = (max(seg) + min(seg)) / 2
            if max(seg) - min(seg) > 200:
                best = max(best, sum(1 for j in range(1, win) if (seg[j - 1] < m) != (seg[j] < m)))
        check("dob: a felvételben van zaj", best >= 30, "max. %d átlépés / 5 ms" % best)

    # 2. ESC megállítja a lejátszást
    wav2, plog2 = os.path.join(out, "esc.wav"), os.path.join(out, "esc_ports.txt")
    res = subprocess.check_output([exe, args.roms, "teszt", "6", wav2, plog2, "3"]).decode()
    with wave.open(wav2) as w:
        d2 = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
    tail = d2[-rate:]
    check("ESC: leáll a hang", max(tail) - min(tail) < 200)
    check("ESC: az IT-vektor visszaállt", res.split("isr=")[1].startswith("f5 3e 70"))
    print("eredmények: %s" % out)
    print("HIBÁK: %d" % bad if bad else "minden ellenőrzés rendben")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
