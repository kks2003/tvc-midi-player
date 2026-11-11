# SID-lejátszó TVC-re (TVC256k++ kártyával)

Eredeti C64 `.sid` (PSID) zenéket játszik le **átalakítás nélkül** a
Videoton TV-Computeren, a [TVC256k++](https://github.com/dikdom/tvc256kplusplus)
kártya vSID-jével. A lejátszót (`sidplay.cas`) egyszer kell betölteni, utána
a kártya aktuális meghajtójáról (pendrive, PSRAM, flash) közvetlenül a `.sid`
fájlokat olvassa. A fejlécet a TVC dolgozza fel, a zene 6502-es
lejátszórutinját pedig egy Z80-as 6502-emulátor futtatja. A SID-regiszterek
írása a kártya `$E0..$F8` regisztereibe megy, a hangot a kártya állítja elő.

A kész, lefordított lejátszó: **[`sidplay.cas`](sidplay.cas)** (ebben a
könyvtárban). Saját fordítás:

```sh
./build.sh                   # -> build/sidplay.cas
```

A gépen: a `sidplay.cas` és a `.sid` fájlok ugyanarra a meghajtóra
(könyvtárba), `LOAD "sidplay"`. A lejátszó kiírja a könyvtár `.sid` fájljait,
és bekéri a nevet:

- `commando` vagy `commando.sid`: a fejléc szerinti kezdő dal,
- `commando,3`: a 3. dal,
- üres sor (Enter): vissza a BASIC-be.

Lejátszás közben:

- **1-9**, **0**: az 1-9., illetve a 10. dal,
- **jobbra / balra nyíl**: a következő / előző dal,
- **ESC** vagy **SPACE**: vissza a fájllistához.

Kell: Python 3, [sjasmplus](https://github.com/z00m128/sjasmplus). A gépen:
TVC 64k (a U3 RAM-ot is használja) és TVC256k++ kártya (az 1., 2., 3. vagy
0. slotban, a lejátszó megkeresi). A zene indulásakor kiírja a nevét, a
szerzőt, a kiadást, a betöltési címet és a dal számát. A beolvasható fájl
mérete a HIMEM-ig tart (kb. 28 KB), a zene mellett a U3 16 KB-ja marad munkaterületnek.

## Hogyan működik

- `sidplay.asm`: a kártya keresése, a könyvtár listázása és a fájl
  beolvasása a kártya fájlparancsaival (`REG_USB_MSC_CMD`: OPENDIR, READDIR,
  FOPEN, FREAD, FCLOSE, a paraméterek a kártya IO RAM-jában, `$D900`/`$DA00`),
  a PSID fejléc, a 6502 memóriája, az időzítő-IT-nkénti hívás.
- `cpu6502.asm`: a 6502-emulátor, a `tools/gen6502.py` generálja (minden
  dokumentált utasítás, decimális mód, és a lejátszókban előforduló nem
  dokumentáltak: LAX, SAX, DCP, ISC, SLO, RLA, SRE, RRA, ANC, ALR, SBX, NOP-ok).
- A 6502 64 KB-os címtere 256 bájtos lapokban. A zene a beolvasási
  pufferben marad (lapra igazítva), a többi lap igény szerint foglalódik
  (a U3, majd a zene fölötti szabad RAM). A `$D400-$D7FF` írása a SID-be
  megy, az OSC3 hívásonként visszaolvasva.
- A lejátszócím a fejlécből, vagy ha 0, az init által beállított
  IT-vektorból (`$0314` vagy `$FFFE`); a kernal IT-kilépési pontjai
  (`$EA31`, `$EA81`, `$FEBC`) kis csonkok.

## Sebesség

Egy 6502-es utasítás átlagosan kb. 100 Z80-ciklus, így egy időzítő-IT alatt
kb. 600 utasítás fér el. Ami ezt adja:

- A kezelők címének alsó bájtja maga az opkód, a felső egy 256 bájtos
  táblából jön (`LD A,(DE)` / `INC DE` / `LD L,A` / `LD H,OPHI` /
  `LD H,(HL)` / `JP (HL)`). Ehhez a `build.sh` két menetben fordít: az első
  megméri a kezelőket, a második elpakolja őket.
- A 6502 N és Z jelzője a Z80 jelzőiben él (ahol a címszámítás elrontaná,
  ott `EX AF,AF'` védi), az átvitel az IXl-ben, A a B-ben, X a C-ben, Y az
  IXh-ban.
- A zene lapjai a Z80 memóriájában is folytonosak, ezért a PC sima `INC DE`.
- Lejátszás alatt saját, rövid IT-kezelő fut a ROM-é helyett (az hívásonként
  kb. 5000 ciklus), ez figyeli az időkorlátot is (végtelen ciklus ellen).
- Ha egy hívás kicsúszik az időből, a következő rövidebbek behozzák.

Emulátorban mérve (a SID-regiszterírások sorozata bájtra egyezik egy PC-s
6502-emulátoréval): Commando (250-340 utasítás/hívás) és Golden Axe 1. dal
(átlag 586, legfeljebb 668 utasítás/hívás) teljes tempóban megy. Ennél
nehezebb lejátszórutinnál a zene lelassul.

## Tempó

A lejátszót a TVC hanggenerátorának IT-je hívja (195312,5 / (4096 - n) Hz),
nem a képkocka-IT. A kettő közös állapotbitet használ, ezért lejátszás
közben a kurzor-IT tiltva van (CRTC R10 = 23h, ahogy a ROM magnórutinja is
csinálja), kilépéskor visszaáll.

- A fejléc `speed` bitje 0 (VBI): 50,12 Hz, a PAL C64 képkockája.
- A `speed` bit 1 (CIA): a CIA1 A időzítője szerint, 985248 / (T + 1) Hz
  (ha az init nem írta, a kernal 60 Hz-e). Ha a zene futás közben átírja az
  időzítőt, a tempó követi. 47,7 Hz alatt az IT kétszer (háromszor...)
  gyorsabb, és minden 2. (3. ...) hív.

Emulátorban mérve: VBI 50,12 Hz, CIA T = 8192 mellett 120 Hz (elvárt 120,3).

## Korlátok

- Csak PSID-szerű zenék; az RSID-k (CIA/VIC IT, kernal hívások) általában nem.
- A digis (mintás, `$D418`-as) zenék és a 2SID/3SID nem.
- Ha a lejátszórutin tartósan tovább fut egy időzítő-IT-nél (kb. 600
  utasítás fölött), a zene lassul.

## Teszt

```sh
python3 test/make_test_sid.py teszt.sid && ./build.sh
```

Az emulátoros teszt a szülőkönyvtár `test/emu_harness.cpp`-jével megy:
`CARD=2` (a kártya a 2. slotban), `CARD_FILE="sidplay.cas,build/sidplay.cas;teszt.sid,teszt.sid"`
(a fájlok a kártya PSRAM-meghajtóján), `TYPE_AT="4:teszt\n"` (a fájlnév
begépelése), a betöltendő program neve `sidplay`.
