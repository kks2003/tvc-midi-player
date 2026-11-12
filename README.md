# tvc-midi-player

MIDI-lejátszó Videoton TV-Computerre. A PC-n futó `midi2tvc.py` a `.mid`
fájlt tömör, képkockánkénti eseménylistává alakítja. A `build.sh` ebből és
a lejátszóból egy betölthető, magától induló `.cas` fájlt készít. Két
lejátszó van:

- **`player_poly.asm` (`--mode poly`): többszólamú.** 3 szólam választható
  hullámformával (négyszög, impulzus, háromszög, fűrész, szinusz, zaj a dobokhoz),
  szoftveres keveréssel a DAC-ként használt hangerőregiszteren.
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
| `--mode poly` | többszólamú lejátszó (lásd lent); `--poly-volume` (alap 9) egy szólam legnagyobb hangereje |
| `--poly-mix clean` (alap) / `soft` | poly: keverés; `clean`: a három szólam összege arányosan 0–15-re, nem vezérel túl; `soft`: hangosabb, a `--poly-knee` (alap 10) fölött lágyan telít |
| `--wave`, `--channel-wave` | poly: hullámforma (`square`, `pulse`, `triangle`, `saw`, `sine`), csatornánként pl. `1=saw,6=sine` |
| `--poly-div N` | poly: a mintaóra osztója, mintavétel = 195312,5 / N Hz (alap 19; nagyobb osztó: több szabad CPU, tompább hang) |
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

A 10. csatorna (GM dob) hangjai szintetizált dobokká alakulnak:

| Dob | GM hangjegyek | Egycsatornás lejátszó | Többszólamú lejátszó |
| --- | --- | --- | --- |
| lábdob | 35, 36 | csúszó hang 160 → 60 Hz, zajkattanás | csúszó négyszög 147 → 45 Hz |
| pergő | 38, 40 | hang + zaj | zaj |
| perem (rimshot) | 37 | magas hang + zaj | rövid zaj |
| taps | 39 | zaj, háromszor | zaj |
| zárt cin, pedál cin | 42, 44 | rövid zaj | rövid zaj |
| nyitott cin, csörgő | 46, 54 | hosszabb, halkuló zaj | hosszabb, halkuló zaj |
| crash, kínai, splash | 49, 52, 55, 57 | hosszú zaj | hosszú zaj |
| ride | 51, 53, 59 | halk zaj | halk zaj |
| mély tam | 41, 43 | csúszó hang 190 → 95 Hz | csúszó négyszög |
| közép tam | 45, 47 | csúszó hang 260 → 140 Hz | csúszó négyszög |
| magas tam | 48, 50 | csúszó hang 350 → 190 Hz | csúszó négyszög |
| kolomp | 56 | 800 Hz-es hang | 784 Hz-es négyszög |
| minden más 27–87 között (pl. bongó, konga, triangulum) | | zárt cin | zárt cin |

A 27 alatti és 87 fölötti hangok kimaradnak. Ha egy tickre több dob esik,
a fontosabb szól (lábdob > pergő > taps > crash > tamok > nyitott cin >
ride > kolomp > perem > zárt cin). A dobütés erőssége halkítja a dobot.

- **Egycsatornás lejátszó:** egy dobütés 1–6 tickre átveszi az egyetlen
  hangcsatornát. Közben a dallam állapota tovább halad (arpeggio, lecsengés,
  új hangok), és a dob után a dallam éppen aktuális hangja szól tovább. A
  zajhoz a lejátszó a megszakításban a `05h` b4 = 0 állással DAC-ra
  kapcsolja a hangerőregisztert, és egy 16 bites LFSR-ből ~40 kHz-cel írja
  (tickenként legfeljebb ~10 ms). A dobkészlet: `DRUM_KIT`.
- **Többszólamú lejátszó:** a dob a három szólam egyikét kapja néhány
  tickre (szabadot, vagy a középső hangét), a zaj hullámtáblával. A
  dobkészlet: `POLY_KIT`.
- Mindkét dobkészlet a dallal együtt kerül a gépre, így a lejátszó
  újrafordítása nélkül hangolható. A GM hangok hozzárendelése: `GM_DRUMS`.

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
  amplitúdóregiszter 4 bites DAC. A hangszámláló közben **mintaóraként**
  jár: a hang-IT (`05h` b5) minden mintánál megszakítást kér,
  `195312,5 / osztó` Hz-cel (`--poly-div`, alap 19 = 10 280 Hz).
