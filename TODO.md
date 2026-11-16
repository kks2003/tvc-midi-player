# Tervek (ToDo)

Ötletek és tervezett bővítések. Az alapelv: **minden bővítés külön
választható opció**, és a kész `.cas`-ba csak a kiválasztott részek kódja és
adata kerül. Így ugyanabból a MIDI-ből a célnak megfelelő program készülhet:
kicsi és gyors, vagy teljes tudású, vagy egy adott hangkártyára szabott.

## 0. Moduláris felépítés (ez az alapja a többinek)

- [ ] **Feltételes fordítás a lejátszókban.** Minden funkció külön blokk
  (`IF FEAT_DIGIDRUM` … `ENDIF` az sjasmplus-ban). A konverter a beállításokból
  dönti el, mely blokkok kellenek, és a dal fejlécében jelzi őket.
- [ ] **A webes felület is így építsen.** A böngésző nem fordít assemblyt,
  ezért két lehetőség van:
  - a `tools/export_players.py` előre lefordítja a lejátszót minden
    funkciókombinációra (5–6 kapcsolónál néhány tucat változat, egyenként
    ~1–2 KB, ez még belefér a `players.js`-be);
  - vagy a lejátszó áthelyezhető modulokból áll, és a JavaScript fűzi össze őket
    (egyszerű „linker” a címek javításával, mint a háttér-módnál a
    `RELOCATE_TABLE`).
  Az első egyszerűbb és biztosan bájtazonos a `build.sh`-val; a második akkor
  kell, ha a kombinációk száma elszáll.
- [ ] **A web_parity és az emulátoros teszt minden kombinációra** (vagy egy
  reprezentatív részhalmazra), hogy egyik változat se romoljon el.
- [ ] A felületen a funkciók egy „Mi kerüljön a programba?” részben, mellettük
  a méret- és CPU-költség.

## 1. Hangzás a beépített hanggal (`player_poly.asm`)

- [ ] **Mintavételezett dobok („digidrum”).** A zajból számolt dobok helyett
  rövid, valódi dobminták a DAC-on (lábdob, pergő, cin, taps). Egy szólamot
  egyszeri lejátszású mintatáblára állít. Opció: mintakészlet (beépített vagy
  saját WAV), mintavétel, a minták hossza. Ára: néhány KB adat.
- [ ] **Hangmagasság-hajlítás és vibrato.** A MIDI pitch bend, a modulációs
  kerék és a burkológörbék hangmagasság-része (most kimarad). A lejátszó
  csúszás-parancsával (`B8+s`) vagy egy új „frekvencia beállítás” paranccsal.
- [ ] **0038h-s gyorsítás.** A mintakezelő a 0000h-tól másolva, hogy pontosan
  a 0038h-ra essen (a SID-lejátszó módszere: a terület mentése és
  visszaállítása). Mintánként −10 ciklus. A 0040h–006Fh a 0. kártyahely
  munkaterülete: mentés és visszaállítás kell, a dokumentáció szerint így
  biztonságos.
- [ ] **PWM-négyszög** (állítható és változtatható kitöltési tényező, tábla
  nélkül: `cp pwm / sbc a,a / and vol`) új hullámformaként.
- [ ] **Hosszú zajtábla** 23 bites LFSR-ből és 16 hangerőszint a cinekhez és a
  pergőhöz (most 256 bájtos zaj, 8 szint).
- [ ] **Tiszta keverés keverőtábla nélkül** (a szólamtáblákba előre
  beépített arány): mintánként −18 ciklus, a lineáris keverésnél.
- [ ] 4. szólam alacsonyabb mintavétellel, ha a CPU-idő engedi.
- [ ] **Háttér-mód a többszólamú lejátszóhoz** gépi kódú programok mellé
  (belépési pontok: indítás, leállítás, képkocka-szinkron), alacsony
  mintavétellel, hogy maradjon CPU-idő.

## 2. Konverter

- [ ] **Okosabb szólamválasztás:** csatornánként „mindig szóljon” / „csak ha
  van hely” jelölés, a dallamcsatorna automatikus felismerése.
- [ ] **Más forrásformátumok:** MOD / XM (tracker-zene), VGM (AY, SN76489,
  SAA1099, OPL2 hangchipes zene). A VGM különösen jól illik a hangkártyákhoz
  (lent).

## 3. Hangkártyák

Közös cél: **egy program, ami alapból a beépített hangon szól, de ha talál
hangkártyát, azt is használja** (indításkor felismeri), vagy a konverterben
kiválasztható, hogy csak egy adott kártyára készüljön. A kártyák
lejátszói is külön modulok (0. pont), így a `.cas`-ba csak a kiválasztott
kártyák kódja kerül.

- [ ] **TVC Multichip Soundcard**
  ([dikdom/TVC-Multichip-Soundcard](https://github.com/dikdom/TVC-Multichip-Soundcard)):
  SN76489, SAA1099 és YM3812 (OPL2) hangchip, akár egyszerre. A repó `doc/`
  könyvtárában van a kártya leírása és a chipek adatlapjai.
  - SN76489: 3 négyszög + zaj, MIDI → 3 szólam + dob.
  - SAA1099: 6 csatorna + 2 zaj, burkológörbe-generátor.
  - YM3812: 9 FM-csatorna (vagy 6 + 5 dob), General MIDI-hangszerek FM-hangszínekkel:
    ez adná a legjobb hangzást.
  - Licenc: a kártya repója CC BY-NC-SA 4.0, ez nem fér össze a GPL-lel, ezért
    a kódját nem vehetjük át, a meghajtót az adatlapokból és a kártya
    leírásából magunk írjuk meg.
- [ ] **TVC 256k++ kártya, vSID**: a kártya egy C64 SID-et (MOS 6581/8580)
  emulál, 985 337 Hz-es SID-órajellel, 41 kHz-es mintavétellel, szűrők
  nélkül; a regiszterek ($00–$18) a kártya `WriteSID` hívásán át írhatók
  (TVC256K_Help). 3 szólam hullámformával (háromszög, fűrész, impulzus PWM-mel,
  zaj) és ADSR-rel: a burkológörbék (`--envelopes`) a SID ADSR-jére is
  leképezhetők. A pontos hívási mód és portok a kártya dokumentációjából.
- [ ] **GameCard**: SN76489 hangchip (ugyanaz, mint a Multichip kártyán), ezért
  a meghajtó közös lehet, csak a port más.
- [ ] Felismerés indításkor: a kártyahelyek azonosítója (`5Ah` port, a
  0040h/0070h/00A0h/00D0h táblák) és a kártyák saját jelzései alapján.
- [ ] Emulátoros teszt: ha az Ep128web / ep128emu valamelyik kártyát tudja,
  azzal; különben valódi gépen kell kipróbálni.
