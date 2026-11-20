#!/bin/sh
# tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
# Copyright (C) 2026 kks2003 és a közreműködők
#
# Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
# Foundation által kiadott GNU General Public License 2. vagy (választás
# szerint) bármely későbbi változata szerint. A programot a hasznosság
# reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
#
# MIDI -> TVC .cas
#   ./build.sh dal.mid [midi2tvc.py kapcsolók...]
#   ./build.sh dal.mid --mode poly     (többszólamú lejátszó)
# Eredmény: build/<dal>.cas (betölthető az Ep128web emulátorba vagy
# a CAS -> WAV átalakítás után valódi gépbe), mellette .sym szimbólumfájl.
set -e
cd "$(dirname "$0")"
if [ $# -lt 1 ]; then
  echo "használat: $0 dal.mid [midi2tvc.py kapcsolók, pl. --mode mono --decay 3]" >&2
  exit 2
fi
mid=$1
shift
case "$mid" in /*) ;; *) mid="$OLDPWD/$mid" ;; esac
name=$(basename "$mid")
name=${name%.*}
# ékezet nélküli fájlnév (Árvíztűrő -> Arvizturo)
name=$(python3 -c 'import sys,unicodedata; t=unicodedata.normalize("NFKD",sys.argv[1]); print("".join(c for c in t if c.isascii() and (c.isalnum() or c in "-_")) or "dal")' "$name")
command -v sjasmplus >/dev/null || { echo "hiányzik a sjasmplus (https://github.com/z00m128/sjasmplus)" >&2; exit 1; }
# --mode poly: többszólamú lejátszó, különben az egycsatornás
player=player.asm
prev=
compress=auto
for a in "$@"; do
  case "$prev $a" in
    "--mode poly"|*" --mode=poly") player=player_poly.asm ;;
    "--compress "*) compress=$a ;;
    *" --compress="*) compress=${a#--compress=} ;;
  esac
  prev=$a
done
mkdir -p build
python3 midi2tvc.py "$mid" -o build/song.bin --title-out build/title.bin "$@"
sjasmplus --nologo --msg=war --raw="build/$name.cas" --sym="build/$name.sym" "$player"
size=$(wc -c < "build/$name.cas")
if [ "$player" = player_poly.asm ]; then
  python3 -c 'import sys, midi2tvc; sys.exit(midi2tvc.check_fit(sys.argv[1]))' "build/$name.sym" || exit 1
fi
# a TVC közvetlenül legfeljebb 42155 bájtos programot tölt be; fölötte (vagy
# --compress on esetén) önkicsomagoló .cas (auTVC, tools/autvc.js, node kell)
prog=$((size - 144))
if [ "$compress" = on ] || { [ "$compress" = auto ] && [ "$prog" -gt 42155 ]; }; then
  if command -v node >/dev/null; then
    node tools/autvc.js "build/$name.cas" "build/$name.cas"
    size=$(wc -c < "build/$name.cas")
  else
    echo "figyelem: a tömörítéshez node kell (https://nodejs.org); a .cas tömörítetlen" >&2
  fi
fi
if [ "$prog" -gt 42155 ] && [ "$compress" = off ]; then
  echo "figyelem: a program $prog bájt, tömörítés nélkül nem tölthető be (legfeljebb 42155)" >&2
fi
echo "kész: build/$name.cas ($size bájt, $player)"
