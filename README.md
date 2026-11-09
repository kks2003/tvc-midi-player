# tvc-midi-player

MIDI-lejátszó Videoton TV-Computerre. A PC-n futó `midi2tvc.py` a `.mid`
fájlt tömör, képkockánkénti eseménylistává alakítja. A `player.asm` egy
megszakításos Z80-lejátszó. A `build.sh` a kettőből egy betölthető, magától
induló `.cas` fájlt készít.

```sh
./build.sh dal.mid                     # -> build/dal.cas
./build.sh dal.mid --mode mono --decay 3 --transpose -12
```

Kell hozzá: Python 3 (csak a szabványos könyvtár) és
[sjasmplus](https://github.com/z00m128/sjasmplus).

A `build/dal.cas` az [Ep128web](https://github.com/kks2003/Ep128web)
emulátorba húzva (TVC módban) magától betöltődik és elindul. Valódi gépre az
Ep128web „CAS → WAV…” funkciójával készíthető magnós hangfájl. Lejátszás
közben az **ESC** vagy a **SPACE** leállítja a zenét, és visszaadja a vezérlést
a BASIC-nek.

## A konverter (`midi2tvc.py`)

| Kapcsoló | Jelentés |
| --- | --- |
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

## A lejátszó (`player.asm`)

- A `.cas` egy kétsoros BASIC programot tartalmaz (`1 PRINT "cím"`,
  `2 X=USR(cím)`), amely mögött ott van a gépi kód és a dal. Mivel a
  programfejlécben be van állítva az autorun (FFh), a `LOAD` után magától
  elindul. A BASIC a záró `00` után kezdi a szimbólumtáblát, ezért a gépi kód
  előtt 64 bájt üresen marad.
- Időzítés: a ROM kurzor-IT-je, képkockánként egyszer (~49,7 Hz). A `0038h`
  RAM-beli belépési pontja (`PUSH AF / LD A,70h / OUT (02h),A / JP C412h`)
  első 3 bájtja a lejátszás idejére `JP irq` lesz. A saját kezelő a
  `59h` port b4 bitjét nézi, lejátszik egy ticket, majd az elmentett eredeti
  8 bájton keresztül lefut a ROM-kezelő is (az törli az IT-t a `07h`-val,
  olvassa a billentyűzetet, növeli a TIME-ot). Kilépéskor a 3 bájt visszakerül.
- A hangot a megszakítás írja. A főprogram `HALT`-tal vár, és az ESC/SPACE
  gombot közvetlenül a billentyűzetmátrixból olvassa (7. sor, `03h`/`58h`).
- Memória: a program `19EFh`-tól kezdődik, a lejátszó kódja kb. 750 bájt, utána jön a dal.
  A konverter 20 000 bájt fölött figyelmeztet (a 32k-s gépen kb. eddig biztos
  a hely).

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
- az IT-vektor visszaállítását.

Kell hozzá g++, gcc, sjasmplus, az Ep128web (az `ep128emu` almodullal), az
ep128emu ROM-csomagja, és írási jog a `/files` könyvtárba, mert az Ep128web
FILE: eszköze ott keresi a fájlokat.

## Tervek

- Több szólam DAC-módban (`05h` b4 = 0): szoftveres keverés pontosan időzített
  ciklusban, a `5Bh` porttal szinkronizált hang-IT-vel vagy IT nélkül.
- Időzítés a hang-IT-vel a képkocka-IT helyett, finomabb felbontással.
- Hangszínek: a hangerő gyors váltogatásával (PWM-szerű) burkológörbék.
