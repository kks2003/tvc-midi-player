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
# A 6502-emulátor két menetben: az 1. menet méri a kezelők méretét, a 2. úgy
# pakolja el őket, hogy a címük alsó bájtja az opkód legyen.
python3 tools/gen6502.py > cpu6502.asm
sjasmplus --nologo --msg=war --raw=build/pass1.cas --sym=build/pass1.sym sidplay.asm
python3 tools/gen6502.py --sym build/pass1.sym > cpu6502.asm
sjasmplus --nologo --msg=war --raw=build/sidplay.cas --sym=build/sidplay.sym sidplay.asm
echo "kész: build/sidplay.cas ($(wc -c < build/sidplay.cas) bájt)"
