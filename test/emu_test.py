#!/usr/bin/env python3
"""Végponttól végpontig tartó teszt a valódi TVC ROM-mal, az Ep128web
emulátormagjával (ep128emu, natívan fordítva).

    python3 test/emu_test.py --ep128web ../Ep128web --roms ep128emu_roms-2.0.11.bin

Lépések: tesztdal (test/make_test_mid.py) -> build.sh -> .cas a FILE:
eszközre (/files) -> TVC 64k+ boot -> load "teszt" (autorun) ->
hangfelvétel és portnapló -> ellenőrzések.  Kell: g++, gcc, sjasmplus, és
írási jog a /files könyvtárba (az Ep128web FILE: eszköze oda mutat).
"""
import argparse, glob, math, os, shutil, struct, subprocess, sys, tempfile, wave

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


def isr_restored(res):
    """az IT-belépő (0038h..003Fh) ugyanaz, mint a betöltés előtt"""
    before = res.split("isr0=")[1].split("\n")[0].strip()
    after = res.split("isr=")[1].split("time=")[0].strip()
    return before == after and before.startswith("f5 3e 70 d3 02 c3")


def basic_ok(ppm):
    """A BASIC a lejátszás után "ok"-kal folytatja, nem hibaüzenettel: a
    képernyő szövegsorai közül a 7. (a betöltött program címe utáni sor)
    ugyanolyan rövid, mint a 4. ("ok" a bekapcsolás után)."""
    data = open(ppm, "rb").read()
    parts = data.split(b"\n", 3)
    w, h = (int(x) for x in parts[1].split())
    px = parts[3]
    rows = []
    for y in range(h):
        line = px[y * w * 3:(y + 1) * w * 3]
        xs = [x for x in range(0, w) if sum(line[x * 3:x * 3 + 3]) > 200]
        rows.append((min(xs), max(xs)) if xs else None)
    lines, cur = [], None
    for y, r in enumerate(rows):
        if r and cur is None:
            cur = [r[0], r[1]]
        elif r:
            cur = [min(cur[0], r[0]), max(cur[1], r[1])]
        elif cur is not None:
            lines.append(cur)
            cur = None
    if cur is not None:
        lines.append(cur)
    if len(lines) < 7:
        return False
    width = lambda l: l[1] - l[0]
    return width(lines[6]) <= width(lines[3]) * 1.5


