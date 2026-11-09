; ============================================================================
; player_poly.asm - többszólamú MIDI-lejátszó Videoton TVC-re (sjasmplus)
;
; A hangoszcillátor helyett a 06h amplitúdóregiszter 4 bites DAC-ként szól
; (05h b4 = 0: a hangerő-szabályzó bemenetén állandó "1" szint van).
; A lejátszó szoftveresen kever:
;   - 3 négyszög szólam: 16 bites fázisakkumulátor (HL, DE, IX), a
;     fázisnövekmény és a hangerő önmódosító operandus (f1..f3, v1..v3)
;   - 1 zajcsatorna (16 bites Galois-LFSR a HL'-ben, hangerő: v5)
;   - a négy forrás összege (0..60) egy 64 bájtos keverőtáblán át (lágy
;     telítés, a dal adataiban) megy ki a 06h-ra
; A minta-hurok állandó idejű (LOOP_CYCLES ciklus), megszakítás nélkül fut
; (DI), és minden mintánál a 59h port kurzor-IT bitjét nézi: képkockánként
; (49,76 Hz, a hardver időzít) egy "tick": ESC/SPACE figyelése, az események
; feldolgozása, lecsengés, hangcsúszás (lábdob), az operandusok frissítése.
;
; A .cas fejléc és a BASIC indító sorok: cas.inc.
; ============================================================================

P_PITCHHI   equ 05h
P_AMP       equ 06h
P_KBDROW    equ 03h
P_KBDIN     equ 58h
P_IRQST     equ 59h
P_IRQCLR    equ 07h

V_PORT03    equ 0B11h
V_PORT05    equ 0B12h
V_PORT06    equ 0B13h

KEYMASK     equ 28h                 ; 7. sor: b3 ESC, b5 SPACE (0 = lenyomva)

; a minta-hurok hossza Z80-ciklusban (a midi2tvc.py ebből számolja a
; mintavételi frekvenciát)
LOOP_CYCLES equ 271

; ---- dal adatformátum (midi2tvc.py --mode poly) ---------------------------
; +0   flags: b0 = ismétlés
; +1   lecsengés (tick / hangerőlépés, 0 = nincs)
; +2   lecsengés alsó szintje
; +3   tartalék
; +4   dw ismétlési pont (az eseménylista elejéhez képest)
; +6   dw tartalék
; +8   64 bájt keverőtábla: összeg (0..60) -> kimenet (0..15)
; +72  128 x dw fázisnövekmény (MIDI hangjegy -> f * 65536 / mintafrekvencia)
; +328 eseménylista:
;   80+16*s+h  n        hang a szólamon (s = 0..2, h = hangerő 0..15), n = hangjegy
;   B0+s                a szólam elhallgat
;   B4 vd               zaj: v = hangerő, d = lecsengés (tick / lépés)
;   B8+s n vd lo hi     csúszó hang (dob): n = kezdőhang, v/d hangerő és
;                       lecsengés (0-ig), lo hi = fázisnövekmény-változás / tick
;   BF lo hi            várakozás lo+256*hi tick
;   C0..FE              várakozás 1..63 tick
;   FF                  vége (ismétléskor ugrás az ismétlési pontra)
SONG_FLAGS  equ song+0
SONG_DECAY  equ song+1
SONG_FLOOR  equ song+2
SONG_LOOP   equ song+4
SONG_MIX    equ song+8
SONG_FREQ   equ song+72
SONG_EVENTS equ song+328

; szólamonkénti állapot (8 bájt)
VS_F        equ 0                   ; dw fázisnövekmény
VS_SLIDE    equ 2                   ; dw változás / tick
VS_VOL      equ 4
VS_DEC      equ 5                   ; lecsengés (tick / lépés)
VS_CNT      equ 6
VS_FLOOR    equ 7

            include "cas.inc"

; ---- belépés ----------------------------------------------------------------
start:
            di
            ld a, (V_PORT03)        ; billentyűzet: a 7. sor marad kiválasztva
            and 0F0h
            or 07h
            out (P_KBDROW), a
            call init_song
            ld a, (V_PORT06)        ; keverőtábla a 06h többi bitjével
            and 0C3h
            ld c, a
            ld hl, SONG_MIX
            ld de, mixtab
            ld b, 64
.mt:        ld a, (hl)
            add a, a
            add a, a
            or c
            ld (de), a
            inc hl
            inc de
            djnz .mt
            ld a, (V_PORT05)        ; DAC-mód: hangjel (b4) és hang-IT (b5) ki
            and 0C0h
            ld (V_PORT05), a
            out (P_PITCHHI), a
            out (P_IRQCLR), a
            call tick               ; az első események
            ld hl, 0
            ld de, 0
            ld ix, 0
            exx
            ld hl, 0ACE1h           ; LFSR
            exx

; ---- minta-hurok (LOOP_CYCLES ciklus, minden ágon ugyanannyi) -------------
loop:
f1:         ld bc, 0                ; 10  1. szólam
            add hl, bc              ; 11
f2:         ld bc, 0                ; 10  2. szólam
            ex de, hl               ; 4
            add hl, bc              ; 11
            ex de, hl               ; 4
f3:         ld bc, 0                ; 10  3. szólam
            add ix, bc              ; 15
            ld a, h                 ; 4
            rlca                    ; 4
            sbc a, a                ; 4
v1:         and 0                   ; 7
            ld c, a                 ; 4
            ld a, d                 ; 4
            rlca                    ; 4
            sbc a, a                ; 4
v2:         and 0                   ; 7
            add a, c                ; 4
            ld c, a                 ; 4
            ld a, ixh               ; 8
            rlca                    ; 4
            sbc a, a                ; 4
v3:         and 0                   ; 7
            add a, c                ; 4
            ld c, a                 ; 4
            exx                     ; 4   zaj
            srl h                   ; 8
            rr l                    ; 8
            sbc a, a                ; 4
            and 0B4h                ; 7
            xor h                   ; 4
            ld h, a                 ; 4
            ld a, l                 ; 4
            exx                     ; 4
v5:         and 0                   ; 7
            add a, c                ; 4
            ld c, a                 ; 4
            ld b, high mixtab       ; 7
            ld a, (bc)              ; 7
            out (P_AMP), a          ; 11
            in a, (P_IRQST)         ; 11  képkocka-IT (DI mellett is jelez)
            and 10h                 ; 7
            jp nz, loop             ; 10  = 271
            call tick
            ld a, (done)
            or a
            jp z, loop

; ---- vége -------------------------------------------------------------------
stop:
            ld a, (V_PORT06)        ; csend
            and 0C3h
            ld (V_PORT06), a
            out (P_AMP), a
            ld a, (V_PORT05)
            and 0C0h
            ld (V_PORT05), a
            out (P_PITCHHI), a
.release:   in a, (P_KBDIN)         ; megvárjuk, hogy elengedjék a gombot
            and KEYMASK
            cp KEYMASK
            jr nz, .release
            ld a, (V_PORT03)
            out (P_KBDROW), a
            ei
            ld hl, 0
            ret

init_song:
            ld hl, SONG_EVENTS
            ld (ptr), hl
            ld de, (SONG_LOOP)
            add hl, de
            ld (loop_ptr), hl
            ld hl, 0
            ld (wait), hl
            xor a
            ld (done), a
            ld (noise_vol), a
            ld (noise_dec), a
            ld hl, vstate
            ld b, 3 * 8
.clr:       ld (hl), a
            inc hl
            djnz .clr
            ret

; ---- tick: képkockánként -----------------------------------------------------
tick:
            out (P_IRQCLR), a       ; a kurzor-IT törlése
            push hl
            push de
            push ix
            in a, (P_KBDIN)
            and KEYMASK
            cp KEYMASK
            jr z, .keys_ok
            ld a, 1
            ld (done), a
            jr .out
.keys_ok:
            call events
            call voices
.out:
            pop ix
            pop de
            pop hl
            ret

; IX = a szólam állapota (A = 0..2)
voice_ix:
            add a, a
            add a, a
            add a, a
            ld c, a
            ld b, 0
            ld ix, vstate
            add ix, bc
            ret

; DE = a hangjegy (A) fázisnövekménye
note_freq:
            push hl
            ld l, a
            ld h, 0
            add hl, hl
            ld de, SONG_FREQ
            add hl, de
            ld e, (hl)
            inc hl
            ld d, (hl)
            pop hl
            ret

events:
            ld hl, (wait)
            ld a, h
            or l
            jr z, .parse
            dec hl
            ld (wait), hl
            ld a, h
            or l
            ret nz
.parse:
            ld hl, (ptr)
.next:
            ld a, (hl)
            inc hl
            cp 0C0h
            jr nc, .short
            cp 80h
            jr c, .next             ; 00..7F: fenntartott
            cp 0B0h
            jr c, .note
            cp 0B3h
            jr c, .off
            cp 0B4h
            jp z, .noise
            cp 0B8h
            jr c, .next
            cp 0BBh
            jp c, .slide
            cp 0BFh
            jr nz, .next
            ld e, (hl)              ; BF lo hi: hosszú várakozás
            inc hl
            ld d, (hl)
            inc hl
            ld (ptr), hl
            ld (wait), de
            ret
.short:
            cp 0FFh
            jr z, .end
            sub 0BFh
            ld (ptr), hl
            ld l, a
            ld h, 0
            ld (wait), hl
            ret
.end:
            ld a, (SONG_FLAGS)
            rrca
            jr nc, .finish
            ld hl, (loop_ptr)
            jr .next
.finish:
            dec hl
            ld (ptr), hl
            ld a, 1
            ld (done), a
            ret
.note:                              ; 80+16*s+h, n
            ld b, a
            rrca
            rrca
            rrca
            rrca
            and 03h
            push bc
            call voice_ix
            pop bc
            ld a, b
            and 0Fh
            ld (ix + VS_VOL), a
            ld a, (hl)
            inc hl
            call note_freq
            ld (ix + VS_F), e
            ld (ix + VS_F + 1), d
            xor a
            ld (ix + VS_SLIDE), a
            ld (ix + VS_SLIDE + 1), a
            ld a, (SONG_DECAY)
            ld (ix + VS_DEC), a
            ld (ix + VS_CNT), a
            ld a, (SONG_FLOOR)
            ld (ix + VS_FLOOR), a
            jp .next
.off:
            sub 0B0h
            call voice_ix
            ld (ix + VS_VOL), 0
            jp .next
.noise:
            ld a, (hl)
            inc hl
            ld b, a
            and 0Fh
            ld (noise_dec), a
            ld (noise_cnt), a
            ld a, b
            rrca
            rrca
            rrca
            rrca
            and 0Fh
            ld (noise_vol), a
            jp .next
.slide:                             ; B8+s n vd lo hi
            sub 0B8h
            call voice_ix
            ld a, (hl)
            inc hl
            call note_freq
            ld (ix + VS_F), e
            ld (ix + VS_F + 1), d
            ld a, (hl)
            inc hl
            ld b, a
            and 0Fh
            ld (ix + VS_DEC), a
            ld (ix + VS_CNT), a
            ld a, b
            rrca
            rrca
            rrca
            rrca
            and 0Fh
            ld (ix + VS_VOL), a
            ld (ix + VS_FLOOR), 0
            ld a, (hl)
            inc hl
            ld (ix + VS_SLIDE), a
            ld a, (hl)
            inc hl
            ld (ix + VS_SLIDE + 1), a
            jp .next

; lecsengés, csúszás, majd az operandusok frissítése
voices:
            ld ix, vstate
            ld b, 3
.v:
            ld l, (ix + VS_F)
            ld h, (ix + VS_F + 1)
            ld e, (ix + VS_SLIDE)
            ld d, (ix + VS_SLIDE + 1)
            add hl, de
            ld (ix + VS_F), l
            ld (ix + VS_F + 1), h
            ld a, (ix + VS_DEC)
            or a
            jr z, .nod
            dec (ix + VS_CNT)
            jr nz, .nod
            ld (ix + VS_CNT), a
            ld a, (ix + VS_VOL)
            cp (ix + VS_FLOOR)
            jr z, .nod
            jr c, .nod
            dec (ix + VS_VOL)
.nod:
            ld de, 8
            add ix, de
            djnz .v
            ld a, (noise_dec)       ; a zaj lecsengése (0-ig)
            or a
            jr z, .nn
            ld hl, noise_cnt
            dec (hl)
            jr nz, .nn
            ld (hl), a
            ld a, (noise_vol)
            or a
            jr z, .nn
            dec a
            ld (noise_vol), a
.nn:
            ld hl, (vstate + 0 * 8 + VS_F)
            ld (f1 + 1), hl
            ld hl, (vstate + 1 * 8 + VS_F)
            ld (f2 + 1), hl
            ld hl, (vstate + 2 * 8 + VS_F)
            ld (f3 + 1), hl
            ld a, (vstate + 0 * 8 + VS_VOL)
            ld (v1 + 1), a
            ld a, (vstate + 1 * 8 + VS_VOL)
            ld (v2 + 1), a
            ld a, (vstate + 2 * 8 + VS_VOL)
            ld (v3 + 1), a
            ld a, (noise_vol)
            ld (v5 + 1), a
            ret

; ---- változók ---------------------------------------------------------------
ptr:        dw 0
loop_ptr:   dw 0
wait:       dw 0
done:       db 0
noise_vol:  db 0
noise_dec:  db 0
noise_cnt:  db 0
vstate:     ds 3 * 8
            align 256
mixtab:     ds 64                   ; a keverőtábla a 06h többi bitjével

song:       incbin "build/song.bin"
prog_end:
