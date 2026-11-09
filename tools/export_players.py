#!/usr/bin/env python3
"""A két lejátszó gépi kódja a webes felülethez: web/players.js.

Mindkét lejátszót üres dallal fordítja le (sjasmplus). A .cas-ból a BASIC
programtól a dal elejéig tartó rész ("code") és a dal mögötti rész
("suffix": az egycsatornás lejátszó relokációs táblája) kerül ki, mert ezek
nem függnek a daltól; a böngésző közéjük teszi a dalt, a "code"-ba beírja a
címet és a dal hosszát (song_len), elé pedig a .cas fejléceket
(midi2tvc.js: buildCas).  A cím helyét két különböző címmel fordítva, a
kimenetek különbségéből keresi meg.  Az assembly forrásokat is beleteszi
(a weboldal forráscsomagjához).

    python3 tools/export_players.py      # a repó gyökeréből
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYERS = {"mono": "player.asm", "poly": "player_poly.asm"}


def assemble(asm, title, song=b""):
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    with open(os.path.join(ROOT, "build", "song.bin"), "wb") as f:
        f.write(song)
    with open(os.path.join(ROOT, "build", "title.bin"), "wb") as f:
        f.write(title.ljust(32).encode("ascii"))
    out = os.path.join(ROOT, "build", "export.cas")
    sym = os.path.join(ROOT, "build", "export.sym")
    subprocess.check_call(["sjasmplus", "--nologo", "--msg=err", "--raw=" + out, "--sym=" + sym, asm], cwd=ROOT)
    syms = {}
    for line in open(sym):
        if ": EQU " in line:
            k, v = line.split(": EQU ")
            syms[k.strip()] = int(v, 16)
    return open(out, "rb").read(), syms


def main():
    result = {}
    for key, asm in PLAYERS.items():
        a, syms = assemble(asm, "A" * 32)
        b, _ = assemble(asm, "B" * 32)
        diff = [i for i in range(len(a)) if a[i] != b[i]]
        assert len(diff) == 32 and diff[-1] - diff[0] == 31, diff
        prog = a[144:]                       # a BASIC programtól a végéig
        prog_len = a[130] | (a[131] << 8)
        assert prog_len == len(prog), (prog_len, len(prog))
        cut = syms["song"] - 0x19EF          # a dal helye a programban
        entry = {"source": asm, "code": list(prog[:cut]), "suffix": list(prog[cut:]),
                 "title_offset": diff[0] - 144,
                 "song_len_offset": syms["song_len"] - 0x19EF if "song_len" in syms else None}
        # próba: egy 3 bájtos dallal a .cas = kód (javítva) + dal + suffix
        test = bytes((1, 2, 3))
        c, _ = assemble(asm, "A" * 32, test)
        code = bytearray(entry["code"])
        if entry["song_len_offset"] is not None:
            code[entry["song_len_offset"]] = len(test)
        assert c[144:] == bytes(code) + test + bytes(entry["suffix"]), asm + ": a .cas összerakása nem egyezik"
        result[key] = entry
    # a forráscsomaghoz (a weboldal "Forrás letöltése" gombja)
    result["sources"] = {name: open(os.path.join(ROOT, name), encoding="utf-8").read()
                         for name in ("player.asm", "player_poly.asm", "cas.inc")}
    out = os.path.join(ROOT, "web", "players.js")
    with open(out, "w") as f:
        f.write("// generálta: tools/export_players.py (ne szerkeszd kézzel)\n")
        f.write("// a lejátszók gépi kódja a BASIC programtól a dal elejéig\n")
        f.write("globalThis.TVC_PLAYERS = " + json.dumps(result, separators=(",", ":"), ensure_ascii=False) + ";\n")
        f.write("if (typeof module !== 'undefined') module.exports = globalThis.TVC_PLAYERS;\n")
    for k, v in result.items():
        if k == "sources":
            continue
        print("%s: %d + %d bájt (%s), cím: +%d, dalhossz: %s" % (k, len(v["code"]), len(v["suffix"]),
              v["source"], v["title_offset"], v["song_len_offset"]))
    print("kész:", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    sys.exit(main())