def peak_cents(samples, rate, f0):
    """A legerősebb összetevő eltérése f0-tól centben (±50 cent, 1 centes
    lépésekben, Hann-ablakkal): a lépcsős, halkuló szinuszra is jó, ahol a
    nullátmenetek számlálása téved."""
    n = len(samples)
    mean = sum(samples) / n
    x = [(v - mean) * (0.5 - 0.5 * math.cos(2 * math.pi * i / n)) for i, v in enumerate(samples)]
    best, bc = -1, 0
    for c in range(-50, 51):
        w = 2 * math.pi * f0 * 2 ** (c / 1200.0) / rate
        re = sum(v * math.cos(w * i) for i, v in enumerate(x))
        im = sum(v * math.sin(w * i) for i, v in enumerate(x))
        p = re * re + im * im
        if p > best:
            best, bc = p, c
    return bc


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
    ap.add_argument("--machine", default="tvc64-12", choices=("tvc64-12", "tvc32-12", "tvc64p-22"),
                    help="a fő tesztek gépe (alap: TVC 64k, BASIC 1.2, mint az Ep128web-ben)")
    args = ap.parse_args()
    os.environ["MACHINE"] = args.machine
    print("gép:", args.machine)

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
    scr1 = os.path.join(out, "teszt.ppm")
    res = subprocess.check_output([exe, args.roms, "teszt", "16", wav, plog], env=dict(os.environ, SCREEN=scr1)).decode()
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
    check("az IT-belépő visszaállt (PUSH AF / LD A,70h / OUT (02h),A / JP ROM)", isr_restored(res))
    check("a dal végén a BASIC hiba nélkül folytatja (ok)", basic_ok(scr1))

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
    scr2 = os.path.join(out, "esc.ppm")
    res = subprocess.check_output([exe, args.roms, "teszt", "6", wav2, plog2, "3"], env=dict(os.environ, SCREEN=scr2)).decode()
    with wave.open(wav2) as w:
        d2 = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
    tail = d2[-rate:]
    check("ESC: leáll a hang", max(tail) - min(tail) < 200)
    check("ESC: az IT-belépő visszaállt", isr_restored(res))
    check("ESC: a BASIC hiba nélkül folytatja (ok)", basic_ok(scr2))
    # 3. többszólamú motor (--mode poly)
    subprocess.check_call([os.path.join(REPO, "build.sh"), mid, "--mode", "poly", "--decay", "4"])
    shutil.copy(os.path.join(REPO, "build", "teszt.cas"), "/files/poly.cas")
    wav3 = os.path.join(out, "poly.wav")
    scr3 = os.path.join(out, "poly.ppm")
    res = subprocess.check_output([exe, args.roms, "poly", "16", wav3, os.path.join(out, "poly_ports.txt")],
                                  env=dict(os.environ, SCREEN=scr3)).decode()
    check("poly: a dal végén a BASIC hiba nélkül folytatja (ok; IX, IY, árnyékregiszterek)", basic_ok(scr3))
    with wave.open(wav3) as w:
        d3 = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
    st = next((i for i in range(len(d3)) if abs(d3[i] - d3[0]) > 200), None)
    check("poly: szól a hang", st is not None)
    if st is not None:
        cents = []
        for k, n in ((0.1, 60), (0.6, 62), (3.6, 72)):          # C4, D4, C5
            f = zero_cross_freq(d3[st + int(k * rate): st + int((k + 0.3) * rate)], rate)
            cents.append(1200 * math.log2(f / midi2tvc.note_freq(n, 440.0)) if f else 999)
        check("poly: a hangmagasság pontos (C4, D4, C5: ±5 cent)", all(abs(c) < 5 for c in cents),
              ", ".join("%.1f" % c for c in cents))
        env = [max(d3[i:i + rate // 200]) - min(d3[i:i + rate // 200])
               for i in range(st, st + 5 * rate, rate // 200)]
        ons = [i * 5 for i in range(1, len(env)) if env[i] > 200 and env[i - 1] <= 200]
        check("poly: időzítés (a C5 3,5 s-nál, ±30 ms)", len(ons) >= 7 and abs(ons[6] - 3500) <= 30,
              "%s ms" % (ons[6] if len(ons) >= 7 else ons))
        # az első akkord (C2 + C-dúr): G4 (dallam), C2 (basszus), E4 egyszerre
        seg = d3[st + int(4.2 * rate): st + int(5.2 * rate)]
        mean = sum(seg) / len(seg)
        def power(f):
            c = sum((x - mean) * math.cos(2 * math.pi * f * i / rate) for i, x in enumerate(seg))
            s_ = sum((x - mean) * math.sin(2 * math.pi * f * i / rate) for i, x in enumerate(seg))
            return math.hypot(c, s_)
        # a csúcs ±3 Hz-en belül (a tick alatti megállások kissé szétkenik)
        p = {f: max(power(f + k * 0.5) for k in range(-6, 7)) for f in (65.41, 329.63, 392.0, 293.66)}
        check("poly: akkord: C2, E4 és G4 egyszerre szól (D4 nem)",
              min(p[65.41], p[329.63], p[392.0]) > 10 * p[293.66],
              "C2 %.0f, E4 %.0f, G4 %.0f, D4 %.0f" % (p[65.41] / 1e3, p[329.63] / 1e3, p[392.0] / 1e3, p[293.66] / 1e3))
        tail = d3[-rate:]
        check("poly: a dal végén csend", max(tail) - min(tail) < 200)
    check("poly: a rendszer IT-belépése érintetlen", isr_restored(res))
    wav4 = os.path.join(out, "poly_esc.wav")
    subprocess.check_output([exe, args.roms, "poly", "7", wav4, os.path.join(out, "poly_esc.txt"), "4"])
    with wave.open(wav4) as w:
        d4 = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
    check("poly: ESC: leáll a hang", max(d4[-rate:]) - min(d4[-rate:]) < 200)

    # 4. háttér-mód (--background): a zene szól, a BASIC közben dolgozik
    subprocess.check_call([os.path.join(REPO, "build.sh"), mid, "--background", "--loop", "--decay", "4"])
    shutil.copy(os.path.join(REPO, "build", "teszt.cas"), "/files/bg.cas")
    wav5 = os.path.join(out, "bg.wav")
    env = dict(os.environ, DUMP="7530,1", TYPE_AT="5:poke 30000,42\\n;9:ext 0\\n;12:ext 1\\n")
    res = subprocess.check_output([exe, args.roms, "bg", "17", wav5, os.path.join(out, "bg_ports.txt")], env=env).decode()
    with wave.open(wav5) as w:
        d5 = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
    def sounding(t0, t1):
        seg = d5[int(t0 * rate): int(t1 * rate)]
        return max(seg) - min(seg) > 200
    check("háttér: a BASIC a zene alatt is végrehajtja a parancsokat (POKE)", "dump 7530: 2a" in res)
    check("háttér: a zene a gépelés alatt végig szól (3..11 s)",
          all(sounding(t, t + 0.5) for t in [x * 0.5 for x in range(6, 22)]))
    check("háttér: EXT 0 leállítja", not sounding(13.0, 14.5))
    check("háttér: EXT 1 újraindítja", sounding(15.5, 17.0))
    # NEW után új program, RUN: a BASIC a lefoglalt blokk alá teszi a vermét
    wav6 = os.path.join(out, "bg_new.wav")
    res6 = subprocess.check_output([exe, args.roms, "bg", "16", wav6, os.path.join(out, "bg_new_ports.txt")],
                                   env=dict(os.environ, DUMP="7531,1",
                                            TYPE_AT="4:new\\n;6:10 poke 30001,7\\n;11:run\\n")).decode()
    with wave.open(wav6) as w:
        d6 = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
    seg_ok = all(max(d6[int(t * rate):int((t + 0.5) * rate)]) - min(d6[int(t * rate):int((t + 0.5) * rate)]) > 200
                 for t in [x * 0.5 for x in range(6, 30)])
    check("háttér: NEW, új program begépelése és RUN alatt a zene végig szól, a program lefut",
          "dump 7531: 07" in res6 and seg_ok)
    res2 = subprocess.check_output([exe, args.roms, "bg", "4", os.path.join(out, "bg2.wav"),
                                    os.path.join(out, "bg2_ports.txt")],
                                   env=dict(os.environ, DUMP="0B19,2")).decode()
    hm = res2.split("dump 0b19:")[1].split()
    himem = int(hm[0], 16) | (int(hm[1], 16) << 8)
    res3 = subprocess.check_output([exe, args.roms, "bg", "4", os.path.join(out, "bg3.wav"),
                                    os.path.join(out, "bg3_ports.txt")],
                                   env=dict(os.environ, DUMP="0021,4")).decode()
    u = [int(x, 16) for x in res3.split("dump 0021:")[1].split()[:4]]
    ext0, ext1 = u[0] | (u[1] << 8), u[2] | (u[3] << 8)
    check("háttér: a HIMEM lejjebb került, az EXT 0/1 a lefoglalt blokkba mutat",
          himem < 0xBF00 and ext1 == himem + 1 and himem < ext0 < 0xC000,
          "HIMEM %04Xh, EXT 0 %04Xh, EXT 1 %04Xh" % (himem, ext0, ext1))

    # 5. a többi gép: mindkét lejátszó, és a háttér-mód a 32k-s gépen
    shutil.copy(os.path.join(REPO, "build", "teszt.cas"), "/files/bg.cas")      # az utolsó build: --background
    subprocess.check_call([os.path.join(REPO, "build.sh"), mid, "--decay", "4"], stdout=subprocess.DEVNULL)
    shutil.copy(os.path.join(REPO, "build", "teszt.cas"), "/files/arp.cas")
    subprocess.check_call([os.path.join(REPO, "build.sh"), mid, "--mode", "poly", "--wave", "sine", "--decay", "4"],
                          stdout=subprocess.DEVNULL)
    shutil.copy(os.path.join(REPO, "build", "teszt.cas"), "/files/sin.cas")
    for mach in [m for m in ("tvc64p-22", "tvc64-12", "tvc32-12") if m != args.machine]:
        for name, label in (("arp", "egycsatornás"), ("sin", "poly, szinusz")):
            wv, scr = os.path.join(out, mach + "_" + name + ".wav"), os.path.join(out, mach + "_" + name + ".ppm")
            r = subprocess.check_output([exe, args.roms, name, "14", wv, os.path.join(out, "x_ports.txt")],
                                        env=dict(os.environ, MACHINE=mach, SCREEN=scr)).decode()
            with wave.open(wv) as w:
                dd = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
            st = next((i for i in range(len(dd)) if abs(dd[i] - dd[0]) > 200), None)
            c = peak_cents(dd[st + int(0.1 * rate): st + int(0.3 * rate)], rate,
                           midi2tvc.note_freq(60, 440.0)) if st is not None else 999
            check("%s, %s: C4 pontos, a végén csend, az IT-belépő visszaállt, ok" % (mach, label),
                  abs(c) < 5 and max(dd[-rate:]) - min(dd[-rate:]) < 200 and isr_restored(r) and basic_ok(scr),
                  "%d cent" % c)
    if args.machine != "tvc32-12":
        r = subprocess.check_output([exe, args.roms, "bg", "12", os.path.join(out, "bg32.wav"),
                                     os.path.join(out, "x_ports.txt")],
                                    env=dict(os.environ, MACHINE="tvc32-12", DUMP="0B19,2")).decode()
        hm = r.split("dump 0b19:")[1].split()
        himem = int(hm[0], 16) | (int(hm[1], 16) << 8)
        with wave.open(os.path.join(out, "bg32.wav")) as w:
            dd = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
        seg = dd[int(5 * rate):int(10 * rate)]
        check("tvc32-12, háttér-mód: a HIMEM 8000h alá kerül, a zene szól",
              himem < 0x8000 and max(seg) - min(seg) > 200, "HIMEM %04Xh" % himem)

    print("eredmények: %s" % out)
    print("HIBÁK: %d" % bad if bad else "minden ellenőrzés rendben")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
