# tvc-midi-player

MIDI-lejátszó Videoton TV-Computerre. A PC-n futó `midi2tvc.py` a `.mid`
fájlt tömör, képkockánkénti eseménylistává alakítja. A `build.sh` ebből és
a lejátszóból egy betölthető, magától induló `.cas` fájlt készít. Két
lejátszó van:

- **`player_poly.asm` (`--mode poly`): többszólamú.** 3 négyszög szólam
  és egy zajcsatorna, szoftveres keveréssel a DAC-ként használt
  hangerőregiszteren.
- **`player.asm` (`--mode arp`, alap, vagy `--mode mono`): egycsatornás.**
  A hardveres hangoszcillátort használja, akkordokat arpeggióval játszik.

```sh
./build.sh dal.mid --mode poly --decay 4    # -> build/dal.cas, többszólamú
./build.sh dal.mid                          # egycsatornás, arpeggio
./build.sh dal.mid --mode mono --decay 3 --transpose -12
```

Kell hozzá: Python 3 (csak a szabványos könyvtár) és
[sjasmplus](https://github.com/z00m128/sjasmplus).

A `build/dal.cas` az [Ep128web](https://github.com/kks2003/Ep128web)
emulátorba húzva (TVC módban) magától betöltődik és elindul. Valódi gépre az
Ep128web „CAS → WAV…” funkciójával készíthető magnós hangfájl. Lejátszás
közben az **ESC** vagy a **SPACE** leállítja a zenét, és visszaadja a vezérlést
a BASIC-nek.

## Webes felület (`web/`)

A `web/index.html` böngészőben végzi el ugyanezt, telepítés nélkül:

- ráhúzott MIDI-fájl, a csatornák listája (sávnév, hangszám, hangterjedelem)
  jelölőnégyzetekkel, a lejátszó módja és a beállítások,
- azonnali újraszámolás, összegzés (hossz, méret, memória a 32k-s gépen),
- **előnézet:** a `web/preview.js` a két lejátszót szimulálja (a poly motort
  mintára pontosan), zongoratekercs-nézettel, amelyen halványan a MIDI,
  színesen a TVC kimenete látszik,
- `.cas` letöltése, és **megnyitás az Ep128web-ben**: a program a linkben
  utazik (`#m=gép&f=…`), az emulátor betölti és elindítja,
- **forráscsomag** (`.zip`): a lejátszó assembly forrása (`player_poly.asm`
  vagy `player.asm`, `cas.inc`), a dal adatai (`build/song.bin`,
  `build/title.bin`), az eredeti MIDI, a kész `.cas`, egy `build.sh`, amely
  sjasmplus-szal bájtra ugyanezt a `.cas`-t fordítja újra, és egy README a
  beállításokkal egyenértékű `build.sh` / `midi2tvc.py` parancssorral.

A `web/midi2tvc.js` a Python konverter JavaScript-portja, a kimenete bájtra
azonos (`python3 test/web_parity.py` ellenőrzi 11 beállítással, a tesztdalon
és a DuckTales-en; a forráscsomag `build.sh`-ját és parancssorát is). A lejátszók gépi kódja a `web/players.js`-ben van; a
`player*.asm` módosítása után újra kell generálni:

```sh
python3 tools/export_players.py
```

Helyben a `web/index.html` közvetlenül megnyitható (`file://` is jó).

## A konverter (`midi2tvc.py`)

| Kapcsoló | Jelentés |
| --- | --- |
| `--mode poly` | többszólamú lejátszó (lásd lent); `--poly-volume` (alap 9) egy szólam legnagyobb hangereje, `--poly-knee` (alap 10) a keverőtábla térde |
| `--mode arp` (alap) | akkordok arpeggióval: legfeljebb `--max-notes` (2–4, alap 3) hang, a legmagasabbak |
| `--mode mono` | egyszólamú: `--prio high` (alap), `low` vagy `last` (a legutóbb leütött) |
| `--arp-bass` | arp módban a legmélyebb hang (basszus) mindig szól, mellette a legmagasabbak (pl. `--max-notes 2`: dallam + basszus) |
| `--arp-speed N` | arpeggio: N tickenként lép (alap 1, azaz ~50 Hz) |
| `--channels 1,2` | csak ezek a MIDI csatornák (alapból mind) |
| `--drums synth` (alap) | a 10. csatorna szintetizált dobként szól (lásd lent); `pitched`: dallamhangként, `off`: kimarad |
| `--transpose N`, `--tuning 440`, `--speed 1.0` | transzponálás (félhang), hangolás, tempószorzó |
| `--decay N`, `--decay-floor V` | lecsengés: N tickenként eggyel halkul, legfeljebb V-ig |
| `--curve`, `--min-volume`, `--max-volume` | MIDI erősség (velocity × CC7 × CC11) leképezése a 4 bites hangerőre |
| `--loop` | a dal végtelenítve szól |
| `--background` | egycsatornás lejátszó: háttérben szól, a BASIC közben fut (lásd lent) |
| `--title` | a betöltés után kiírt cím (alapból a fájlnév) |

A konverter kezeli a tempóváltásokat, a kitartó pedált (CC64), a CC7/CC11
hangerőt és az „all notes off” üzeneteket. A nagyon rövid hangok is legalább
egy tick hosszúak. A 47,7 Hz alatti hangok (MIDI 30 alatt) egy oktávval
feljebb szólnak.

### Dob

A 10. csatorna (GM dob) hangjai szintetizált dobokká alakulnak. Egy dobütés
1–6 tickre átveszi az egyetlen hangcsatornát. Közben a dallam állapota
tovább halad (arpeggio, lecsengés, új hangok), és a dob után a dallam éppen
aktuális hangja szól tovább.

- **Lábdob, tamok, kolomp, perem:** az oszcillátor hangja tickenként lefelé
  csúszik (a lábdob 160 → 110 → 80 → 60 Hz) és halkul; az elején egy rövid
  zajkattanással.
- **Pergő, cinek, crash, ride, taps:** zaj. A megszakításban a lejátszó a
  `05h` b4 = 0 állással DAC-ra kapcsolja a hangerőregisztert, és egy 16 bites
  LFSR-ből ~40 kHz-cel írja (tickenként legfeljebb ~10 ms, utána visszaáll
  az oszcillátor). A pergő zaj és hang keveréke.
- Ha egy tickre több dob esik, a fontosabb szól (lábdob > pergő > taps >
  crash > tamok > nyitott cin > ride > kolomp > perem > zárt cin). A dobütés
  erőssége gyengítésként (0–15) kerül az adatba.
- A dobkészlet a `midi2tvc.py` `DRUM_KIT` táblázatában van (tickenként: hang
  Hz-ben, hangerő, zaj hangereje és hossza), és a dallal együtt kerül a gépre,
  így a lejátszó újrafordítása nélkül hangolható. A GM hangok hozzárendelése:
  `GM_DRUMS`.

## Hardver (a [tvcdoc](https://github.com/kks2003/tvcdoc) alapján)

- 12 bites PITCH: alsó 8 bit a `04h`, felső 4 bit a `05h` b0–b3 bitjein.
  A frekvencia `f = 195312,5 / (4096 − PITCH)` Hz. A PITCH-táblát a konverter
  számolja (`round(4096 − 195312,5 / f)`), és a dallal együtt kerül a gépre.
- `05h` b4: **1 = az oszcillátor négyszögjele megy a hangerő-szabályzóra,
  0 = állandó „1” szint**, ekkor a `06h` amplitúdóregiszter 4 bites DAC-ként
  működik. A források itt ellentmondanak egymásnak. A `tvcrom.md` szövege és a
  ROM kódja (`FA95h`: `AND EFh`, „hangjel tiltás”) ezt mondja, az ep128emu
  `tvc64vm.cpp` is így emulálja, és a lenti emulátoros teszt is ezt igazolja.
  Valódi gépen még ki kell próbálni. A `05h` b5 a hang-IT-t engedélyezi
  (a lejátszó tiltja), a b6/b7 a magnómotorokat vezérli (ezeket megőrzi).
- Hangerő: `06h` b2–b5. A b0–b1 (videómód) és a b7 (nyomtató) változatlan
  marad. A lejátszó minden íráskor frissíti a ROM `0B12h` / `0B13h` tükrét is.

## A többszólamú lejátszó (`player_poly.asm`)

- A `05h` b4 = 0 állással a hangoszcillátor nem szól, a `06h`
  amplitúdóregiszter 4 bites DAC. A lejátszó megszakítás nélkül (DI), egy
  állandó, 271 ciklusos minta-hurokban kever, ~11,3 kHz-cel:
  - **3 négyszög szólam:** 16 bites fázisakkumulátor (HL, DE, IX). A
    fázisnövekmény és a hangerő önmódosító operandus, így a hurokban nincs
    memóriaolvasás.
  - **Zajcsatorna:** 16 bites Galois-LFSR (HL').
  - **Keverés:** a négy forrás összegét (0–60) egy 64 bájtos, 256 bájtra
    igazított keverőtábla képezi le 0–15-re. A tábla a dallal jön; a
    `--poly-knee` értékéig lineáris, fölötte lágyan telít.
- **Időzítés:** a hurok minden mintánál olvassa az `59h` port kurzor-IT
  bitjét (DI mellett is beáll). Képkockánként (49,76 Hz, a hardver időzít)
  lefut egy tick: törli a jelzést (`07h`), figyeli az ESC/SPACE gombot,
  feldolgozza az eseményeket, kezeli a lecsengést és a hangcsúszást, és
  frissíti az operandusokat. Tick közben a fázisok állnak. Ezt a konverter
  a fázisnövekmény-táblában kiegyenlíti (a tick átlagos idejét, ~1100
  ciklust, az emulátorban mértem), így a hangmagasság néhány centen belül
  pontos.
- **Szólamkiosztás:** minden tickben a legmagasabb hang (dallam), a
  legmélyebb (basszus), majd a következő legmagasabb kap szólamot. A
  folytatódó hangok a helyükön maradnak.
- **Dob:**
  - A pergő, a cinek, a crash, a ride és a taps a zajcsatornán szól,
    dobonként saját hangerővel, lecsengéssel és hosszal.
  - A lábdob, a tamok és a kolomp csúszó hangként szól egy szólamon: a
    lábdob kb. 147 → 45 Hz 5 tick alatt. Ilyenkor egy szabad szólamot, vagy
    a középső (nem dallam, nem basszus) hang szólamát veszi el.
  - A dobkészlet: `POLY_KIT` a `midi2tvc.py`-ban.
- **Méret:** a lejátszó a 256 bájtos igazítással és a keverőtáblával kb. 1 KB, az 58 s-os, 8 sávos DuckTales a
  dallal együtt kb. 4,9 KB.

## Az egycsatornás lejátszó (`player.asm`)

- A `.cas` egy kétsoros BASIC programot tartalmaz (`1 PRINT "cím"`,
  `2 X=USR(cím)`), amely mögött ott van a gépi kód és a dal. Mivel a
  programfejlécben be van állítva az autorun (FFh), a `LOAD` után magától
  elindul. A BASIC a záró `00` után kezdi a szimbólumtáblát, ezért a gépi kód
  előtt 64 bájt üresen marad.
- Időzítés: a ROM kurzor-IT-je, képkockánként egyszer (~49,7 Hz). A `0038h`
  RAM-beli belépési pontja `PUSH AF / LD A,70h / OUT (02h),A / JP C405h` (BASIC 2.2; az 1.2-es ROM-listában C412h); a
  lejátszó a `JP` célját (`003Eh`) írja át a saját kezelőjére. Így az a ROM
  lapozása (U0 U1 U2 SYS) után fut, akkor is, ha a megszakított program
  éppen a videó-RAM-ot lapozta be. A kezelő a `59h` port b4 bitjét nézi,
  lejátszik egy ticket, majd a ROM-kezelőre ugrik (az törli az IT-t a
  `07h`-val, olvassa a billentyűzetet, növeli a TIME-ot). Leálláskor az
  eredeti cím visszakerül.
- Memória: a program `19EFh`-tól kezdődik, a lejátszó kódja kb. 1,2 KB
  (ebből kb. 0,5 KB a háttér-mód betöltője), utána jön a dal, a végén a
  relokációs tábla (212 bájt). A konverter 20 000 bájt fölött figyelmeztet (a
  32k-s gépen kb. eddig biztos a hely).

### Előtér és háttér

Belépési pontok (BASIC: `X=USR(cím)`):

| Cím | Mit csinál |
| --- | --- |
| `6759` | a dal fejléce szerint (`--background`) előtérben vagy háttérben; az autorun ezt hívja |
| `6762` | előtérben: a dal végéig vagy ESC/SPACE-ig, utána visszatér |
| `6765` | háttérben: azonnal visszatér, a zene szól |

- **Előtérben** a főprogram `HALT`-tal vár, és az ESC/SPACE gombot
  közvetlenül a billentyűzetmátrixból olvassa (7. sor, `03h`/`58h`).
- **Háttérben:**
  - A lejátszó a megszakításos részét és a dalt a memória tetejére
    másolja. Ehhez a `HIMEM`-et (`0B19h`) lejjebb teszi, ugyanúgy, mint a
    ROM `HI-MEM-SET` rutinja (`C4B7h`). A BASIC a vermét és a változóit a
    `HIMEM` alá teszi, így a zene alatt új programot lehet begépelni,
    futtatni vagy betölteni.
  - A másolatot a relokációs tábla szerint javítja (sjasmplus
    `RELOCATE_START`/`RELOCATE_TABLE`). A ROM USRTAB-jába beírja:
    **`EXT 0`** leállítja, **`EXT 1`** elölről indítja.
  - A futó BASIC verme miatt 512 bájtot üresen hagy a blokk fölött.
  - Ha újra elindítod, és az új dal elfér a régi helyén, oda kerül; ha
    nincs elég hely (32k-s gép, hosszú dal), előtérben szól.
  - A program közben ne használja a `SOUND`-ot, és ne tiltsa le a
    megszakításokat.

Például egy `--background` kapcsolóval készült `zene.cas`-szal:

```basic
LOAD "zene"            a betöltés után a zene magától indul a háttérben
NEW                    a zene szól tovább, a BASIC területe üres
10 PRINT "SZOL A ZENE"
20 FOR I=1 TO 3000 : NEXT I
30 EXT 0
RUN                    a program fut, a zene szól, a 30. sor leállítja
EXT 1                  elölről indítja
```

A `6762`/`6765` belépési pont csak addig hívható, amíg a betöltött program
(a két BASIC sor és mögötte a lejátszó) érintetlen, tehát közvetlenül a
`LOAD` után. Új sorok begépelése vagy `NEW` után már csak az `EXT 0` /
`EXT 1` használható: ezek a lefoglalt blokkba mutatnak.

A lejátszó által elvett idő (emulátorban, a valódi ROM-mal mérve, a 58 s-os
DuckTales egycsatornás változatain, képkockánként 62 802 ciklusból):

| | Átlag | Legrosszabb képkocka |
| --- | --- | --- |
| a lejátszó | 2 400–2 600 ciklus (3,8–4,2%) | ~24 100 ciklus (38%, a dobok zajlökete) |
| a ROM megszakításkezelője (zene nélkül is fut) | 4 935 ciklus (7,9%) | 5 398 ciklus (8,6%) |

A többszólamú lejátszó a teljes CPU-t használja (DI mellett kever), mellette
más nem futhat.

Az adatformátum leírása a `player.asm` elején található.

## Tesztelés az emulátorban

A `test/emu_test.py` az Ep128web emulátormagját (ep128emu, változatlan C++
forrás) natívan lefordítja, és a valódi TVC ROM-mal futtatja a lejátszót:

```sh
python3 test/emu_test.py --ep128web ../Ep128web --roms ep128emu_roms-2.0.11.bin
```

Lépései: tesztdal (`test/make_test_mid.py`: C-dúr skála, tempóváltás, akkordok
basszussal és dobritmus), majd `build.sh`. Ezután a `.cas` a FILE: eszközre
kerül (`/files`), a TVC 64k+ / BASIC 2.2 bootol, és a teszt beírja:
`load "teszt"`. Közben rögzíti a hangkimenetet (WAV) és a `04h`–`06h`
portírásokat. Végül ellenőrzi:

- a skála hangjainak sorrendjét és a PITCH-értékeket,
- a hangkezdetek időzítését a tempótérkép szerint (±1 tick),
- az arpeggiót (tickenként váltakozó hangok),
- a dobot: a lábdob hangját, a zajlöketeket (DAC-mód) és a zajt a
  felvételben, valamint azt, hogy a dallam a dob közben is halad,
- a felvett hang frekvenciáját (C4: 261,45 Hz, a számított érték 261,46 Hz),
- a dal végi és az ESC utáni csendet,
- az IT-belépő visszaállítását,
- a többszólamú motort: a hangmagasságot (±5 cent), az időzítést, hogy egy
  akkord három hangja egyszerre szól (spektrumból), a csendet a dal végén és
  az ESC-et,
- a háttér-módot: a zene alatt a BASIC végrehajt egy `POKE`-ot, a zene
  végig szól, az `EXT 0` leállítja, az `EXT 1` újraindítja, a `HIMEM`
  lejjebb kerül, és az EXT-címek a lefoglalt blokkba mutatnak.

Kell hozzá g++, gcc, sjasmplus, az Ep128web (az `ep128emu` almodullal), az
ep128emu ROM-csomagja, és írási jog a `/files` könyvtárba, mert az Ep128web
FILE: eszköze ott keresi a fájlokat.

## Tervek

- Poly: 4. szólam vagy kitöltési tényező (pulzusszélesség) szólamonként;
  csatornánkénti szólam-hozzárendelés (`--voice 1=melody` stb.).
- Poly: a tick munkájának szétosztása, hogy a fázisok ne álljanak meg.
