#!/usr/bin/env python3
# tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
# Copyright (C) 2026 kks2003 és a közreműködők
#
# Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
# Foundation által kiadott GNU General Public License 2. vagy (választás
# szerint) bármely későbbi változata szerint. A programot a hasznosság
# reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
#
"""A mellékelt burkológörbe-fájlok (envelopes/) a webes felületnek:
web/envelopes.js (globalThis.TVC_ENVELOPES = {midiplay: '...', tvc: '...'}).
A fájlok Varga István midiplay programjából valók (GPL 2 vagy későbbi)."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from midi2tvc import ENV_FILES  # noqa: E402

out = {}
for key, fn in ENV_FILES.items():
    with open(os.path.join(HERE, "..", "envelopes", fn), encoding="utf-8") as f:
        out[key] = f.read()
with open(os.path.join(HERE, "..", "web", "envelopes.js"), "w", encoding="utf-8") as f:
    f.write("// generálta: tools/export_envelopes.py; a burkológörbék a midiplay programból\n"
            "// valók (Varga István, GPL 2 vagy későbbi, https://github.com/istvan-v/midiplay)\n")
    f.write("globalThis.TVC_ENVELOPES = " + json.dumps(out, ensure_ascii=False) + ";\n")
print("web/envelopes.js:", ", ".join("%s (%d bájt)" % (k, len(v)) for k, v in out.items()))
