#!/usr/bin/env python3
"""A webes konverter (web/midi2tvc.js) és a Python változat bájtra azonos
kimenetének ellenőrzése: ugyanazokkal a beállításokkal a build.sh és a
node is elkészíti a .cas fájlt.  Kell: node, sjasmplus.

    python3 test/web_parity.py [további.mid ...]
"""
import json, os, shutil, subprocess, sys, tempfile

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
    (["--mode", "poly", "--decay", "4", "--decay-floor", "5", "--poly-volume", "11", "--poly-knee", "8", "--loop"],
     {"mode": "poly", "decay": 4, "decayFloor": 5, "polyVolume": 11, "polyKnee": 8, "loop": True}),
    (["--mode", "poly", "--channels", "1,4,6,5,10"], {"mode": "poly", "channels": [1, 4, 6, 5, 10]}),
    (["--channels", "1,2,10", "--max-notes", "4"], {"channels": [1, 2, 10], "maxNotes": 4}),
]

RUNNER = r"""
const fs = require('fs');
const M = require(process.argv[2] + '/web/midi2tvc.js');
const P = require(process.argv[2] + '/web/players.js');
const job = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const r = M.convertMidi(new Uint8Array(fs.readFileSync(job.midi)), job.opts);
const cas = M.buildCas(r.mode === 'poly' ? P.poly : P.mono, r.song, job.title);
fs.writeFileSync(job.out, cas);
"""


def main():
    mids = sys.argv[1:] or [os.path.join(REPO, "examples", "teszt.mid")]
    duck = os.path.join(REPO, "examples", "ducktales", "ducktales.mid")
    if not sys.argv[1:] and os.path.exists(duck):
        mids.append(duck)
    subprocess.check_call([sys.executable, os.path.join(REPO, "tools", "export_players.py")],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tmp = tempfile.mkdtemp(prefix="tvcweb_")
    runner = os.path.join(tmp, "run.js")
    open(runner, "w").write(RUNNER)
    bad = n = 0
    for mid in mids:
        for args, opts in CASES:
            name = "par"
            src = os.path.join(tmp, name + ".mid")
            shutil.copy(mid, src)
            subprocess.check_call([os.path.join(REPO, "build.sh"), src] + args, stdout=subprocess.DEVNULL)
            want = open(os.path.join(REPO, "build", name + ".cas"), "rb").read()
            job = os.path.join(tmp, "job.json")
            out = os.path.join(tmp, "js.cas")
            json.dump({"midi": src, "opts": opts, "title": name, "out": out}, open(job, "w"))
            subprocess.check_call(["node", runner, REPO, job])
            got = open(out, "rb").read()
            n += 1
            ok = got == want
            if not ok:
                bad += 1
                first = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), None)
                print("ELTÉR: %s %s (python %d bájt, js %d bájt, első eltérés: %s)"
                      % (os.path.basename(mid), " ".join(args) or "(alap)", len(want), len(got), first))
            else:
                print("azonos: %s %s (%d bájt)" % (os.path.basename(mid), " ".join(args) or "(alap)", len(got)))
    print("%d/%d azonos" % (n - bad, n))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
