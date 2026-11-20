#!/bin/sh
# tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
# Copyright (C) 2026 kks2003 és a közreműködők
#
# Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
# Foundation által kiadott GNU General Public License 2. vagy (választás
# szerint) bármely későbbi változata szerint. A programot a hasznosság
# reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
#
# A böngészős sjasmplus (web/sjasmplus/sjasmplus.js + .wasm) újraépítése:
# ugyanaz a v1.24.0, mint a build.sh-é, Emscriptennel WebAssemblyre fordítva.
# Kell: git, Emscripten (emcc / em++ a PATH-ban, pl. source emsdk_env.sh).
#
#     tools/build_sjasmplus_wasm.sh
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
git clone -q --depth 1 --branch v1.24.0 https://github.com/z00m128/sjasmplus.git "$tmp/sjasmplus"
( cd "$tmp/sjasmplus" && em++ -O2 -std=c++17 -w -DMAX_PATH=PATH_MAX -Isjasm -Icrc32c sjasm/*.cpp crc32c/*.cpp \
    -o "$tmp/sjasmplus.js" -sMODULARIZE=1 -sEXPORT_NAME=SjasmPlus -sENVIRONMENT=web,node \
    -sFORCE_FILESYSTEM=1 -sALLOW_MEMORY_GROWTH=1 -sEXPORTED_RUNTIME_METHODS=FS,callMain \
    -sINVOKE_RUN=0 -sEXIT_RUNTIME=0 )
cp "$tmp/sjasmplus.js" "$tmp/sjasmplus.wasm" web/sjasmplus/
cp "$tmp/sjasmplus/LICENSE.md" web/sjasmplus/LICENSE.md
rm -rf "$tmp"
echo "kész: web/sjasmplus/sjasmplus.js, sjasmplus.wasm"
