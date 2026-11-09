#!/bin/sh
# A SID-lejátszó: build/sidplay.cas (TVC 64k + TVC256k++ kártya)
#   ./build.sh
# A .sid fájlokat nem kell átalakítani: másold őket a kártya meghajtójára
# (pendrive, PSRAM vagy flash), töltsd be a sidplay.cas-t, és add meg a nevet.
set -e
cd "$(dirname "$0")"
command -v sjasmplus >/dev/null || { echo "hiányzik a sjasmplus (https://github.com/z00m128/sjasmplus)" >&2; exit 1; }
mkdir -p build
printf '%-32s' 'TVC SID lejatszo' > build/title.bin
[ -f cpu6502.asm ] || python3 tools/gen6502.py > cpu6502.asm
sjasmplus --nologo --msg=war --raw=build/sidplay.cas --sym=build/sidplay.sym sidplay.asm
echo "kész: build/sidplay.cas ($(wc -c < build/sidplay.cas) bájt)"
