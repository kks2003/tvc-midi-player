#!/bin/sh
# MIDI -> TVC .cas
#   ./build.sh dal.mid [midi2tvc.py kapcsolók...]
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
command -v sjasmplus >/dev/null || { echo "hiányzik a sjasmplus (https://github.com/z00m128/sjasmplus)" >&2; exit 1; }
mkdir -p build
python3 midi2tvc.py "$mid" -o build/song.bin --title-out build/title.bin "$@"
sjasmplus --nologo --msg=war --raw="build/$name.cas" --sym="build/$name.sym" player.asm
size=$(wc -c < "build/$name.cas")
echo "kész: build/$name.cas ($size bájt)"
