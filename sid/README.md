# SID-lejátszó TVC-re (TVC256k++ kártyával)

Eredeti C64 `.sid` (PSID) zenéket játszik le **konvertálás nélkül** a
Videoton TV-Computeren, a [TVC256k++](https://github.com/dikdom/tvc256kplusplus)
kártya vSID-jével. A `.sid` fájl bájtra változatlanul kerül a `.cas`-ba, a
fejlécet a TVC dolgozza fel, a zene 6502-es lejátszórutinját pedig egy
Z80-as 6502-emulátor futtatja. A SID-regiszterek írása a kártya
`$E0..$F8` regisztereibe megy, a hangot a kártya állítja elő.

```sh
./build.sh zene.sid          # -> build/zene.cas
```

Kell: Python 3, [sjasmplus](https://github.com/z00m128/sjasmplus). A gépen:
TVC 64k (a U3 RAM-ot is használja) és TVC256k++ kártya (az 1., 2., 3. vagy
0. slotban, a lejátszó megkeresi). Betöltés után kiírja a szerzőt, a
kiadást, a betöltési címet és a dal számát; **ESC** vagy **SPACE**: kilépés
a BASIC-be.

## Hogyan működik

- `sidplay.asm`: a kártya keresése, a PSID fejléc, a 6502 memóriája, a
  képkockánkénti (VSYNC, ~49,7 Hz) hívás.
- `cpu6502.asm`: a 6502-emulátor, a `tools/gen6502.py` generálja (minden
  dokumentált utasítás, decimális mód, és a lejátszókban előforduló nem
  dokumentáltak: LAX, SAX, DCP, ISC, SLO, RLA, SRE, RRA, ANC, ALR, SBX, NOP-ok).
- A 6502 64 KB-os címtere 256 bájtos lapokban, igény szerint foglalva
  (a U3, a program fölötti szabad RAM, majd a `.sid` helye). A
  `$D400-$D7FF` írása a SID-be megy, az OSC3 képkockánként visszaolvasva.
- A lejátszócím a fejlécből, vagy ha 0, az init által beállított
  IT-vektorból (`$0314` vagy `$FFFE`); a kernal IT-kilépési pontjai
  (`$EA31`, `$EA81`, `$FEBC`) kis csonkok.

## Korlátok (első változat)

- Csak PSID-szerű zenék; az RSID-k (CIA/VIC IT, kernal hívások) általában nem.
- A tempó mindig a TVC képkockája (~49,7 Hz, a PAL C64-é 50,1 Hz); a
  CIA-időzítésű és a többsebességes (2x-4x) zenék még nem.
- A digis (mintás, `$D418`-as) zenék és a 2SID/3SID nem.
- Ha a lejátszórutin egy képkockánál tovább fut, a zene lassul.

## Teszt

```sh
python3 test/make_test_sid.py teszt.sid && ./build.sh teszt.sid
```

Az emulátoros teszt a szülőkönyvtár `test/emu_harness.cpp`-jével megy
(`CARD=2 CARD_FILE=teszt.cas,build/teszt.cas`: a kártya a 2. slotban, a
fájl a kártya PSRAM-meghajtóján, `load "teszt"`).
