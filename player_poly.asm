; ============================================================================
; player_poly.asm - többszólamú MIDI-lejátszó Videoton TVC-re (sjasmplus)
;
; A hangoszcillátor helyett a 06h amplitúdóregiszter 4 bites DAC-ként szól
; (05h b4 = 0: a hangerő-szabályzó bemenetén állandó "1" szint van). A
; hangszámláló közben mintaóraként jár: a hang-IT (05h b5 = 1) minden
; mintánál megszakítást kér (195312,5 / osztó Hz, az osztó a dal fejlécében).
;
; A megszakítás (it_handler, ~253 ciklus a belépéssel együtt):
;   - 3 szólam: 16 bites fázisakkumulátor (IX, IY, HL'), a fázisnövekmény
;     önmódosító operandus (f1..f3)
;   - szólamonként egy 256 bájtos tábla a fázis felső bájtjával címezve
;     (w1..w3: a tábla lapja); a tábla a hullámformát és a hangerőt is
;     tartalmazza (hullámforma x 8 hangerőszint, induláskor számoljuk ki)
;   - a három érték összege (0..45) egy 64 bájtos keverőtáblán át (lágy
;     telítés, a dal adataiban) megy ki a 06h-ra
;   - TICKN mintánként (~50 Hz) a tick: ESC/SPACE, események, lecsengés,
;     hangcsúszás. Ez engedélyezett megszakítással fut, tehát a minták közben
;     is mennek: a hang nem áll meg, a hangmagasság pontos.
;
; Az ötlet (hang-IT mint mintaóra, hullámtáblák, a zenefeldolgozás a
; megszakításból, EI mellett) Szalontai Béla "Többcsatornás hanggeneráló
; programcsomag"-jából való (tvcdoc: sources/3 csatornás asm lejátszó, MIT).
;
; Lejátszás közben a ROM megszakításkezelője nem fut (a 0038h-n a mi
; kezelőnk van), a kurzor-IT tiltva; a végén minden visszaáll.
; A .cas fejléc és a BASIC indító sorok: cas.inc.
; ============================================================================

P_PITCHLO   equ 04h
P_PITCHHI   equ 05h
P_AMP       equ 06h
P_IRQCLR    equ 07h
P_KBDROW    equ 03h
P_KBDIN     equ 58h
P_CRTCREG   equ 70h
P_CRTCDAT   equ 71h

V_PORT03    equ 0B11h
V_PORT05    equ 0B12h
V_PORT06    equ 0B13h
V_HIMEM     equ 0B19h
IRQVEC      equ 0038h

KEYMASK     equ 28h                 ; 7. sor: b3 ESC, b5 SPACE (0 = lenyomva)
LEVELS      equ 8                   ; hangerőszint hullámformánként
MAX_SLOTS   equ 5

; ---- dal adatformátum (midi2tvc.py --mode poly) ---------------------------
; +0   flags: b0 = ismétlés
; +1   lecsengés (tick / hangerőlépés, 0 = nincs)
; +2   lecsengés alsó szintje
; +3   a mintaóra osztója (mintafrekvencia = 195312,5 / osztó)
; +4   dw ismétlési pont (az eseménylista elejéhez képest)
; +6   minta / tick
; +7   a hullámforma-helyek száma (1..5)
; +8   5 bájt: helyenként a hullámforma (0 négyszög, 1 impulzus 25%,
;      2 háromszög, 3 fűrész, 4 zaj)
; +13  3 bájt tartalék
; +16  64 bájt keverőtábla: összeg (0..45) -> kimenet (0..15)
; +80  128 x dw fázisnövekmény (MIDI hangjegy -> f * 65536 / mintafrekvencia)
; +336 eseménylista:
;   80+16*s+h  n        hang a szólamon (s = 0..2, h = hangerő 0..15), n = hangjegy
;   B0+s                a szólam elhallgat
;   B8+s n vd lo hi     csúszó / lecsengő hang (dob): n = kezdőhang, v/d hangerő
;                       és lecsengés (0-ig), lo hi = fázisnövekmény-változás / tick
;   BB+s h              a szólam hullámforma-helye (h = 0..4)
;   BF lo hi            várakozás lo+256*hi tick
;   C0..FE              várakozás 1..63 tick
;   FF                  vége (ismétléskor ugrás az ismétlési pontra)
SONG_FLAGS  equ song+0
SONG_DECAY  equ song+1
SONG_FLOOR  equ song+2
SONG_DIV    equ song+3
SONG_LOOP   equ song+4
SONG_TICKN  equ song+6
SONG_NSLOTS equ song+7
SONG_WAVES  equ song+8
SONG_MIX    equ song+16
SONG_FREQ   equ song+80
SONG_EVENTS equ song+336

; szólamonkénti állapot (9 bájt)
VS_F        equ 0                   ; dw fázisnövekmény
VS_SLIDE    equ 2                   ; dw változás / tick
VS_VOL      equ 4
VS_DEC      equ 5                   ; lecsengés (tick / lépés)
VS_CNT      equ 6
VS_FLOOR    equ 7
VS_SLOT     equ 8                   ; hullámforma-hely
VS_SIZE     equ 9

            include "cas.inc"

; ---- belépés ----------------------------------------------------------------
start:
            di
            call build_tables
            jr nc, .mem_ok
            ei                      ; nincs elég memória a tábláknak
            ld hl, -1
            ret
.mem_ok:
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
            ld a, (V_PORT03)        ; billentyűzet: a 7. sor marad kiválasztva
            and 0F0h
            or 07h
            out (P_KBDROW), a
            ld a, 10                ; a CRTC kurzor-IT tiltása (mint a ROM a
            out (P_CRTCREG), a      ; magnókezelésnél: 10. regiszter = 23h)
            ld a, 23h
            out (P_CRTCDAT), a
            ld hl, IRQVEC           ; a megszakítás a mi kezelőnkre ugrik
            ld de, saved_irq
            ld bc, 3
            ldir
            ld a, 0C3h
            ld (IRQVEC), a
            ld hl, it_handler
            ld (IRQVEC + 1), hl
            ld a, (SONG_TICKN)
            ld (tickn + 1), a
            call tick_work          ; az első események
            ld ix, 0
            ld iy, 0
            exx
            ld hl, 0
            ld a, (SONG_TICKN)
            ld e, a
            exx
            ld a, (SONG_DIV)        ; mintaóra: PITCH = 4096 - osztó
            neg
            out (P_PITCHLO), a
            ld a, (V_PORT05)
            and 0C0h
            or 2Fh                  ; hang-IT be, hangjel ki (DAC), PITCH b8..b11 = F
            out (P_PITCHHI), a
            in a, (5Bh)             ; a számlánc törlése
            out (P_IRQCLR), a
            ei
.wait:      halt
            ld a, (done)
            or a
            jr z, .wait

; ---- vége -------------------------------------------------------------------
            di
            ld a, (V_PORT05)        ; hang-IT ki
            and 0C0h
            ld (V_PORT05), a
            out (P_PITCHHI), a
            ld a, (V_PORT06)        ; csend
            and 0C3h
            ld (V_PORT06), a
            out (P_AMP), a
            ld hl, saved_irq
            ld de, IRQVEC
            ld bc, 3
            ldir
            ld a, 10                ; a kurzor-IT vissza
            out (P_CRTCREG), a
            ld a, 03h
            out (P_CRTCDAT), a
.release:   in a, (P_KBDIN)         ; megvárjuk, hogy elengedjék a gombot
            and KEYMASK
            cp KEYMASK
            jr nz, .release
            ld a, (V_PORT03)
            out (P_KBDROW), a
            out (P_IRQCLR), a
            ei
            ld hl, 0
            ret

; ---- mintamegszakítás -------------------------------------------------------
; árnyékregiszterek: HL' = 3. fázis, BC' munka, D' összeg, E' tickszámláló;
; IX, IY = 1. és 2. fázis.  Ciklus: 13 (IM 1) + 10 (JP) + 230
it_handler:
            ex af, af'              ; 4
            exx                     ; 4
            out (P_IRQCLR), a       ; 11
f1:         ld bc, 0                ; 10
            add ix, bc              ; 15
f2:         ld bc, 0                ; 10
            add iy, bc              ; 15
f3:         ld bc, 0                ; 10
            add hl, bc              ; 11
            ld c, ixh               ; 8
w1:         ld b, 0                 ; 7   a tábla lapja (hullámforma + hangerő)
            ld a, (bc)              ; 7
            ld d, a                 ; 4
            ld c, iyh               ; 8
w2:         ld b, 0                 ; 7
            ld a, (bc)              ; 7
            add a, d                ; 4
            ld d, a                 ; 4
            ld c, h                 ; 4
w3:         ld b, 0                 ; 7
            ld a, (bc)              ; 7
            add a, d                ; 4
            ld c, a                 ; 4
            ld b, high mixtab       ; 7
            ld a, (bc)              ; 7
            out (P_AMP), a          ; 11
            dec e                   ; 4
            jr z, tick_entry        ; 7
            exx                     ; 4
            ex af, af'              ; 4
            ei                      ; 4
            ret                     ; 10

; tick: a főregiszterekkel, engedélyezett megszakítással (a minták mennek)
tick_entry:
tickn:      ld e, 0                 ; minta / tick (induláskor írjuk be)
            exx
            ex af, af'
            push af
            ld a, (in_tick)         ; ha az előző tick még fut, kihagyjuk
            or a
            jr nz, .skip
            inc a
            ld (in_tick), a
            ei
            push bc
            push de
            push hl
            call tick_work
            pop hl
            pop de
            pop bc
            xor a
            ld (in_tick), a
.skip:
            pop af
            ei
            ret

tick_work:
            in a, (P_KBDIN)
            and KEYMASK
            cp KEYMASK
            jr z, .keys_ok
            ld a, 1
            ld (done), a
            ret
.keys_ok:
            call events
            jp voices

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
            ld (in_tick), a
            ld hl, vstate
            ld b, 3 * VS_SIZE
.clr:       ld (hl), a
            inc hl
            djnz .clr
            ret

; HL = a szólam állapota (A = 0..2); BC, DE marad
voice_hl:
            push de
            ld e, a
            add a, a
            add a, a
            add a, a
            add a, e                ; * 9
            ld e, a
            ld d, 0
            ld hl, vstate
            add hl, de
            pop de
            ret

; DE = a hangjegy (A) fázisnövekménye; HL marad
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

; ---- események --------------------------------------------------------------
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
            jp nc, .short
            cp 80h
            jr c, .next             ; 00..7F: fenntartott
            cp 0B0h
            jr c, .note
            cp 0B3h
            jp c, .off
            cp 0B8h
            jr c, .next
            cp 0BBh
            jp c, .slide
            cp 0BEh
            jp c, .wave
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
            ld c, (hl)              ; hangjegy
            inc hl
            push hl
            call voice_hl
            ld a, c
            call note_freq
            ld (hl), e              ; VS_F
            inc hl
            ld (hl), d
            inc hl
            xor a
            ld (hl), a              ; VS_SLIDE
            inc hl
            ld (hl), a
            inc hl
            ld a, b
            and 0Fh
            ld (hl), a              ; VS_VOL
            inc hl
            ld a, (SONG_DECAY)
            ld (hl), a              ; VS_DEC
            inc hl
            ld (hl), a              ; VS_CNT
            inc hl
            ld a, (SONG_FLOOR)
            ld (hl), a              ; VS_FLOOR
            pop hl
            jp .next
.off:
            sub 0B0h
            push hl
            call voice_hl
            ld de, VS_VOL
            add hl, de
            ld (hl), 0
            pop hl
            jp .next
.wave:                              ; BB+s h
            sub 0BBh
            ld c, (hl)
            inc hl
            push hl
            call voice_hl
            ld de, VS_SLOT
            add hl, de
            ld (hl), c
            pop hl
            jp .next
.slide:                             ; B8+s n vd lo hi
            sub 0B8h
            ld c, (hl)              ; hangjegy
            inc hl
            ld b, (hl)              ; vd
            inc hl
            push hl
            call voice_hl
            ld a, c
            call note_freq
            ld (hl), e              ; VS_F
            inc hl
            ld (hl), d
            inc hl
            ex de, hl               ; DE = VS_SLIDE
            pop hl
            ld a, (hl)
            inc hl
            ld (de), a
            inc de
            ld a, (hl)
            inc hl
            ld (de), a
            inc de
            ld a, b
            rrca
            rrca
            rrca
            rrca
            and 0Fh
            ld (de), a              ; VS_VOL
            inc de
            ld a, b
            and 0Fh
            ld (de), a              ; VS_DEC
            inc de
            ld (de), a              ; VS_CNT
            inc de
            xor a
            ld (de), a              ; VS_FLOOR = 0
            jp .next

; ---- lecsengés, csúszás, majd a megszakítás operandusai -------------------
voices:
            ld hl, vstate
            ld bc, w1 + 1
            call voice1
            ld bc, w2 + 1
            call voice1
            ld bc, w3 + 1
            call voice1
            ld hl, (vstate + 0 * VS_SIZE + VS_F)    ; egy-egy utasítás: a
            ld (f1 + 1), hl                         ; megszakítás nem lát
            ld hl, (vstate + 1 * VS_SIZE + VS_F)    ; félig átírt értéket
            ld (f2 + 1), hl
            ld hl, (vstate + 2 * VS_SIZE + VS_F)
            ld (f3 + 1), hl
            ret
; HL = a szólam állapota, BC = a táblalap operandusa; kilépéskor HL a következő
voice1:
            push bc
            ld e, (hl)              ; F += csúszás
            inc hl
            ld d, (hl)
            inc hl
            ld c, (hl)
            inc hl
            ld b, (hl)
            ex de, hl
            add hl, bc
            ex de, hl               ; DE = az új F, HL = VS_SLIDE + 1
            dec hl
            dec hl
            ld (hl), d
            dec hl
            ld (hl), e
            ld de, VS_VOL
            add hl, de              ; HL = VS_VOL
            ld a, (hl)
            ld c, a                 ; C = hangerő
            inc hl
            ld a, (hl)              ; VS_DEC
            inc hl                  ; VS_CNT
            or a
            jr z, .nodec
            dec (hl)
            jr nz, .nodec
            ld (hl), a
            inc hl                  ; VS_FLOOR
            ld a, c
            cp (hl)
            dec hl
            jr z, .nodec
            jr c, .nodec
            dec c
            dec hl
            dec hl
            ld (hl), c              ; VS_VOL
            inc hl
            inc hl
.nodec:
            inc hl                  ; VS_FLOOR
            inc hl                  ; VS_SLOT
            ld a, c                 ; lap: 0 (csend) vagy 1 + hely * 8 + szint
            or a
            jr z, .page
            inc a
            rrca
            and 0Fh                 ; szint 1..8
            ld c, a
            ld a, (hl)
            add a, a
            add a, a
            add a, a
            add a, c
.page:
            ld c, a
            ld a, (tab_base)
            add a, c
            inc hl                  ; a következő szólam
            pop de                  ; a táblalap operandusa
            ld (de), a
            ret

; ---- hullámtáblák -----------------------------------------------------------
; lap 0: csend; utána helyenként 8 lap (hangerőszint 1..8 -> csúcs 1,3,..15):
; érték = minta (0..255) * csúcs / 256, kerekítve.  CY = 1: nincs elég hely.
build_tables:
            ld hl, (song_len)       ; a táblák a program után, lapra igazítva
            ld de, song + 255
            add hl, de
            ld l, 0
            ld a, h
            ld (tab_base), a
            ld a, (SONG_NSLOTS)     ; lapok száma: 1 + helyek * 8
            add a, a
            add a, a
            add a, a
            inc a
            add a, h
            ld b, a                 ; B = a táblák utáni lap
            ld a, (V_HIMEM + 1)     ; a BASIC verme alatt maradjon 2 lap
            sub 2
            cp b
            ret c
            xor a                   ; lap 0: csend
.zero:      ld (hl), a
            inc l
            jr nz, .zero
            inc h
            ld ix, SONG_WAVES
            ld a, (SONG_NSLOTS)
            ld b, a
.slot:      push bc
            ld a, (ix + 0)
            ld (wave_id), a
            ld de, 0ACE1h           ; a zaj LFSR-je
            ld (lfsr), de
            ld c, 0                 ; C = index
.sample:    push hl
            call wave_sample        ; A = minta 0..255
            ld e, a
            ld d, 0                 ; DE = minta
            ld b, LEVELS
            push de
            pop iy                  ; IY = minta * csúcs (csúcs = 1)
.level:     push bc
            push iy
            pop bc
            ld a, c                 ; kerekítés: (minta * csúcs + 128) / 256
            add a, 80h
            ld a, b
            adc a, 0
            ld (hl), a
            inc h                   ; a következő szint lapja
            add iy, de
            add iy, de              ; csúcs += 2
            pop bc
            djnz .level
            pop hl
            inc l
            inc c
            jr nz, .sample
            ld a, h
            add a, LEVELS
            ld h, a
            inc ix
            pop bc
            djnz .slot
            or a
            ret

; A = a wave_id hullámforma C. mintája (0..255)
wave_sample:
            ld a, (wave_id)
            or a
            jr z, .square
            dec a
            jr z, .pulse
            dec a
            jr z, .triangle
            dec a
            jr z, .saw
            ld de, (lfsr)           ; zaj
            ld b, 8
.n:         srl d
            rr e
            jr nc, .nx
            ld a, d
            xor 0B4h
            ld d, a
.nx:        djnz .n
            ld (lfsr), de
            ld a, e
            ret
.square:    ld a, c
            rlca
            sbc a, a
            cpl                     ; 0..127: 255, 128..255: 0
            ret
.pulse:     ld a, c
            cp 64
            sbc a, a                ; 0..63: 255
            ret
.triangle:  ld a, c
            add a, a
            ret nc
            cpl                     ; 128..255: lefelé
            ret
.saw:       ld a, c
            ret

; ---- változók ---------------------------------------------------------------
; a dal hossza (a weboldal buildCas-a is ide írja be)
song_len:   dw song_end - song
saved_irq:  ds 3
tab_base:   db 0
wave_id:    db 0
lfsr:       dw 0
ptr:        dw 0
loop_ptr:   dw 0
wait:       dw 0
done:       db 0
in_tick:    db 0
vstate:     ds 3 * VS_SIZE
            align 256
mixtab:     ds 64                   ; a keverőtábla a 06h többi bitjével

song:       incbin "build/song.bin"
song_end:
prog_end:
