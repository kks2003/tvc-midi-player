; ============================================================================
; player.asm - megszakításos MIDI-lejátszó Videoton TVC-re (sjasmplus)
;
; A kimenet egy kész .cas fájl (lásd build.sh): 128 bájtos CAS-fejléc,
; 16 bájtos BASIC programfejléc (autorun), két BASIC sor
;     1 PRINT "<cím>"
;     2 X=USR(<start>)
; majd a lejátszó gépi kódja és a dal adatai (build/song.bin, midi2tvc.py).
;
; Hardver (tvcdoc: tvchardver.md, tvcrom.md, ROM-lista):
;   04h        PITCH b0..b7
;   05h        b0..b3 PITCH b8..b11, b4 hangjel (1 = oszcillátor, 0 = állandó
;              szint -> DAC), b5 hang-IT, b6/b7 magnómotorok
;   06h        b2..b5 amplitúdó (0..15), b0..b1 videómód, b7 nyomtató strobe
;   07h        írás: kurzor/hang IT törlése
;   59h        olvasás: függő IT-k, b4 = 0: kurzor/hang IT
;   0B12h/0B13h a 05h/06h port tükre a rendszerváltozókban
;   f = 195312,5 / (4096 - PITCH) Hz
;
; Időzítés: a ROM kurzor-IT-je (képkockánként egy, ~49,7 Hz). A 0038h-n lévő
; RAM-beli belépési pont első 3 bájtját "JP irq"-re cseréljük; a saját
; kezelőnk után a ROM eredeti kezelője is lefut (ugyanazzal a 8 bájttal, amit
; a 0038h-ról elmentettünk), így a billentyűzet, a TIME stb. tovább megy.
;
; Leállítás: ESC vagy SPACE, vagy a dal vége (ha nem ismétel).
; ============================================================================

P_PITCHLO   equ 04h
P_PITCHHI   equ 05h
P_AMP       equ 06h
P_KBDROW    equ 03h
P_KBDIN     equ 58h
P_IRQST     equ 59h

V_PORT03    equ 0B11h
V_PORT05    equ 0B12h
V_PORT06    equ 0B13h
V_SNDACT    equ 0B14h       ; SND_ACTIVE: a ROM SOUND időtartam-kezelése

IRQVEC      equ 0038h

; billentyűzet 7. sor: b3 = ESC, b5 = SPACE (0 = lenyomva)
KEYMASK     equ 28h

; ---- dal adatformátum (midi2tvc.py) ---------------------------------------
; +0   flags: b0 = ismétlés
; +1   arpeggio sebesség (tick / lépés, >= 1)
; +2   lecsengés (tick / hangerőlépés, 0 = nincs)
; +3   lecsengés alsó szintje (0..15)
; +4   dw ismétlési pont (az eseménylista elejéhez képest)
; +6   dw a dobkészlet helye a dal elejéhez képest (0 = nincs)
; +8   128 x dw PITCH (MIDI hangjegy -> 12 bites PITCH)
; +264 eseménylista:
;   00..7F  hang (MIDI hangjegy), egyszólamú
;   80      szünet
;   82..84  akkord: utána 2..4 hangjegy, arpeggióval szól
;   90..9F  hangerő (a következő hangoktól)
;   A0 lo hi  várakozás lo+256*hi tick (>= 1)
;   A1..BF g  dobütés: a dobkészlet (A-A1h). eleme, g = gyengítés (0..15)
;   C0..FE  várakozás 1..63 tick
;   FF      vége (ismétléskor ugrás az ismétlési pontra)
;
; Dobkészlet: db darabszám, darabszám x dw (a dal elejéhez képest), majd
; dobonként tickenkénti lépések, 4 bájt: hangerő (FF = vége), PITCH lo,
; PITCH hi (FF = nincs hang), zaj (b4..b7 hangerő, b0..b3 hossz ~1,2 ms-os
; egységekben). A dobütés néhány tickre átveszi a csatornát; közben a dallam
; állapota tovább halad, és a dob végén a dallam aktuális hangja szól tovább.
SONG_FLAGS  equ song+0
SONG_ARP    equ song+1
SONG_DECAY  equ song+2
SONG_FLOOR  equ song+3
SONG_LOOP   equ song+4
SONG_KIT    equ song+6
PITCH_TAB   equ song+8
SONG_EVENTS equ song+8+256

            include "cas.inc"

