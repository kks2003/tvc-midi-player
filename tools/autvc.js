#!/usr/bin/env node
// tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
// Copyright (C) 2026 kks2003 és a közreműködők
//
// Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
// Foundation által kiadott GNU General Public License 2. vagy (választás
// szerint) bármely későbbi változata szerint. A programot a hasznosság
// reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
//
// Önkicsomagoló .cas készítése (auTVC, web/autvc-core.js):
//   node tools/autvc.js be.cas ki.cas
// A betöltés után a program a teljes 64 KB RAM-ba kicsomagolja magát, majd a
// BASIC RUN-nal indul (ugyanúgy, mint a tömörítetlen .cas). A sorszám fix (1),
// hogy a kimenet a webes felületével bájtra azonos legyen.
'use strict';
const fs = require('fs');
const path = require('path');
const core = require(path.join(__dirname, '..', 'web', 'autvc-core.js'));

const [src, dst] = process.argv.slice(2);
if (!src || !dst) {
  console.error('használat: node tools/autvc.js be.cas ki.cas');
  process.exit(2);
}
const input = new Uint8Array(fs.readFileSync(src));
const r = core.build({ input, autorun: true, lineNumber: 1 });
fs.writeFileSync(dst, r.bytes);
console.log('tömörítve (auTVC): ' + input.length + ' -> ' + r.bytes.length + ' bájt');
for (const w of r.warnings) console.log('figyelem: ' + w);
