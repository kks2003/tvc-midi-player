#!/usr/bin/env python3
"""A két lejátszó gépi kódja a webes felülethez: web/players.js.

Mindkét lejátszót üres dallal fordítja le (sjasmplus). A .cas-ból a BASIC
programtól a dal elejéig tartó rész kerül ki ("code"), mert ez nem függ a
daltól; a böngésző a végére teszi a dalt, és elé a .cas fejléceket
(midi2tvc.js: buildCas).  A cím helyét két különböző címmel fordítva, a
kimenetek különbségéből keresi meg.  Az assembly forrásokat is beleteszi
(a weboldal forráscsomagjához).

    python3 tools/export_players.py      # a repó gyökeréből
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYERS = {"mono": "player.asm", "poly": "player_poly.asm"}


def assemble(asm, title):
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    open(os.path.join(ROOT, "build", "song.bin"), "wb").close()
    with open(os.path.join(ROOT, "build", "title.bin"), "wb") as f:
        f.write(title.ljust(32).encode("ascii"))
    out = os.path.join(ROOT, "build", "export.cas")
    subprocess.check_call(["sjasmplus", "--nologo", "--msg=war", "--raw=" + out, asm], cwd=ROOT)
    return open(out, "rb").read()


def main():
    result = {}
    for key, asm in PLAYERS.items():
        a = assemble(asm, "A" * 32)
        b = assemble(asm, "B" * 32)
        diff = [i for i in range(len(a)) if a[i] != b[i]]
        assert len(diff) == 32 and diff[-1] - diff[0] == 31, diff
        code = a[144:]                       # a BASIC programtól a dal elejéig
        prog_len = a[130] | (a[131] << 8)
        assert prog_len == len(code), (prog_len, len(code))
        result[key] = {"source": asm, "code": list(code), "title_offset": diff[0] - 144}
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
        print("%s: %d bájt (%s), cím: +%d" % (k, len(v["code"]), v["source"], v["title_offset"]))
    print("kész:", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    sys.exit(main())