; ---- lejátszó -------------------------------------------------------------
start:
            assert start < 10000
            di
            ld hl, IRQVEC           ; az eredeti IT-belépés mentése
            ld de, orig_irq
            ld bc, 8
            ldir
            xor a
            ld (V_SNDACT), a        ; a ROM ne kapcsolja ki a hangot
            ld (done), a
            call init_song
            ld a, 0C3h              ; JP irq
            ld (IRQVEC), a
            ld hl, irq
            ld (IRQVEC + 1), hl
            ei
.loop:
            halt
            ld a, (done)
            or a
            jr nz, .stop
            call read_keys
            cp KEYMASK
            jr z, .loop
.stop:
            di
            ld hl, orig_irq         ; az IT-belépés visszaállítása
            ld de, IRQVEC
            ld bc, 3
            ldir
            call sound_off
            ei
.release:                           ; megvárjuk, hogy elengedjék a gombot
            halt
            call read_keys
            cp KEYMASK
            jr nz, .release
            ld hl, 0
            ret

; A = a billentyűzet 7. sorának ESC/SPACE bitjei (KEYMASK: nincs lenyomva)
read_keys:
            di
            ld a, (V_PORT03)
            and 0F0h
            or 07h
            out (P_KBDROW), a
            in a, (P_KBDIN)
            and KEYMASK
            ld b, a
            ld a, (V_PORT03)
            out (P_KBDROW), a
            ei
            ld a, b
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
            ld (arp_n), a
            ld (cur_vol), a
            ld (drum_on), a
            ld a, 12
            ld (note_vol), a
            ld a, (SONG_ARP)
            or a
            jr nz, .arp_ok
            inc a
.arp_ok:    ld (arp_speed), a
            ret

; ---- megszakítás ------------------------------------------------------------
irq:
            push af
            in a, (P_IRQST)
            bit 4, a                ; 0: kurzor/hang IT (a képkocka-IT)
            jr nz, .chain
            push bc
            push de
            push hl
            call tick
            call drum_step
            pop hl
            pop de
            pop bc
.chain:
            pop af
            jp orig_irq             ; az eredeti ROM-kezelő (törli az IT-t)

; ---- egy tick (képkocka) ----------------------------------------------------
tick:
            ld hl, (wait)
            ld a, h
            or l
            jr z, .parse
            dec hl
            ld (wait), hl
            ld a, h
            or l
            jp nz, effects
.parse:
            ld hl, (ptr)
.next:
            ld a, (hl)
            inc hl
            cp 80h
            jr c, .note
            jr z, .rest
            cp 90h
            jr c, .chord
            cp 0A0h
            jr c, .vol
            jr z, .lwait
            cp 0C0h
            jp c, .drum             ; A1..BF: dobütés
            cp 0FFh
            jr z, .end
            sub 0BFh                ; C0..FE -> 1..63
            ld (ptr), hl
            ld l, a
            ld h, 0
            ld (wait), hl
            ret
.lwait:
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld (ptr), hl
            ld (wait), de
            ret
.drum:
            sub 0A1h                ; a dob sorszáma
            ld c, (hl)              ; gyengítés
            inc hl
            push hl
            call drum_start
            pop hl
            jp .next
.vol:
            and 0Fh
            ld (note_vol), a
            jr .next
.rest:
            xor a
            ld (arp_n), a
            ld (cur_vol), a
            push hl
            call set_vol
            pop hl
            jr .next
