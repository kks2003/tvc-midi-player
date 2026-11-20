#!/usr/bin/env python3
# tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
# Copyright (C) 2026 kks2003 és a közreműködők
#
# Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
# Foundation által kiadott GNU General Public License 2. vagy (választás
# szerint) bármely későbbi változata szerint. A programot a hasznosság
# reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
#
"""A webes konverter (web/midi2tvc.js) és a Python változat bájtra azonos
kimenetének ellenőrzése: ugyanazokkal a beállításokkal a build.sh és a
node is elkészíti a .cas fájlt.  A weboldal forráscsomagját is ellenőrzi:
a csomag build.sh-ja és a README-ben megadott parancssor is ugyanezt a
.cas-t adja.  Kell: node, sjasmplus.

    python3 test/web_parity.py [további.mid ...]
"""
import json, math, os, shlex, shutil, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# (a parancssori kapcsolók, ugyanez a JS opciókkal)
CASES = [
    ([], {}),
    (["--mode", "mono"], {"mode": "mono"}),
    (["--mode", "mono", "--prio", "last", "--decay", "2"], {"mode": "mono", "prio": "last", "decay": 2}),
    (["--mode", "mono", "--prio", "low"], {"mode": "mono", "prio": "low"}),
    (["--max-notes", "2", "--arp-bass", "--arp-speed", "2", "--loop"],
     {"maxNotes": 2, "arpBass": True, "arpSpeed": 2, "loop": True}),
    (["--drums", "pitched", "--transpose", "-12", "--speed", "1.25"],
     {"drums": "pitched", "transpose": -12, "speed": 1.25}),
    (["--drums", "off", "--tuning", "432", "--curve", "1.3", "--min-volume", "3", "--max-volume", "12"],
     {"drums": "off", "tuning": 432, "curve": 1.3, "minVolume": 3, "maxVolume": 12}),
    (["--mode", "poly"], {"mode": "poly"}),
    (["--mode", "poly", "--decay", "4", "--decay-floor", "5", "--poly-volume", "11", "--poly-mix", "soft",
      "--poly-knee", "8", "--loop"],
     {"mode": "poly", "decay": 4, "decayFloor": 5, "polyVolume": 11, "polyMix": "soft", "polyKnee": 8, "loop": True}),
    (["--mode", "poly", "--poly-volume", "12", "--wave", "sine"], {"mode": "poly", "polyVolume": 12, "wave": "sine"}),
    (["--mode", "poly", "--loop", "--channel-wave", "1=saw"], {"mode": "poly", "loop": True, "channelWave": {"1": "saw"}}),
    (["--from", "4.5", "--to", "9.25"], {"from": 4.5, "to": 9.25}),
    (["--from", "4.5", "--to", "9.25", "--trim", "--loop"], {"from": 4.5, "to": 9.25, "trim": True, "loop": True}),
    (["--mode", "poly", "--from", "2", "--trim"], {"mode": "poly", "from": 2, "trim": True}),
    (["--mode", "poly", "--to", "30", "--speed", "1.5"], {"mode": "poly", "to": 30, "speed": 1.5}),
    (["--trim"], {"trim": True}),
    (["--loop", "--loop-pause", "3"], {"loop": True, "loopPause": 3}),
    (["--drum-volume", "60"], {"drumVolume": 60}),
    (["--gain", "150"], {"gain": 150}),
    (["--mode", "poly", "--bend"], {"mode": "poly", "bend": True}),
    (["--mode", "poly", "--cards", "sn", "--bend", "--fast-irq"], {"mode": "poly", "cards": ["sn"], "bend": True, "fastIrq": True}),
    (["--mode", "poly", "--cards", "sn,sid"], {"mode": "poly", "cards": ["sn", "sid"]}),
    (["--mode", "poly", "--cards", "saa"], {"mode": "poly", "cards": ["saa"]}),
    (["--mode", "poly", "--cards", "opl,sn"], {"mode": "poly", "cards": ["sn", "opl"]}),
    (["--mode", "poly", "--cards", "sn,sid,saa,opl", "--fast-irq"], {"mode": "poly", "cards": ["sn", "sid", "saa", "opl"], "fastIrq": True}),
    (["--mode", "poly", "--bend", "--envelopes", "tvc", "--from", "1", "--to", "6"],
     {"mode": "poly", "bend": True, "envelopes": "tvc", "from": 1, "to": 6}),
    (["--mode", "poly", "--fast-irq", "--wave", "sine"], {"mode": "poly", "fastIrq": True, "wave": "sine"}),
    (["--mode", "poly", "--poly-mix", "fast"], {"mode": "poly", "polyMix": "fast"}),
    (["--mode", "poly", "--poly-mix", "fast", "--fast-irq", "--gain", "max"], {"mode": "poly", "polyMix": "fast", "fastIrq": True, "gain": "max"}),
    (["--mode", "poly", "--envelopes", "midiplay"], {"mode": "poly", "envelopes": "midiplay"}),
    (["--mode", "poly", "--envelopes", "tvc", "--loop", "--decay", "3", "--gain", "max"],
     {"mode": "poly", "envelopes": "tvc", "loop": True, "decay": 3, "gain": "max"}),
    (["--mode", "poly", "--envelopes", "tvc", "--wave", "triangle", "--from", "3", "--to", "20"],
     {"mode": "poly", "envelopes": "tvc", "wave": "triangle", "from": 3, "to": 20}),
    (["--gain", "60", "--mode", "poly"], {"gain": 60, "mode": "poly"}),
    (["--gain", "max", "--mode", "poly", "--poly-mix", "soft"], {"gain": "max", "mode": "poly", "polyMix": "soft"}),
    (["--gain", "max", "--mode", "arp"], {"gain": "max", "mode": "arp"}),
    (["--gain", "130", "--mode", "mono", "--drum-volume", "70"], {"gain": 130, "mode": "mono", "drumVolume": 70}),
    (["--drum-volume", "150", "--mode", "poly"], {"drumVolume": 150, "mode": "poly"}),
    (["--drum-volume", "35", "--mode", "arp"], {"drumVolume": 35, "mode": "arp"}),
    (["--mode", "poly", "--loop", "--trim", "--loop-pause", "9"], {"mode": "poly", "loop": True, "trim": True, "loopPause": 9}),
    (["--mode", "poly", "--channels", "1,4,6,5,10"], {"mode": "poly", "channels": [1, 4, 6, 5, 10]}),
    (["--channels", "1,2,10", "--max-notes", "4"], {"channels": [1, 2, 10], "maxNotes": 4}),
    (["--mode", "mono", "--background", "--loop"], {"mode": "mono", "background": True, "loop": True}),
    (["--mode", "poly", "--wave", "saw", "--poly-div", "23", "--channel-wave", "1=triangle,6=pulse"],
     {"mode": "poly", "wave": "saw", "polyDiv": 23, "channelWave": {"1": "triangle", "6": "pulse"}}),
    (["--mode", "poly", "--wave", "triangle", "--drums", "off"], {"mode": "poly", "wave": "triangle", "drums": "off"}),
    (["--mode", "poly", "--wave", "sine", "--channel-wave", "6=saw"], {"mode": "poly", "wave": "sine", "channelWave": {"6": "saw"}}),
]

RUNNER = r"""
const fs = require('fs');
const M = require(process.argv[2] + '/web/midi2tvc.js');
const P = require(process.argv[2] + '/web/players.js');
require(process.argv[2] + '/web/envelopes.js');
const job = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const A = require(process.argv[2] + '/web/assembler.js');
const SjasmPlus = require(process.argv[2] + '/web/sjasmplus/sjasmplus.js');
(async () => {
  const r = M.convertMidi(new Uint8Array(fs.readFileSync(job.midi)), job.opts);
  // a böngészős sjasmplus a dalhoz kellő részekkel fordít; mellette a tartalék
  // (előre fordított, minden funkcióval) is összeáll
  const run = await A.createAssembler(SjasmPlus, fs.readFileSync(process.argv[2] + '/web/sjasmplus/sjasmplus.wasm'));
  const cas = (await M.assembleCas(run, P, r, job.title)).cas;
  fs.writeFileSync(job.out, cas);
  M.buildCas(r.mode === 'poly' ? P.poly : P.mono, r.song, job.title);
  const name = 'par';
  const files = M.sourcePackage({ players: P, result: r, midiBytes: new Uint8Array(fs.readFileSync(job.midi)),
    midiName: name + '.mid', name, title: job.title, casBytes: cas });
  fs.writeFileSync(job.zip, M.zipFiles(files, /\.sh$/));
})();
"""


def bend_midi():
    """próbadal: pitch bend (RPN 0 tartomány 12 félhang), modulációs kerék"""
    import struct
    def vlq(n):
        b = [n & 0x7F]
        n >>= 7
        while n:
            b.append(0x80 | (n & 0x7F))
            n >>= 7
        return bytes(reversed(b))
    ev = [(0, bytes((0xB0, 101, 0))), (0, bytes((0xB0, 100, 0))), (0, bytes((0xB0, 6, 12))),
          (0, bytes((0xC0, 80))), (0, bytes((0x90, 60, 100))), (0, bytes((0x91, 48, 90)))]
    for k in range(1, 40):
        v = 8192 + int(8000 * math.sin(k / 6.0))
        ev.append((k * 24, bytes((0xE0, v & 0x7F, v >> 7))))
    ev += [(960, bytes((0xB1, 1, 127))), (1900, bytes((0x80, 60, 0))), (1920, bytes((0x90, 64, 100))),
           (2880, bytes((0xE0, 0, 64))), (3840, bytes((0x80, 64, 0))), (3840, bytes((0x81, 48, 0)))]
    trk = b"".join(vlq(t - p) + e for (t, e), p in zip(ev, [0] + [x[0] for x in ev])) + b"\x00\xff\x2f\x00"
    path = os.path.join(tempfile.mkdtemp(prefix="tvcbend_"), "bend.mid")
    open(path, "wb").write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480) + b"MTrk" + struct.pack(">I", len(trk)) + trk)
    return path


