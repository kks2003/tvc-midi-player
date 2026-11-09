# SID-lejátszó TVC-re (TVC256k++ kártyával)

Eredeti C64 `.sid` (PSID) zenéket játszik le **átalakítás nélkül** a
Videoton TV-Computeren, a [TVC256k++](https://github.com/dikdom/tvc256kplusplus)
kártya vSID-jével. A lejátszót (`sidplay.cas`) egyszer kell betölteni, utána
a kártya aktuális meghajtójáról (pendrive, PSRAM, flash) közvetlenül a `.sid`
fájlokat olvassa. A fejlécet a TVC dolgozza fel, a zene 6502-es
lejátszórutinját pedig egy Z80-as 6502-emulátor futtatja. A SID-regiszterek
írása a kártya `$E0..$F8` regisztereibe megy, a hangot a kártya állítja elő.

```sh
./build.sh                   # -> build/sidplay.cas
```

A gépen: a `sidplay.cas` és a `.sid` fájlok ugyanarra a meghajtóra
(könyvtárba), `LOAD "sidplay"`. A lejátszó kiírja a könyvtár `.sid` fájljait,
és bekéri a nevet:

- `commando` vagy `commando.sid`: a fejléc szerinti kezdő dal,
- `commando,3`: a 3. dal,
- üres sor (Enter): vissza a BASIC-be.

Lejátszás közben **ESC** vagy **SPACE**: vissza a fájllistához.

Kell: Python 3, [sjasmplus](https://github.com/z00m128/sjasmplus). A gépen:
TVC 64k (a U3 RAM-ot is használja) és TVC256k++ kártya (az 1., 2., 3. vagy
0. slotban, a lejátszó megkeresi). A zene indulásakor kiírja a nevét, a
szerzőt, a kiadást, a betöltési címet és a dal számát. A beolvasható fájl
mérete a HIMEM-ig tart (kb. 40 KB).

## Hogyan működik

- `sidplay.asm`: a kártya keresése, a könyvtár listázása és a fájl
  beolvasása a kártya fájlparancsaival (`REG_USB_MSC_CMD`: OPENDIR, READDIR,
  FOPEN, FREAD, FCLOSE, a paraméterek a kártya IO RAM-jában, `$D900`/`$DA00`),
  a PSID fejléc, a 6502 memóriája, a képkockánkénti (VSYNC, ~49,7 Hz) hívás.
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
python3 test/make_test_sid.py teszt.sid && ./build.sh
```

Az emulátoros teszt a szülőkönyvtár `test/emu_harness.cpp`-jével megy:
`CARD=2` (a kártya a 2. slotban), `CARD_FILE="sidplay.cas,build/sidplay.cas;teszt.sid,teszt.sid"`
(a fájlok a kártya PSRAM-meghajtóján), `TYPE_AT="4:teszt\n"` (a fájlnév
begépelése), a betöltendő program neve `sidplay`.