.note:
            ld (arp_notes), a
            ld b, 1
            jr .start_notes
.chord:
            and 07h                 ; 2..4 hang
            ld b, a
            ld c, a
            ld de, arp_notes
.copy:      ld a, (hl)
            ld (de), a
            inc hl
            inc de
            djnz .copy
            ld b, c                 ; B = a hangok száma
.start_notes:
            ld a, b
            ld (arp_n), a
            xor a
            ld (arp_i), a
            ld a, (arp_speed)
            ld (arp_cnt), a
            ld a, (SONG_DECAY)
            ld (env_cnt), a
            push hl
            ld a, (arp_notes)
            call set_note
            ld a, (note_vol)
            ld (cur_vol), a
            call set_vol
            pop hl
            jp .next
.end:
            ld a, (SONG_FLAGS)
            rrca
            jr nc, .finish
            ld hl, (loop_ptr)
            jp .next
.finish:
            dec hl
            ld (ptr), hl            ; a vége-jelen marad
            call sound_off
            ld a, 1
            ld (done), a
            ret

; arpeggio és lecsengés a várakozás alatti tickekben
effects:
            ld a, (arp_n)
            cp 2
            jr c, .env
            ld hl, arp_cnt
            dec (hl)
            jr nz, .env
            ld a, (arp_speed)
            ld (hl), a
            ld a, (arp_n)
            ld b, a
            ld a, (arp_i)
            inc a
            cp b
            jr c, .idx
            xor a
.idx:       ld (arp_i), a
            ld e, a
            ld d, 0
            ld hl, arp_notes
            add hl, de
            ld a, (hl)
            call set_note
.env:
            ld a, (SONG_DECAY)
            or a
            ret z
            ld a, (arp_n)
            or a
            ret z
            ld hl, env_cnt
            dec (hl)
            ret nz
            ld a, (SONG_DECAY)
            ld (hl), a
            ld a, (SONG_FLOOR)
            ld b, a
            ld a, (cur_vol)
            cp b
            ret z
            ret c
            dec a
            ld (cur_vol), a
            jp set_vol

; ---- dob ---------------------------------------------------------------------
; A = a dob sorszáma, C = gyengítés
drum_start:
            ld b, a
            ld hl, (SONG_KIT)
            ld a, h
            or l
            ret z                   ; nincs dobkészlet
            ld de, song
            add hl, de
            ld a, b
            cp (hl)
            ret nc                  ; nincs ilyen dob
            inc hl
            add a, a
            ld e, a
            ld d, 0
            add hl, de
            ld e, (hl)
            inc hl
            ld d, (hl)
            ld hl, song
            add hl, de
            ld (drum_ptr), hl
            ld a, c
            ld (drum_att), a
            ld a, 1
            ld (drum_on), a
            ret

; a futó dob egy lépése (minden tickben, a dallam után)
drum_step:
            ld a, (drum_on)
            or a
            ret z
            ld hl, (drum_ptr)
            ld a, (hl)
            inc hl
            cp 0FFh
            jr z, .end
            call atten
            ld (drum_vol), a
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld a, (hl)
            inc hl
            ld (drum_ptr), hl
            ld (drum_noise), a
            ld a, d
            inc a
            jr z, .notone
            ld a, e                 ; a dob hangja
            out (P_PITCHLO), a
            ld a, (V_PORT05)
            and 0C0h
            or 10h
            or d
            ld (V_PORT05), a
            out (P_PITCHHI), a
            ld a, (drum_vol)
            jr .tvol
.notone:    xor a
            ld (drum_vol), a