def main():
    mids = sys.argv[1:] or [os.path.join(REPO, "examples", "teszt.mid")]
    duck = os.path.join(REPO, "examples", "ducktales", "ducktales.mid")
    if not sys.argv[1:] and os.path.exists(duck):
        mids.append(duck)
    if not sys.argv[1:]:
        mids.append(bend_midi())
    subprocess.check_call([sys.executable, os.path.join(REPO, "tools", "export_players.py")],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tmp = tempfile.mkdtemp(prefix="tvcweb_")
    runner = os.path.join(tmp, "run.js")
    open(runner, "w").write(RUNNER)
    bad = n = 0
    for mid in mids:
        for args, opts in CASES:
            # a hajlítás próbadala rövid: csak az alap és a --bend esetek
            if mid.endswith("bend.mid") and args and "--bend" not in args and args != ["--mode", "poly"]:
                continue
            name = "par"
            src = os.path.join(tmp, name + ".mid")
            shutil.copy(mid, src)
            subprocess.check_call([os.path.join(REPO, "build.sh"), src] + args, stdout=subprocess.DEVNULL)
            want = open(os.path.join(REPO, "build", name + ".cas"), "rb").read()
            job = os.path.join(tmp, "job.json")
            out = os.path.join(tmp, "js.cas")
            zpath = os.path.join(tmp, "src.zip")
            json.dump({"midi": src, "opts": opts, "title": name, "out": out, "zip": zpath}, open(job, "w"))
            subprocess.check_call(["node", runner, REPO, job])
            got = open(out, "rb").read()
            n += 1
            ok = got == want
            # a forráscsomag: a saját build.sh-ja és a README parancssora
            pkg = os.path.join(tmp, "pkg")
            shutil.rmtree(pkg, ignore_errors=True)
            with zipfile.ZipFile(zpath) as z:
                assert z.testzip() is None
                z.extractall(pkg)
            os.chmod(os.path.join(pkg, name, "build.sh"), 0o755)
            subprocess.check_call([os.path.join(pkg, name, "build.sh")], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
            rebuilt = open(os.path.join(pkg, name, "build", name + ".cas"), "rb").read()
            if rebuilt != want:
                ok = False
                print("  a forráscsomag build.sh-ja eltérő .cas-t fordít")
            readme = open(os.path.join(pkg, name, "README.txt"), encoding="utf-8").read()
            cmd = shlex.split([l for l in readme.splitlines() if l.strip().startswith("./build.sh")][0])
            midi_copy = os.path.join(tmp, cmd[1])
            shutil.copy(os.path.join(pkg, name, cmd[1]), midi_copy)
            subprocess.check_call([os.path.join(REPO, "build.sh"), midi_copy] + cmd[2:], stdout=subprocess.DEVNULL)
            if open(os.path.join(REPO, "build", name + ".cas"), "rb").read() != want:
                ok = False
                print("  a README parancssora eltérő .cas-t ad: %s" % " ".join(cmd))
            if not ok:
                bad += 1
                first = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), None)
                print("ELTÉR: %s %s (python %d bájt, js %d bájt, első eltérés: %s)"
                      % (os.path.basename(mid), " ".join(args) or "(alap)", len(want), len(got), first))
            else:
                print("azonos: %s %s (%d bájt)" % (os.path.basename(mid), " ".join(args) or "(alap)", len(got)))
    # a cím (TVC ékezetes kódok) és az ékezet nélküli fájlnév
    sys.path.insert(0, REPO)
    import midi2tvc
    titles = ["Árvíztűrő tükörfúrógép", "ÁÉÍÓÖŐÚÜŰ áéíóöőúüű", "Õ û ä ß \"idéz\" €", "x" * 40,
              "Kacsák – „részlet” — ‘a’"]
    js = subprocess.check_output(["node", "-e", "const M=require(process.argv[1]+'/web/midi2tvc.js');"
                                  "for (const t of JSON.parse(process.argv[2])) console.log("
                                  "Buffer.from(M.titleBytes(t)).toString('hex')+' '+M.asciiName(t))",
                                  REPO, json.dumps(titles)]).decode().split("\n")
    for t, line in zip(titles, js):
        n += 1
        want = midi2tvc.tvc_title(t).hex() + " " + midi2tvc.ascii_name(t)
        if line != want:
            bad += 1
            print("ELTÉR: cím %r: python %s, js %s" % (t, want, line))
        else:
            print("azonos: cím %r -> %s" % (t, line))
    print("%d/%d azonos" % (n - bad, n))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
