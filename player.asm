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
BASIC_TEXT  equ 19EFh

; billentyűzet 7. sor: b3 = ESC, b5 = SPACE (0 = lenyomva)
KEYMASK     equ 28h

; ---- dal adatformátum (midi2tvc.py) ---------------------------------------
; +0   flags: b0 = ismétlés
; +1   arpeggio sebesség (tick / lépés, >= 1)
; +2   lecsengés (tick / hangerőlépés, 0 = nincs)
; +3   lecsengés alsó szintje (0..15)
; +4   dw ismétlési pont (az eseménylista elejéhez képest)
; +6   dw tartalék
; +8   128 x dw PITCH (MIDI hangjegy -> 12 bites PITCH)
; +264 eseménylista:
;   00..7F  hang (MIDI hangjegy), egyszólamú
;   80      szünet
;   82..84  akkord: utána 2..4 hangjegy, arpeggióval szól
;   90..9F  hangerő (a következő hangoktól)
;   A0 lo hi  várakozás lo+256*hi tick (>= 1)
;   C0..FE  várakozás 1..63 tick
;   FF      vége (ismétléskor ugrás az ismétlési pontra)
SONG_FLAGS  equ song+0
SONG_ARP    equ song+1
SONG_DECAY  equ song+2
SONG_FLOOR  equ song+3
SONG_LOOP   equ song+4
PITCH_TAB   equ song+8
SONG_EVENTS equ song+8+256

; ---- .cas fejléc ------------------------------------------------------------
            org BASIC_TEXT - 16 - 128
CAS_TOTAL   equ 16 + (prog_end - basic)
CAS_BLOCKS  equ (CAS_TOTAL + 127) / 128
cas_hdr:
            db 11h, 00h             ; nem pufferelt fájl, nem védett
            dw CAS_BLOCKS
            dw CAS_TOTAL - (CAS_BLOCKS - 1) * 128
            ds 128 - 6, 0
prg_hdr:
            db 00h, 01h             ; programfájl
            dw prog_end - basic     ; hossz (a gépi kóddal és a dallal együtt)
            db 0FFh                 ; autorun
            ds 10, 0
            db 00h                  ; változatszám

; ---- BASIC sorok ----------------------------------------------------------
basic:
            assert basic == BASIC_TEXT
line1:      db line2 - line1
            dw 1
            db 0DDh, ' "'           ; PRINT "
            incbin "build/title.bin", 0, 32
            db '"', 0FFh
line2:      db line_end - line2
            dw 2
            db 'X', 9Ah, "USR", 96h ; X=USR(
            db '0' + (start / 1000) % 10
            db '0' + (start / 100) % 10
            db '0' + (start / 10) % 10
            db '0' + start % 10
            db 95h, 0FFh            ; )
line_end:   db 00h                  ; a BASIC program vége
            ; A BASIC a záró 00 után kezdi a szimbólumtáblát (az X változó
            ; bejegyzése 12 bájt), ezért a gépi kód előtt üres sáv kell.
            ds 64, 0

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
            jr c, .next             ; A1..BF: fenntartott, átlépjük
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

; ---- hardver ----------------------------------------------------------------
; A = MIDI hangjegy (0..127): PITCH beállítása, oszcillátor be
set_note:
            ld l, a
            ld h, 0
            add hl, hl
            ld de, PITCH_TAB
            add hl, de
            ld a, (hl)
            out (P_PITCHLO), a
            inc hl
            ld a, (V_PORT05)
            and 0C0h                ; magnómotorok maradnak, hang-IT tiltva
            or 10h                  ; hangjel engedélyezve
            or (hl)                 ; PITCH b8..b11
            ld (V_PORT05), a
            out (P_PITCHHI), a
            ret

; A = hangerő (0..15)
set_vol:
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
            call set_vol
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

song:       incbin "build/song.bin"
prog_end:
