# Tervek (ToDo)

Ötletek és tervezett bővítések. Az alapelv: **minden bővítés külön
választható opció**, és a kész `.cas`-ba csak a kiválasztott részek kódja és
adata kerül. Így ugyanabból a MIDI-ből a célnak megfelelő program készülhet:
kicsi és gyors, vagy teljes tudású, vagy egy adott hangkártyára szabott.

## 0. Moduláris felépítés (ez az alapja a többinek)

- [x] **Feltételes fordítás a lejátszókban.** A kapcsolható részek
  `IF FEAT_…` / `ENDIF` blokkok; a konverter a dalból dönti el, melyik kell,
  és a `build/features.inc`-be írja (`midi2tvc.py` / `midi2tvc.js`
  `features_inc`). Eddig: többszólamú: dobok (csúszás), impulzus, háromszög,
  fűrész, zaj, szinusz; egycsatornás: dobok, háttér-mód.
- [x] **A webes felület is így épít:** a `build.sh`-éval azonos sjasmplus
  (v1.24.0) WebAssemblyre fordítva fut a böngészőben (`web/sjasmplus/`,
  `web/assembler.js`, újraépítés: `tools/build_sjasmplus_wasm.sh`), így
  bármelyik kombináció bájtra azonos a `build.sh`-val; egy fordítás néhány ms.
  Ha nem tölthető be, az előre fordított, minden részt tartalmazó lejátszó a
  tartalék (`players.js`).
- [x] **A keverőtábla futás közben** a hullámtáblák utáni lapon (a `.cas`-ban
  nincs lapra igazító kitöltés: −207 bájt a DuckTales-nél).
- [x] **A web_parity** a böngészős fordítóval fordít (75/75 bájtra azonos), a
  forráscsomag a `build/features.inc`-et is tartalmazza.
- [ ] **Emulátoros teszt a kombinációkra** (most a meglévő esetek futnak, ezek
  több kombinációt lefednek; célzott esetek kellenek a többire).
- [ ] A felületen „Mi kerüljön a programba?” rész: most automatikus (a dal
  dönti el) és kiírja; kézi kapcsolók (pl. háttér-mód, kártyák) a további
  funkciókkal jönnek, mellettük a méret- és CPU-költség.
- [x] További kapcsolható részek: hullámforma-váltás (`FEAT_WAVECHG`, csak
  több hullámformánál), lecsengés (`FEAT_DECAY`), ismétlés (`FEAT_LOOP`). (A
  billentyűfigyelés marad: enélkül nem lehetne leállítani.)

## 1. Hangzás a beépített hanggal (`player_poly.asm`)

- [ ] **Mintavételezett dobok („digidrum”).** A zajból számolt dobok helyett
  rövid, valódi dobminták a DAC-on (lábdob, pergő, cin, taps). Egy szólamot
  egyszeri lejátszású mintatáblára állít. Opció: mintakészlet (beépített vagy
  saját WAV), mintavétel, a minták hossza. Ára: néhány KB adat. Felmérés: a
  kezelő lapon belül olvas, ezért a minta tickenként lapot váltana
  (F = 65536 / minta-per-tick); hangerőszintenként külön lap kellene, így egy
  0,3 s-os dob 8 szinten ~30 KB — csak 1–2 szinttel, néhány dobra fér bele.
- [x] **Hangmagasság-hajlítás és vibrato** (`--bend`, `FEAT_PITCH`): MIDI pitch
  bend (RPN 0 tartomány), vibrato a modulációs kerékről, a burkológörbék
  hangmagassága; új `B3+s lo hi` parancs. Emulátorban ellenőrizve. (Az
  egycsatornás lejátszóban még nincs.)
- [x] **0038h-s gyorsítás** (`--fast-irq`, `FEAT_IRQ0038`, kapcsolható): emulátorban
  mindhárom gépen ellenőrizve (hangmagasság, a 0038h–0088h terület visszaáll). Eredeti leírás: A mintakezelő a 0000h-tól másolva, hogy pontosan
  a 0038h-ra essen (a SID-lejátszó módszere: a terület mentése és
  visszaállítása). Mintánként −10 ciklus. A 0040h–006Fh a 0. kártyahely
  munkaterülete: mentés és visszaállítás kell, a dokumentáció szerint így
  biztonságos.
