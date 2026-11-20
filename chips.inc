; tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
; Copyright (C) 2026 kks2003 és a közreműködők
;
; Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
; Foundation által kiadott GNU General Public License 2. vagy (választás
; szerint) bármely későbbi változata szerint. A programot a hasznosság
; reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
;
; ============================================================================
; chips.inc - hangkártya-meghajtók a többszólamú lejátszóhoz (player_poly.asm)
;
; Ha a program indításkor hangkártyát talál, a dal a kártyán szól: ugyanazok
; az események (events) és szólamállapotok (voices: hangerő, lecsengés,
; csúszás, hajlítás) futnak, csak a mintánkénti DAC-keverés helyett tickenként
; a kártya regisztereibe írjuk a három szólamot. A tick időzítése marad a
; hangszámláló IT-je, de tickenként egyszer (osztó = mintaosztó * minta/tick),
; így a processzor szinte szabad.
;
; A kártyák felismerése: a bővítőhelyek RAM-területén (0040h + 30h * hely) a
; kártya neve (hossz + szöveg); a hely I/O portjai 10h + 10h * hely-től.
;   GameCard:  "JOY+SN", SN76489 a +0 porton
;   Multichip: "SndMx",  SN76489 a +0, SAA1099 a +2/+3, OPL2 a +4/+5 porton
;   TVC256k++: "256k++", vSID (C64 SID-emuláció): a kártya E0h+n regiszterei,
;              a +0 portra a regiszter sorszáma, a +1-re az érték
; A meghajtók a chipek adatlapjai alapján készültek.
; ============================================================================

CARD_NONE   equ 0
CARD_SN     equ 1
CARD_SID    equ 2
CARD_SAA    equ 3
CARD_OPL    equ 4

; ---- felismerés ---------------------------------------------------------------
; -> card_type, card_port (a hely I/O alapcíme). Ha több is van, a sorrend:
; vSID, OPL2, SAA1099, SN76489 (a Multichip kártyán mindhárom chip megvan).
detect_card:
            IF FEAT_SID
            ld hl, name_256k
            call find_card
            ld b, CARD_SID
            jr z, .found
            ENDIF
            IF FEAT_OPL
            ld hl, name_sndmx
            call find_card
            ld b, CARD_OPL
            jr z, .found
            ENDIF
            IF FEAT_SAA
            ld hl, name_sndmx
            call find_card
            ld b, CARD_SAA
            jr z, .found
            ENDIF
            IF FEAT_SN
            ld hl, name_sndmx
            call find_card
            ld b, CARD_SN
            jr z, .found
            ld hl, name_joysn
            call find_card
            ld b, CARD_SN
            jr z, .found
            ENDIF
            xor a
            ld (card_type), a
            ret
.found:     ld (card_port), a
            ld a, b
            ld (card_type), a
            ret

; HL = a keresett név (hossz, betűk); Z = megvan, A = a hely I/O alapcíme
find_card:
            ld de, 0040h
            ld c, 10h
            ld b, 4
.slot:      push bc
            push de
            push hl
            ld a, (hl)
            inc a
            ld b, a                 ; hossz + a hossz bájtja
.cmp:       ld a, (de)
            cp (hl)
            jr nz, .no
            inc de
            inc hl
            djnz .cmp
.no:        pop hl
            pop de
            pop bc
            ld a, c
            ret z
            ld a, e
            add a, 30h
            ld e, a
            ld a, c
            add a, 10h
            ld c, a
            djnz .slot
            or 1                    ; NZ: nincs
            ret

            IF FEAT_SN || FEAT_SAA || FEAT_OPL
name_sndmx: db 5, "SndMx"
            ENDIF
            IF FEAT_SN
name_joysn: db 6, "JOY+SN"
            ENDIF
            IF FEAT_SID
name_256k:  db 6, "256k++"
            ENDIF

; ---- lejátszás kártyán -----------------------------------------------------------
; a start ide ugrik, ha talált kártyát (a regiszterek már elmentve, DI)
chip_main:
            call init_song
            call chip_init
            ld a, (V_PORT03)        ; billentyűzet: a 7. sor marad kiválasztva
            and 0F0h
            or 07h
            out (P_KBDROW), a
            ld a, 10                ; a CRTC kurzor-IT tiltása
            out (P_CRTCREG), a
            ld a, 23h
            out (P_CRTCDAT), a
            ld hl, IRQVEC           ; a megszakítás a mi kezelőnkre (mint a DAC-nál,
            ld de, saved_irq        ; ugyanannyi bájtot mentünk: a vége ugyanaz)
            IF FEAT_IRQ0038
            ld bc, IRQ_LEN
            ELSE
            ld bc, 3
            ENDIF
            ldir
            ld a, 0C3h
            ld (IRQVEC), a
            ld hl, chip_irq
            ld (IRQVEC + 1), hl
            call tick_work          ; az első események
            call chip_update
            ld a, (SONG_TICKN)      ; hang-IT tickenként: osztó = mintaosztó * minta/tick
            ld b, a
            ld a, (SONG_DIV)
            ld e, a
            ld d, 0
            ld hl, 0
.mul:       add hl, de
            djnz .mul
            ex de, hl
            ld hl, 4096
            or a
            sbc hl, de              ; PITCH = 4096 - osztó
            ld a, l
            out (P_PITCHLO), a
            ld a, (V_PORT05)
            and 0C0h
            or 20h                  ; hang-IT be, hangjel ki
            or h
            out (P_PITCHHI), a
            ld a, (V_PORT06)        ; a beépített hang csendben
            and 0C3h
            out (P_AMP), a
            in a, (5Bh)             ; a számlánc törlése
            out (P_IRQCLR), a
            ei
.wait:      halt
            ld a, (done)
            or a
            jr z, .wait
            di
            call chip_silence
            jp the_end

; tickenként egyszer
chip_irq:
            push af
            out (P_IRQCLR), a
            push bc
            push de
            push hl
            push ix
            push iy
            ld a, (in_tick)
            or a
            jr nz, .skip
            inc a
            ld (in_tick), a
            call tick_work
            call chip_update
            xor a
            ld (in_tick), a
.skip:      pop iy
            pop ix
            pop hl
            pop de
            pop bc
            pop af
            ei
            ret

; ---- közös ----------------------------------------------------------------------
; a hangerő (0..15, a szólam hangereje a dalban legfeljebb SONG_VMAX) ->
; 0..15 a kártyára: v * 15 / vmax (vol_scale tábla, induláskor)
chip_init:
            ld a, (SONG_VMAX)
            or a
            jr nz, .vm
            ld a, 15
.vm:        ld c, a
            ld hl, vol_scale
            ld b, 0                 ; B = v
.v:         ld a, b
            ld e, a                 ; v * 15
            add a, a
            add a, a
            add a, a
            add a, a
            sub e
            ld d, 0                 ; D = (v * 15) / vmax
.dv:        cp c
            jr c, .dd
            sub c
            inc d
            jr .dv
.dd:        ld a, d
            cp 16
            jr c, .ok
            ld a, 15
.ok:        ld (hl), a
            inc hl
            inc b
            ld a, b
            cp 16
            jr nz, .v
            ld a, (card_type)
            IF FEAT_SN
            cp CARD_SN
            jp z, sn_init
            ENDIF
            IF FEAT_SID
            cp CARD_SID
            jp z, sid_init
            ENDIF
            IF FEAT_SAA
            cp CARD_SAA
            jp z, saa_init
            ENDIF
            IF FEAT_OPL
            cp CARD_OPL
            jp z, opl_init
            ENDIF
            ret

chip_update:
            ld a, (card_type)
            IF FEAT_SN
            cp CARD_SN
            jp z, sn_update
            ENDIF
            IF FEAT_SID
            cp CARD_SID
            jp z, sid_update
            ENDIF
            IF FEAT_SAA
            cp CARD_SAA
            jp z, saa_update
            ENDIF
            IF FEAT_OPL
            cp CARD_OPL
            jp z, opl_update
            ENDIF
            ret

chip_silence:
            ld a, (card_type)
            IF FEAT_SN
            cp CARD_SN
            jp z, sn_silence
            ENDIF
            IF FEAT_SID
            cp CARD_SID
            jp z, sid_silence
            ENDIF
            IF FEAT_SAA
            cp CARD_SAA
            jp z, saa_silence
            ENDIF
            IF FEAT_OPL
            cp CARD_OPL
            jp z, opl_silence
            ENDIF
            ret

; HL = a szólam állapota -> A = a hullámforma (0..5), B = hangerő a kártyára
; (0..15), DE = fázisnövekmény (VS_F); HL marad
voice_get:
            push hl
            ld e, (hl)              ; VS_F
            inc hl
            ld d, (hl)
            inc hl
            inc hl
            inc hl                  ; VS_VOL
            ld a, (hl)
            push de
            ld e, a
            ld d, 0
            push hl
            ld hl, vol_scale
            add hl, de
            ld b, (hl)
            pop hl
            pop de
            inc hl                  ; VS_DEC
            inc hl                  ; VS_CNT
            inc hl                  ; VS_FLOOR
            inc hl                  ; VS_SLOT
            ld a, (hl)
            push de
            ld e, a
            ld d, 0
            ld hl, SONG_WAVES
            add hl, de
            ld a, (hl)
            pop de
            pop hl
            ret

; AHL / BC -> AHL (24 bites hányados), DE = maradék; IXL számláló
div24:
            ld de, 0
            ld ixl, 24
.lp:        add hl, hl              ; AHL <<= 1, a kilépő bit a maradékba
            rla
            ex de, hl
            adc hl, hl
            jr c, .big              ; a maradék túllépte a 16 bitet: biztosan nagyobb
            or a
            sbc hl, bc
            jr nc, .one
            add hl, bc
            ex de, hl
            jr .nx
.big:       or a
            sbc hl, bc
.one:       ex de, hl
            inc l                   ; a hányados bitje
.nx:        dec ixl
            jr nz, .lp
            ret

            IF FEAT_SID || FEAT_OPL
; HL * DE -> DEHL (32 bit)
mul16:
            push bc
            ld b, h
            ld c, l
            ld hl, 0
            ld a, 16
.m:         add hl, hl
            rl e
            rl d
            jr nc, .n
            add hl, bc
            jr nc, .n
            inc de
.n:         dec a
            jr nz, .m
            pop bc
            ret
            ENDIF

            IF FEAT_SN
; ---- SN76489 (GameCard, Multichip) -------------------------------------------------
; 3 négyszög-csatorna (10 bites osztó: f = órajel / (32 * N), órajel
; 3 579 545 Hz) és egy zajcsatorna; hangerő: 4 bites csillapítás, 2 dB-es
; lépésekben (0 = leghangosabb, 15 = néma). A zaj-hullámformájú szólam a
; zajcsatornán szól.
SN_K        equ 37535               ; N = SN_K * mintaosztó / fázisnövekmény

sn_init:
            ld a, (SONG_DIV)        ; sn_k = SN_K * osztó (24 bit)
            ld b, a
            xor a
            ld hl, 0
            ld c, 0
.m:         ld de, SN_K
            add hl, de
            adc a, c
            djnz .m
            ld (sn_k), hl
            ld (sn_k + 2), a
            ld a, (card_port)
            ld c, a
            ld a, 0E4h              ; zaj: fehér, a leggyorsabb
            out (c), a
sn_silence:
            ld a, (card_port)
            ld c, a
            ld a, 9Fh               ; mind a négy csatorna néma
            out (c), a
            ld a, 0BFh
            out (c), a
            ld a, 0DFh
            out (c), a
            ld a, 0FFh
            out (c), a
            ret

sn_update:
            xor a
            ld (sn_noise), a
            ld hl, vstate
            ld a, 0
.voice:     push af                 ; A = a csatorna (0..2)
            push hl
            call voice_get          ; A = hullámforma, B = hangerő, DE = F
            ld c, a
            pop hl
            pop af
            push hl
            push af                 ; A = csatorna
            ld a, c
            cp 4                    ; zaj: a zajcsatornára
            jr nz, .tone
            ld a, (sn_noise)
            cp b
            jr nc, .nmax
            ld a, b
            ld (sn_noise), a
.nmax:      ld b, 0                 ; a hangcsatorna néma
            jr .vol
.tone:      push bc
            ld a, d
            or e
            jr z, .t0
            ld b, d                 ; BC = F
            ld c, e
            ld hl, (sn_k)
            ld a, (sn_k + 2)
            call div24              ; AHL = N = sn_k / F
            or a
            jr nz, .t0
            ld a, h                 ; legfeljebb 1023 (a mélyebb hangok ott maradnak)
            cp 4
            jr c, .t1
