#!/bin/sh
# SID -> TVC .cas (TVC 64k + TVC256k++ kártya)
#   ./build.sh zene.sid
# Az eredeti .sid fájl változatlanul kerül a .cas-ba, a lejátszó a TVC-n
# dolgozza fel. Eredmény: build/<zene>.cas, mellette .sym.
set -e
cd "$(dirname "$0")"
if [ $# -lt 1 ]; then
  echo "használat: $0 zene.sid" >&2
  exit 2
fi
sid=$1
case "$sid" in /*) ;; *) sid="$OLDPWD/$sid" ;; esac
name=$(basename "$sid")
name=${name%.*}
command -v sjasmplus >/dev/null || { echo "hiányzik a sjasmplus (https://github.com/z00m128/sjasmplus)" >&2; exit 1; }
mkdir -p build
cp "$sid" build/tune.sid
# a cím (BASIC PRINT sor): a PSID fejléc neve, 32 karakter
python3 - build/tune.sid build/title.bin <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
if d[:4] not in (b"PSID", b"RSID"):
    sys.exit("nem PSID/RSID fájl: " + sys.argv[1])
n = d[0x16:0x36].split(b"\0")[0]
t = bytes(c if 32 <= c < 127 and c != 34 else 63 for c in n)
open(sys.argv[2], "wb").write(t.ljust(32)[:32])
PY
[ -f cpu6502.asm ] || python3 tools/gen6502.py > cpu6502.asm
sjasmplus --nologo --msg=war --raw="build/$name.cas" --sym="build/$name.sym" sidplay.asm
size=$(wc -c < "build/$name.cas")
echo "kész: build/$name.cas ($size bájt)"
