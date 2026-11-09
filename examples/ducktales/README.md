# DuckTales (Disney) – próbadal

A `ducktales.mid` 8 sávos MIDI: dob (10. csatorna), ének (1.), synth (2.),
gitár (3.), rézfúvós (4.), vonósok (5.), basszus (6.), vokál (7.).
Hossza 58 s. A felvételeket (`.mp3`) az Ep128web emulátormagja készítette,
a valódi TVC ROM-mal (TVC 64k+, BASIC 2.2), a `.cas` betöltésével és
lejátszásával.

| Fájl | Lejátszó | Mi szól | Parancs |
| --- | --- | --- | --- |
| `duckpol1` | többszólamú | minden sáv (3 szólam + zaj) | `./build.sh ducktales.mid --mode poly --decay 4 --decay-floor 5` |
| `duckpol2` | többszólamú | ének, rézfúvós, vonós, basszus, dob | `... --mode poly --channels 1,4,6,5,10 --decay 4 --decay-floor 5` |
| `ducktal1` | egycsatornás | dallam (ének + rézfúvós) + dob | `... --mode mono --channels 1,4,10 --decay 3 --decay-floor 8` |
| `ducktal2` | egycsatornás | dallam + basszus arpeggióval + dob | `... --mode arp --max-notes 2 --arp-bass --channels 1,4,6,10 --decay 3 --decay-floor 8` |