.t0:        ld hl, 1023
.t1:        pop bc
            pop af                  ; csatorna
            push af
            push bc
            rrca
            rrca
            rrca                    ; csatorna * 32
            ld b, a
            ld a, l
            and 0Fh
            or b
            or 80h                  ; 1 cc 0 nnnn: a hang alsó 4 bitje
            ld b, a
            ld a, (card_port)
            ld c, a
            out (c), b
            ld a, l                 ; 0 0 hhhhhh: a felső 6 bit
            srl h
            rra
            srl h
            rra
            srl h
            rra
            srl h
            rra
            and 3Fh
            out (c), a
            pop bc
.vol:       ld e, b                 ; hangerő 0..15 -> csillapítás
            ld d, 0
            ld hl, sn_att
            add hl, de
            ld b, (hl)
            pop af                  ; csatorna
            push af
            rrca
            rrca
            rrca
            or 90h                  ; 1 cc 1 aaaa
            or b
            ld b, a
            ld a, (card_port)
            ld c, a
            out (c), b
            pop af
            pop hl
            ld de, VS_SIZE
            add hl, de
            inc a
            cp 3
            jp nz, .voice
            ld a, (sn_noise)        ; a zajcsatorna hangereje
            ld e, a
            ld d, 0
            ld hl, sn_att
            add hl, de
            ld a, (hl)
            or 0F0h
            ld b, a
            ld a, (card_port)
            ld c, a
            out (c), b
            ret

; hangerő (0..15, lineáris) -> csillapítás (2 dB-es lépés): round(-20 lg(v/15) / 2)
sn_att:     db 15, 12, 9, 7, 6, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0
sn_k:       ds 3
sn_noise:   db 0
            ENDIF

            IF FEAT_SID
; ---- vSID (TVC256k++) ---------------------------------------------------------------
; 3 szólam hullámformával (háromszög, fűrész, impulzus, zaj) és ADSR-rel; a
; SID órajele 985 337 Hz (336 MHz / 341). Frekvencia: SIDF = f * 2^24 / órajel =
; F * sid_k / 65536, sid_k = 3 325 563 / mintaosztó. Hangerő szólamonként nincs:
; a kitartási szinttel (S) állítjuk; a SID ezt csak csökkenteni engedi, ezért
; ha nő (új hang), a kaput rövid szünettel újraindítjuk (attack 2 ms).
SID_K24     equ 3325563

sid_init:
            ld a, (SONG_DIV)        ; sid_k = (SID_K24 + osztó/2) / osztó
            ld c, a
            ld b, 0
            srl a
            ld e, a
            ld d, 0
            ld hl, SID_K24 & 0FFFFh
            add hl, de
            ld a, SID_K24 >> 16
            adc a, 0
            call div24
            ld (sid_k), hl
            ld (sid_k + 2), a
            ld a, (card_port)       ; nincs automatikus regiszterléptetés
            add a, 2
            ld c, a
            xor a
            out (c), a
            ld a, 24                ; fő hangerő: max., szűrő nincs
            ld b, 0Fh
            call sid_w
            ld hl, sid_last
            ld b, 6
.z:         ld (hl), 0
            inc hl
            djnz .z
sid_silence:
            ld e, 0                 ; minden szólam: kapu ki, ADSR 0
.v:         ld a, e
            add a, 4
            ld b, 0
            call sid_w
            ld a, e
            add a, 5
            call sid_w
            ld a, e
            add a, 6
            call sid_w
            ld a, e
            add a, 7
            ld e, a
            cp 21
            jr c, .v
            ret

; A = SID-regiszter (0..24), B = érték
sid_w:
            push bc
            push af
            ld a, (card_port)
            ld c, a
            pop af
            push af
            add a, 0E0h
            out (c), a
            inc c
            out (c), b
            pop af
            pop bc
            ret

sid_update:
            ld hl, vstate
            xor a
.voice:     push af                 ; A = szólam
            push hl
            call voice_get          ; A = hullámforma, B = hangerő, DE = F
            ld (sid_tmp), a
            ld a, b
            ld (sid_tmp + 1), a
            ld (sid_tmp + 2), de
            pop hl
            pop af
            push hl
            push af
            ld c, a                 ; C = szólam, a regiszterek alapja 7 * C
            add a, a
            add a, a
            add a, a
            sub c
            ld (sid_base), a
            ; frekvencia: zajnál fix, világos
            ld a, (sid_tmp)
            cp 4
            ld hl, 0C000h
            jr z, .freq
            ld hl, (sid_tmp + 2)    ; F * sid_k / 65536
            ld de, (sid_k)
            call mul16              ; DEHL = F * (sid_k alsó 16 bitje)
            push de                 ; a szorzat felső 16 bitje
            ld a, (sid_k + 2)       ; + F * (sid_k felső bájtja, legfeljebb 3)
            ld de, (sid_tmp + 2)
            ld hl, 0
            or a
            jr z, .hiok
.hi:        add hl, de
            dec a
            jr nz, .hi
.hiok:      pop de
            add hl, de
            jr nc, .freq
            ld hl, 0FFFFh
.freq:      ld a, (sid_base)
            ld b, l
            call sid_w              ; 0: frekvencia alsó bájt
            inc a
            ld b, h
            call sid_w              ; 1: felső bájt
            ; hullámforma és impulzusszélesség
            ld a, (sid_tmp)
            ld e, a
            ld d, 0
            ld hl, sid_wave
            add hl, de
            ld a, (hl)
            ld (sid_ctl), a
            ld hl, sid_pw
            add hl, de
            ld a, (sid_base)
            add a, 2
            ld b, 0
            call sid_w              ; 2: PW alsó
            inc a
            ld b, (hl)
            call sid_w              ; 3: PW felső (4 bit)
            ld a, (sid_base)        ; 5: AD = 0 (attack 2 ms, decay 6 ms)
            add a, 5
            ld b, 0
            call sid_w
            ; hangerő -> kitartási szint; ha nő, a kapu újraindul
            pop af
            push af
            ld e, a
            ld d, 0
            ld hl, sid_last
            add hl, de
            ld a, (sid_tmp + 1)
            ld c, a                 ; C = az új hangerő
            ld b, (hl)              ; B = az előző
            ld (hl), a
            ld a, (sid_base)
            add a, 6
            push bc
            ld b, c
            sla b
            sla b
            sla b
            sla b
            call sid_w              ; 6: SR = hangerő << 4, release 0
            pop bc
            ld a, c
            or a
            ld a, (sid_ctl)
            jr z, .gate             ; néma: kapu ki
            ld a, c
            cp b
            jr z, .keep
            jr c, .keep             ; csökken: a kitartási szint elég
            ld a, (sid_base)        ; nő: kapu ki, rövid szünet, kapu be
            add a, 4
            ld b, a
            ld a, (sid_ctl)
            push bc
            ld c, b
            ld b, a
            ld a, c
            call sid_w
            pop bc
            ld b, 10
.dl:        djnz .dl
.keep:      ld a, (sid_ctl)
            or 1
.gate:      ld b, a
            ld a, (sid_base)
            add a, 4
            call sid_w              ; 4: vezérlés (hullámforma, kapu)
            pop af
            pop hl
            ld de, VS_SIZE
            add hl, de
            inc a
            cp 3
            jp nz, .voice
            ret

; hullámforma (0 négyszög, 1 impulzus 25%, 2 háromszög, 3 fűrész, 4 zaj, 5 szinusz,
; 6 impulzus 12,5%)
sid_wave:   db 40h, 40h, 10h, 20h, 80h, 10h, 40h
sid_pw:     db 08h, 04h, 08h, 08h, 08h, 08h, 02h      ; PW felső 4 bit (alsó bájt 0)
sid_k:      ds 3
sid_last:   ds 6
sid_tmp:    ds 4
sid_base:   db 0
sid_ctl:    db 0
            ENDIF

            IF FEAT_SAA
; ---- SAA1099 (Multichip) -------------------------------------------------------------
; 6 négyszög-csatorna (ebből 3-at használunk) és 2 zajgenerátor, 8 MHz-es
; órajel. Frekvencia: f = 15625 * 2^okt / (511 - N), okt 0..7, N 0..255.
; A mi fázisnövekményünkből (F, mintaosztó d): 511 - N = 5242,88 * d * 2^okt / F;
; T = SAA_K * d / F = 8 * 5242,88 * d / F, és az oktávot úgy választjuk, hogy
; T * 2^okt a [2048, 4096) tartományba essen: 511 - N = T * 2^okt / 8.
; Hangerő: 4 bites amplitúdó (bal, jobb). A zaj-hullámformájú szólam a 0. zaj-
; generátort (a leggyorsabb) kapja a saját csatornáján.
SAA_K       equ 41943

saa_init:
            ld a, (SONG_DIV)        ; saa_k = SAA_K * osztó (24 bit)
            ld b, a
            xor a
            ld hl, 0
            ld c, 0
.m:         ld de, SAA_K
            add hl, de
            adc a, c
            djnz .m
            ld (saa_k), hl
            ld (saa_k + 2), a
            ld a, 1Ch               ; törlés, majd hang be
            ld b, 02h
            call saa_w
            ld b, 01h
            call saa_w
            ld a, 16h               ; zajgenerátorok: a leggyorsabb
            ld b, 0
            call saa_w
            ld a, 18h               ; burkológörbe-generátorok ki
            call saa_w
            inc a
            call saa_w
saa_silence:
            xor a                   ; amplitúdók 0, frekvencia és zaj ki
            ld b, a
.s:         call saa_w
            inc a
            cp 6
            jr c, .s
            ld a, 14h
            call saa_w
            inc a
            call saa_w
            ret

; A = regiszter, B = érték (A, B, DE, HL marad)
saa_w:
            push bc
            push af
            ld a, (card_port)
            add a, 3
            ld c, a
            pop af
            out (c), a              ; +3: cím
            dec c
            out (c), b              ; +2: adat
            pop bc
            ret

saa_update:
            xor a
            ld (saa_oct), a
            ld (saa_oct + 1), a
            ld (saa_ten), a
            ld (saa_nen), a
            ld hl, vstate
.voice:     push af                 ; A = csatorna
            push hl
            call voice_get          ; A = hullámforma, B = hangerő, DE = F
            ld (ch_wave), a
            ld a, b
            ld (ch_vol), a
            ld (ch_f), de
            pop hl
            pop af
            push hl
            push af
            ld c, a                 ; C = csatorna
            ld a, (ch_vol)          ; amplitúdó: bal = jobb = hangerő
            ld b, a
            add a, a
            add a, a
            add a, a
            add a, a
            or b
            ld b, a
            ld a, c
            call saa_w
            ld a, c                 ; B = 1 << csatorna
            ld b, 1
            or a
            jr z, .bm
.bl:        sla b
            dec a
            jr nz, .bl
.bm:        ld a, (ch_vol)
            or a
            jr z, .next             ; néma: se hang, se zaj
            ld a, (ch_wave)
            cp 4
            jr nz, .tone
            ld a, (saa_nen)
            or b
            ld (saa_nen), a
            jr .next
.tone:      ld a, (saa_ten)
            or b
            ld (saa_ten), a
            push bc
            ld de, (ch_f)
            ld a, d
            or e
            jr z, .low
            ld b, d
            ld c, e
            ld hl, (saa_k)
            ld a, (saa_k + 2)
            call div24              ; AHL = T
            or a
            jr nz, .low
            ld a, h
            cp 10h
            jr nc, .low             ; T >= 4096: a legmélyebb hang
            ld e, 0                 ; E = oktáv
.oc:        ld a, h
            cp 08h
            jr nc, .got
            ld a, e
            cp 7
            jr z, .got
            add hl, hl
            inc e
            jr .oc
.got:       srl h                   ; 511 - N = HL / 8
            rr l
            srl h
            rr l
            srl h
            rr l
            ld a, h
            or a
            jr nz, .mok
            ld l, 0                 ; túl magas: N = 255
.mok:       ld a, l
            cpl                     ; N = 511 - (256 + L) = 255 - L
            ld d, a
            jr .wr
.low:       ld de, 0
.wr:        pop bc
            ld a, c                 ; frekvencia: 08h + csatorna
            add a, 8
            ld b, d
            call saa_w
            ld a, c                 ; oktáv: 10h (0., 1. csatorna), 11h (2.)
            and 1
            ld a, e
            jr z, .ol
            add a, a
            add a, a
            add a, a
            add a, a
.ol:        ld b, a
            ld a, c
            srl a
            ld e, a
            ld d, 0
            ld hl, saa_oct
            add hl, de
            ld a, (hl)
            or b
            ld (hl), a
.next:      pop af
            pop hl
            ld de, VS_SIZE
            add hl, de
            inc a
            cp 3
            jp nz, .voice
            ld a, (saa_oct)
            ld b, a
            ld a, 10h
            call saa_w
            ld a, (saa_oct + 1)
            ld b, a
            ld a, 11h
            call saa_w
            ld a, (saa_ten)
            ld b, a
            ld a, 14h
            call saa_w
            ld a, (saa_nen)
            ld b, a
            ld a, 15h
            call saa_w
            ret

saa_k:      ds 3
saa_oct:    ds 2
saa_ten:    db 0
saa_nen:    db 0
            ENDIF

            IF FEAT_OPL
; ---- YM3812 / OPL2 (Multichip) --------------------------------------------------------
; 9 FM-csatorna, ebből 3: a 0..2. csatorna (modulátor: 0..2., vivő: 3..5.
; operátor). Frekvencia: f = Fnum * 49716 / 2^(20 - blokk); a mi F-ünkből
; Fnum (0. blokk) = F * 62,857 / d = F * opl_k / 65536, opl_k = OPL_K24 / d,
; majd blokkonként felezve, amíg 1024 alá nem ér. Hangszín a hullámformából: a
; modulátor szorzója, erőssége és visszacsatolása (1:2 arány = páratlan
; felharmonikusok, négyszögszerű; 1:1 visszacsatolással = fűrészszerű; a
; háromszög és a szinusz majdnem tiszta szinusz). Hangerő: a vivő
; csillapítása (0,75 dB-es lépés). Új hangnál (a hangerő nő) a kulcs újra
; lenyomódik. Írás után a chipnek idő kell (cím 3,3 us, adat 23 us).
OPL_K24     equ 4119406

opl_init:
            ld a, (SONG_DIV)        ; opl_k = (OPL_K24 + osztó/2) / osztó
            ld c, a
            ld b, 0
            srl a
            ld e, a
            ld d, 0
            ld hl, OPL_K24 & 0FFFFh
            add hl, de
            ld a, OPL_K24 >> 16
            adc a, 0
            call div24
            ld (opl_k), hl
            ld (opl_k + 2), a
            ld a, 01h               ; hullámforma-választás engedélyezve
            ld b, 20h
            call opl_w
            ld a, 08h
            ld b, 0
            call opl_w
            ld a, 0BDh              ; dallam-mód, nincs dob
            call opl_w
            ld e, 0                 ; a 0..5. operátor
.op:        ld a, 20h
            add a, e
            ld b, 21h               ; kitartott, szorzó 1
            call opl_w
            ld a, 40h
            add a, e
            ld b, 3Fh               ; néma
            call opl_w
            ld a, 60h
            add a, e
            ld b, 0F0h              ; azonnali felfutás, nincs lecsengés
            call opl_w
            ld a, 80h
            add a, e
            ld b, 0Fh               ; kitartás a csúcson, gyors elengedés
            call opl_w
            ld a, 0E0h
            add a, e
            ld b, 0                 ; szinusz
            call opl_w
            inc e
            ld a, e
            cp 6
            jr c, .op
            xor a
            ld (opl_last), a
            ld (opl_last + 1), a
            ld (opl_last + 2), a
opl_silence:
            ld e, 0
.s:         ld a, 0B0h              ; kulcs fel
            add a, e
            ld b, 0
            call opl_w
            ld a, 43h               ; a vivő néma
            add a, e
            ld b, 3Fh
            call opl_w
            inc e
            ld a, e
            cp 3
            jr c, .s
            ret

; A = regiszter, B = érték (A, DE, HL marad)
opl_w:
            push bc
            push af
            ld a, (card_port)
            add a, 4
            ld c, a
            pop af
            out (c), a              ; +4: regiszter
            push af                 ; várakozás (3,3 us)
            pop af
            inc c
            out (c), b              ; +5: adat
            ld b, 6                 ; várakozás (23 us)
.d:         djnz .d
            pop bc
            ret

opl_update:
            ld hl, vstate
            xor a