- **A mintamegszakítás** 253 ciklus (a belépéssel együtt, emulátorban
  mérve):
  - **3 szólam:** 16 bites fázisakkumulátor (IX, IY, HL'), a fázisnövekmény
    önmódosító operandus.
  - **Hullámtáblák:** szólamonként egy 256 bájtos tábla, a fázis felső
    bájtjával címezve. A tábla a hullámformát és a hangerőt is tartalmazza
    (hullámforma × 8 hangerőszint). A táblákat a lejátszó induláskor
    számolja ki a program utáni szabad memóriába, csak a dalban használt
    hullámformákhoz (hullámformánként 2 KB).
  - **Keverés:** a három érték összegét (0–45) egy 64 bájtos keverőtábla
    képezi le 0–15-re. A tábla a dallal jön. Alapból (`--poly-mix clean`) a
    három szólam teljes összegét (3 × a szólam legnagyobb hangereje)
    arányosan képezi le, így nem vezérel túl: a DuckTales-ben csak a minták
    0,4%-a telít, a dobok csúcsain. A `soft` keverés kb. 1,6 dB-lel
    hangosabb, de a térd fölött összenyom: a DuckTales mintáinak 38%-a
    esik oda, és szinuszos akkordon az akkordon kívüli energia 2,4% helyett
    6,3% (hallható torzítás).
- **Hullámformák:** négyszög, 25%-os impulzus, háromszög, fűrész, szinusz
  (`--wave`, csatornánként `--channel-wave 1=saw,6=sine`), és zaj a dobokhoz.
  A szinuszt a lejátszó egy 64 bájtos negyed-szinusz táblából tükrözéssel
  számolja; a felvételben a 3. felhang a négyszögnél 0,36, szinusznál 0,02.
- **Regiszterek:** a lejátszó az IX, IY és az árnyékregisztereket használja,
  ezeket belépéskor elmenti, kilépéskor visszaállítja (a BASIC a sajátjainak
  használja őket; USR-ből csak HL, BC, DE, AF, DE', AF' szabad).
- **Tick:** a megszakítás számolja a mintákat, és ~50 Hz-enként a zenét is
  feldolgozza (ESC/SPACE, események, lecsengés, hangcsúszás). Ez
  engedélyezett megszakítással fut, tehát közben a minták tovább mennek: a
  hang nem áll meg, a tempó és a hangmagasság a hardver órájából jön (a
  teszt 1 centen belül méri).
- **Szólamkiosztás:** minden tickben a legmagasabb hang (dallam), a
  legmélyebb (basszus), majd a következő legmagasabb kap szólamot. A
  folytatódó hangok a helyükön maradnak.
- **Dob:** minden dob egy szólamot kap néhány tickre (szabadot, vagy a
  középső, nem dallam és nem basszus hangét). A lábdob, a tamok és a kolomp
  lefelé csúszó négyszög, a pergő, a cinek, a crash és a taps a zaj
  hullámtáblán szól. A dobkészlet: `POLY_KIT` a `midi2tvc.py`-ban.
- **CPU:** a keverés az alap mintavételnél a gép idejének 83%-át viszi el,
  osztó 23-nál (8 492 Hz) 69%-át, 28-nál (6 975 Hz) 56%-át. A maradék a
  főprogramé: a `.cas`-ban ez csak a dal végét várja, de egy gépi kódú
  program ennyi idővel futhat mellette. Lejátszás közben a ROM
  megszakításkezelője nem fut (a `0038h`-n a mintamegszakítás van, a
  kurzor-IT tiltva), a végén minden visszaáll.
- **Méret:** a lejátszó kb. 1,1 KB, az 58 s-os, 8 sávos DuckTales a dallal
  együtt 5,4 KB, futás közben ehhez jön 4,3 KB hullámtábla.

Az alapötlet (a hang-IT mint mintaóra, hullámtáblák, a zene feldolgozása a
megszakításból, engedélyezett megszakítással) Szalontai Béla „Többcsatornás
hanggeneráló programcsomag”-jából való (tvcdoc:
`sources/3 csatornás asm lejátszó`, MIT licenc). Az első változat
megszakítás nélküli, számolt idejű hurokban kevert: ott tick közben megállt
a hang, a hangmagasságot kalibrálni kellett, és a teljes CPU-t elvitte.

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

A többszólamú lejátszó a CPU 56–93%-át használja (a mintavételtől függően),
és a ROM megszakításkezelője közben nem fut, ezért BASIC nem futhat
mellette; gépi kódú program a maradék időben igen.

Az adatformátum leírása a `player.asm` elején található.

## Tesztelés az emulátorban

A `test/emu_test.py` az Ep128web emulátormagját (ep128emu, változatlan C++
forrás) natívan lefordítja, és a valódi TVC ROM-mal futtatja a lejátszót:

```sh
python3 test/emu_test.py --ep128web ../Ep128web --roms ep128emu_roms-2.0.11.bin
```

Lépései: tesztdal (`test/make_test_mid.py`: C-dúr skála, tempóváltás, akkordok
basszussal és dobritmus), majd `build.sh`. Ezután a `.cas` a FILE: eszközre
kerül (`/files`), a TVC 64k / BASIC 1.2 bootol (`--machine`, mint az
Ep128web alapgépe), és a teszt beírja:
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
- a többszólamú motort: a hangmagasságot (±5 cent; a mért eltérés 0,4 cent), az időzítést, hogy egy
  akkord három hangja egyszerre szól (spektrumból), a csendet a dal végén és
  az ESC-et,
- a háttér-módot: a zene alatt a BASIC végrehajt egy `POKE`-ot, a zene
  végig szól, az `EXT 0` leállítja, az `EXT 1` újraindítja, a `HIMEM`
  lejjebb kerül, és az EXT-címek a lefoglalt blokkba mutatnak,
- a képernyőn, hogy a lejátszás után a BASIC `ok`-kal folytatja, nem
  hibaüzenettel,
- a másik két gépen (TVC 64k+ / BASIC 2.2 és TVC 32k / BASIC 1.2) mindkét
  lejátszót (a polyt szinusszal), és a 32k-s gépen a háttér-módot.

Kell hozzá g++, gcc, sjasmplus, az Ep128web (az `ep128emu` almodullal), az
ep128emu ROM-csomagja, és írási jog a `/files` könyvtárba, mert az Ep128web
FILE: eszköze ott keresi a fájlokat.

## Tervek

- Poly: 4. szólam; csatornánkénti szólam-hozzárendelés (`--voice 1=melody`).
- Poly: háttér-mód gépi kódú programok mellé (belépési pontok: indítás,
  leállítás, képkocka-szinkron), a tvcdoc 2 csatornás, CRTC-szinkronos
  lejátszójának mintájára.