- [x] **Keskeny impulzus** (12,5%, `--wave pulse12`, `FEAT_WAVE_PULSE12`) új
  hullámformaként, a kártyákon is (vSID: PW 12,5%). A futás közben változó
  kitöltési tényező (PWM) a táblás keverésnél túl drága lenne; a vSID-en
  megoldható volna (a PW tickenként írható).
- [ ] **Hosszú zajtábla** 23 bites LFSR-ből és 16 hangerőszint a cinekhez és a
  pergőhöz (most 256 bájtos zaj, 8 szint).
- [x] **Tiszta keverés keverőtábla nélkül** (`--poly-mix fast`,
  `FEAT_FASTMIX`): a szólamtáblákba induláskor a kimenet kerül (0..5, << 2), a
  kezelő csak összead és a 06h többi bitjét hozzá-OR-olja: mintánként −11
  ciklus (a −18-ból 7 az `OR`). Emulátorban ellenőrizve (a DAC-szintek
  eloszlása egyezik az előnézettel).
- [ ] 4. szólam alacsonyabb mintavétellel, ha a CPU-idő engedi. Felmérés: a
  negyedik fázis már nem fér regiszterbe (IX, IY, HL' foglalt), memóriából
  kb. +80 ciklus mintánként: 8,5 kHz-en is ~90% CPU, a tickeknek alig marad.
  Csak a gyors keveréssel és ~7 kHz-es mintavétellel lenne értelme.
- [ ] **Háttér-mód a többszólamú lejátszóhoz** gépi kódú programok mellé
  (belépési pontok: indítás, leállítás, képkocka-szinkron), alacsony
  mintavétellel, hogy maradjon CPU-idő. Felmérés: a kezelő most az IX, IY és
  az árnyékregisztereket tartja fenn magának; háttérben ezeket menteni kell
  (+~60 ciklus), így 5 kHz körül ~50% CPU maradna a programnak. Kártyával
  (`--cards`) viszont könnyű: ott tickenként egyszer fut, a CPU szinte szabad
  — ez lehet az első lépés.

## Nagy dalok

- [x] **Tömörítés** (auTVC, `--compress`, a webes felületen „Tömörítés”): 42 155
  bájt fölött automatikus, kisebb dalnál kérhető.
- [x] **Az U3 RAM a többszólamú lejátszónak** (`FEAT_BIGMEM`): a dal a táblákkal
  kb. `FD00h`-ig; a BASIC verme (`BE00h–BFFFh`) helyén a dal kimarad, a
  lejátszó induláskor összehúzza. Emulátorban tesztelve (16 perces, 54 KB-os dal).
- [ ] Az egycsatornás lejátszó nagy dalhoz (most 42 155 bájt): a ROM-ot
  használja (megszakítás), ezért az U3 csak a dal adatainak lapozásával menne.

## 2. Konverter

- [x] **Kottaszerkesztő** a webes felületen: hangonként kihagyható, mi kerüljön
  át; látszik, melyik hangot nem játssza a TVC; csatornánkénti átültetés,
  szerkesztés, új dal.
- [x] **Szólam-elsőbbség hangonként** a kottaszerkesztőben („★ Mindenképp”,
  „Ha van hely”, kihagyás; a MIDI-ben CC 16), mindhárom módban.
- [ ] A dallamcsatorna automatikus felismerése; csatornánkénti alapértelmezett
  elsőbbség a Csatornák táblázatban.
- [ ] **Más forrásformátumok:** MOD / XM (tracker-zene), VGM (AY, SN76489,
  SAA1099, OPL2 hangchipes zene). A VGM különösen jól illik a hangkártyákhoz
  (lent).

## 3. Hangkártyák

Közös cél: **egy program, ami alapból a beépített hangon szól, de ha talál
hangkártyát, azt is használja** (indításkor felismeri), vagy a konverterben
kiválasztható, hogy csak egy adott kártyára készüljön. A kártyák
lejátszói is külön modulok (0. pont), így a `.cas`-ba csak a kiválasztott
kártyák kódja kerül.

Mindhárom kártyát emulálja az Ep128web (a `web/src/tvc_soundcards.cpp`,
`tvc256kpp.cpp`, `card/tvc-sid.c`), a gépbeállításoknál bővítőhelyre tehetők,
így a tesztek emulátorban futhatnak. A bővítőhely `n` (0..3) I/O portjai:
`10h + 10h·n` … `1Fh + 10h·n`.

- [x] **TVC Multichip Soundcard**: SN76489 (`--cards sn`), SAA1099
  (`--cards saa`) és OPL2 (`--cards opl`, 3 FM-csatorna, hangszín a
  hullámformából) meghajtó, emulátorban tesztelve, előnézettel. Még lehetne:
  az OPL2 9 csatornája és General MIDI-hangszínek, az SAA1099 6 csatornája.
  ([dikdom/TVC-Multichip-Soundcard](https://github.com/dikdom/TVC-Multichip-Soundcard)):
  SN76489, SAA1099 és YM3812 (OPL2) hangchip, akár egyszerre. A repó `doc/`
  könyvtárában van a kártya leírása és a chipek adatlapjai. Portok (a
  bővítőhely alapcímétől): `+0` SN76489, `+2`/`+3` SAA1099 adat/cím,
  `+4`/`+5` OPL2 regiszterválasztás/adat.
  - SN76489: 3 négyszög + zaj, MIDI → 3 szólam + dob.
  - SAA1099: 6 csatorna + 2 zaj, burkológörbe-generátor.
  - YM3812: 9 FM-csatorna (vagy 6 + 5 dob), General MIDI-hangszerek FM-hangszínekkel:
    ez adná a legjobb hangzást.
  - Licenc: a kártya repója CC BY-NC-SA 4.0, ez nem fér össze a GPL-lel, ezért
    a kódját nem vehetjük át, a meghajtót az adatlapokból és a kártya
    leírásából magunk írjuk meg.
- [x] **TVC 256k++ kártya, vSID** (`--cards sid`), emulátorban tesztelve. Eredeti terv:: a kártya egy C64 SID-et (MOS 6581/8580)
  emulál, 985 337 Hz-es SID-órajellel, 41 kHz-es mintavétellel, szűrők
  nélkül (TVC256K_Help). A SID-regiszterek ($00–$18) a kártya `E0h + n`
  regiszterei: a bővítőhely `+0` portjára a regiszter sorszáma, a `+1`-re az
  érték (az `+2`-n beállított lépéssel automatikusan továbblép, így egy
  `OTIR`-ral egyben írható). 3 szólam hullámformával (háromszög, fűrész, impulzus PWM-mel,
  zaj) és ADSR-rel: a burkológörbék (`--envelopes`) a SID ADSR-jére is
  leképezhetők.
- [x] **SN76489 meghajtó** (`--cards sn`, `chips.inc`): GameCard és Multichip,
  felismeréssel, emulátorban tesztelve, előnézettel.
- [x] **GameCard**: SN76489 hangchip a bővítőhely `+0` portján (ugyanaz, mint a
  Multichip kártyán, ugyanazon a porton), ezért a meghajtó közös; a `+2`/`+3`
  a 3. és 4. botkormány.
- [x] Felismerés indításkor: a kártyahelyek azonosítója (`5Ah` port, a
  0040h/0070h/00A0h/00D0h táblák) és a kártyák saját jelzései alapján.
- [x] Emulátoros teszt mindhárom kártyával; az előnézet szimulálja a chipeket. Eredeti terv: (az Ep128web harness kártyával is
  induljon, és a kártyák hangja is kerüljön a felvételbe); a webes előnézetbe
  a chipek hangja (SN76489, SAA1099, OPL2, SID) szimulálva vagy az Ep128web
  moduljaiból.