.tvol:      call hw_vol
            ld a, (drum_noise)      ; zaj
            and 0Fh
            ret z
            ld b, a                 ; B = hossz
            ld a, (drum_noise)
            rrca
            rrca
            rrca
            rrca
            and 0Fh
            call atten
            or a
            ret z
            add a, a
            add a, a
            ld c, a                 ; C = amplitúdó (06h b2..b5)
            ld a, (V_PORT06)
            and 0C3h
            ld d, a                 ; D = a 06h többi bitje
            ld a, (V_PORT05)
            and 0EFh                ; b4 = 0: az amplitúdóregiszter DAC
            out (P_PITCHHI), a
            ld hl, (lfsr)
.unit:      push bc
            ld b, 48                ; 48 x 79 ciklus = ~1,2 ms
.sample:    srl h                   ; 16 bites Galois-LFSR (B400h)
            rr l
            sbc a, a
            ld e, a
            and 0B4h
            xor h
            ld h, a
            ld a, e
            and c
            or d
            out (P_AMP), a
            djnz .sample
            pop bc
            djnz .unit
            ld (lfsr), hl
            ld a, (V_PORT05)        ; az oszcillátor vissza
            out (P_PITCHHI), a
            ld a, (drum_vol)
            jp hw_vol
.end:
            xor a
            ld (drum_on), a
            call hw_tone            ; a dallam hangja szól tovább
            ld a, (cur_vol)
            jp hw_vol

; A = max(0, A - gyengítés)
atten:
            push bc
            ld b, a
            ld a, (drum_att)
            ld c, a
            ld a, b
            sub c
            jr nc, .ok
            xor a
.ok:        pop bc
            ret
drum_code_end:

; ---- hardver ----------------------------------------------------------------
; A = MIDI hangjegy (0..127): a dallam PITCH-e; dob közben csak eltároljuk
set_note:
            ld l, a
            ld h, 0
            add hl, hl
            ld de, PITCH_TAB
            add hl, de
            ld a, (hl)
            ld (sh_lo), a
            inc hl
            ld a, (hl)
            ld (sh_hi), a
            ld a, (drum_on)
            or a
            ret nz
; a dallam eltárolt PITCH-e a hardverre, oszcillátor be
hw_tone:
            ld a, (sh_lo)
            out (P_PITCHLO), a
            ld a, (sh_hi)
            ld b, a
            ld a, (V_PORT05)
            and 0C0h                ; magnómotorok maradnak, hang-IT tiltva
            or 10h                  ; hangjel engedélyezve
            or b                    ; PITCH b8..b11
            ld (V_PORT05), a
            out (P_PITCHHI), a
            ret

; A = a dallam hangereje (0..15); dob közben nem írjuk ki
set_vol:
            ld b, a
            ld a, (drum_on)
            or a
            ret nz
            ld a, b
; A = hangerő (0..15) a hardverre
hw_vol:
            add a, a
            add a, a
            ld b, a
            ld a, (V_PORT06)
            and 0C3h
            or b
            ld (V_PORT06), a
            out (P_AMP), a
            ret

sound_off:
            xor a
            ld (arp_n), a
            ld (drum_on), a
            ld (cur_vol), a
            call hw_vol
            ld a, (V_PORT05)
            and 0C0h                ; hangjel és hang-IT ki
            ld (V_PORT05), a
            out (P_PITCHHI), a
            ret

; ---- változók ---------------------------------------------------------------
orig_irq:   ds 8                    ; a 0038h eredeti 8 bájtja (itt fut le)
ptr:        dw 0
loop_ptr:   dw 0
wait:       dw 0
done:       db 0
note_vol:   db 0
cur_vol:    db 0
env_cnt:    db 0
arp_speed:  db 1
arp_cnt:    db 0
arp_n:      db 0
arp_i:      db 0
arp_notes:  ds 4
sh_lo:      db 0                    ; a dallam PITCH-e (dob közben)
sh_hi:      db 0
drum_on:    db 0
drum_ptr:   dw 0
drum_att:   db 0
drum_vol:   db 0
drum_noise: db 0
lfsr:       dw 0ACE1h

song:       incbin "build/song.bin"
prog_end:
