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
; A meghajtók a chipek adatlapjai alapján készültek.
; ============================================================================

CARD_NONE   equ 0
CARD_SN     equ 1

; ---- felismerés ---------------------------------------------------------------
; -> card_type, card_port (a hely I/O alapcíme)
detect_card:
            IF FEAT_SN
            ld hl, name_sndmx
            call find_card
            jr z, .sn
            ld hl, name_joysn
            call find_card
            jr z, .sn
            ENDIF
            xor a
            ld (card_type), a
            ret
            IF FEAT_SN
.sn:        ld (card_port), a
            ld a, CARD_SN
            ld (card_type), a
            ret
            ENDIF

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

            IF FEAT_SN
name_sndmx: db 5, "SndMx"
name_joysn: db 6, "JOY+SN"
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
            ret

chip_update:
            ld a, (card_type)
            IF FEAT_SN
            cp CARD_SN
            jp z, sn_update
            ENDIF
            ret

chip_silence:
            ld a, (card_type)
            IF FEAT_SN
            cp CARD_SN
            jp z, sn_silence
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

card_type:  db 0
card_port:  db 0
vol_scale:  ds 16