.voice:     push af                 ; A = csatorna
            push hl
            call voice_get          ; A = hullámforma, B = hangerő, DE = F
            ld (ch_wave), a
            ld a, b
            ld (ch_vol), a
            ld (ch_f), de
            pop hl
            pop af
            push hl
            push af
            ld c, a                 ; C = csatorna
            ld a, (ch_wave)         ; hangszín
            ld e, a
            ld d, 0
            ld hl, opl_mmul
            add hl, de
            ld b, (hl)
            ld a, 20h
            add a, c
            call opl_w              ; modulátor: szorzó
            ld hl, opl_mtl
            add hl, de
            ld b, (hl)
            ld a, 40h
            add a, c
            call opl_w              ; modulátor: erősség
            ld hl, opl_fb
            add hl, de
            ld b, (hl)
            ld a, 0C0h
            add a, c
            call opl_w              ; visszacsatolás, FM
            ld a, (ch_vol)          ; vivő: csillapítás a hangerőből
            ld e, a
            ld hl, opl_tl
            add hl, de
            ld b, (hl)
            ld a, 43h
            add a, c
            call opl_w
            ; frekvencia
            ld a, (ch_wave)
            cp 4
            ld hl, 03FFh            ; zaj: magas, fix
            ld e, 6
            jr z, .fw
            push bc
            ld hl, (ch_f)           ; Fnum0 = F * opl_k / 65536 (24 bit)
            ld de, (opl_k)
            call mul16
            ex de, hl               ; HL = a szorzat felső 16 bitje
            ld de, (ch_f)
            ld a, (opl_k + 2)
            ld b, a
            xor a
            inc b
            jr .hc
.hi:        add hl, de
            adc a, 0
.hc:        djnz .hi
            ld e, 0                 ; E = blokk
.bk:        or a
            jr nz, .sh
            ld b, a
            ld a, h
            cp 4
            ld a, b
            jr c, .bok
.sh:        ld b, a
            ld a, e
            cp 7
            ld a, b
            jr z, .clamp
            srl a
            rr h
            rr l
            inc e
            jr .bk
.clamp:     ld hl, 03FFh
.bok:       pop bc
.fw:        ld a, 0A0h              ; Fnum alsó 8 bit
            add a, c
            ld b, l
            call opl_w
            ld a, e                 ; blokk << 2 | Fnum felső 2 bit
            add a, a
            add a, a
            or h
            ld (ch_f), a            ; (ideiglenesen)
            ; kulcs: hangerő > 0; ha nő, előbb fel
            ld e, c
            ld d, 0
            ld hl, opl_last
            add hl, de
            ld a, (ch_vol)
            ld b, (hl)
            ld (hl), a
            or a
            jr z, .off
            cp b
            jr z, .on
            jr c, .on
            ld a, (ch_f)            ; nő: kulcs fel, majd le
            ld b, a
            ld a, 0B0h
            add a, c
            call opl_w
.on:        ld a, (ch_f)
            or 20h
            jr .key
.off:       ld a, (ch_f)
.key:       ld b, a
            ld a, 0B0h
            add a, c
            call opl_w
            pop af
            pop hl
            ld de, VS_SIZE
            add hl, de
            inc a
            cp 3
            jp nz, .voice
            ret

; hullámforma (0 négyszög, 1 impulzus 25%, 2 háromszög, 3 fűrész, 4 zaj, 5 szinusz,
; 6 impulzus 12,5%)
opl_mmul:   db 22h, 21h, 22h, 21h, 2Fh, 21h, 21h    ; modulátor: kitartott, szorzó
opl_mtl:    db 21h, 21h, 2Dh, 25h, 00h, 3Fh, 1Dh    ; modulátor erőssége (0,75 dB-es lépés, 3Fh: nincs)
opl_fb:     db 00h, 04h, 00h, 0Ch, 0Eh, 00h, 06h    ; visszacsatolás << 1, FM
; hangerő (0..15, lineáris) -> a vivő csillapítása: round(-20 lg(v/15) / 0,75)
opl_tl:     db 63, 31, 23, 19, 15, 13, 11, 9, 7, 6, 5, 4, 3, 2, 1, 0
opl_k:      ds 3
opl_last:   ds 3
            ENDIF

            IF FEAT_SAA || FEAT_OPL
ch_wave:    db 0
ch_vol:     db 0
ch_f:       dw 0
            ENDIF

card_type:  db 0
card_port:  db 0
vol_scale:  ds 16
