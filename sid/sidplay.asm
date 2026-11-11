; ============================================================================
; sidplay.asm - C64 SID-zene lejátszó Videoton TVC 64k + TVC256k++ kártyára
; (sjasmplus). A lejátszó egyszer töltődik be (sidplay.cas), utána a kártya
; aktuális meghajtójáról (pendrive, PSRAM, flash) közvetlenül az eredeti .sid
; fájlt olvassa be, átalakítás nélkül. A fejlécet a TVC dolgozza fel, a zene
; 6502-es lejátszórutinját egy Z80-as 6502-emulátor (cpu6502.asm) futtatja.
; A SID-regiszterek írása a kártya vSID-jére megy ($E0..$F8 regiszterek).
;
; Kell: TVC 64k (a U3 RAM is), TVC256k++ kártya az 1..3. vagy 0. slotban.
;
; Memória: a 6502 64 KB-os címtere 256 bájtos lapokban, igény szerint
; foglalva: a U3 ($C000-$FFFF), a beolvasott fájl fölötti szabad RAM a HIMEM
; alá, végül a .sid fájl helye (a lapokba másolás után).
; A $D000-$DFFF tartomány I/O: a $D400-$D7FF írása a SID-be megy, az olvasás
; egy árnyéklapról jön (OSC3/ENV3 képkockánként frissítve a kártyáról).
;
; Fájlnév megadása: "zene" (a .sid kiterjesztést hozzáteszi), "zene.sid",
; vagy "zene,3" (a 3. dal). Üres sor: vissza a BASIC-be.
; ============================================================================

P_PAGING    equ 02h
P_KBDROW    equ 03h
P_KBDIN     equ 58h
V_PAGING    equ 0003h
V_PORT03    equ 0B11h
IRQVEC      equ 0038h
V_HIMEM     equ 0B19h
IO_PARAM    equ 0D900h          ; a kártya IO RAM-ja a slot IOMEM-jében
IO_RESULT   equ 0DA00h
IO_ATTR     equ 0DB00h
REG_MSC     equ 0D6h            ; REG_USB_MSC_CMD
REG_DRIVE   equ 0C5h
CHUNK       equ 1530            ; legfeljebb 6*256-2 bájt olvasásonként
PAGE_RUN    equ 0B0h            ; U0 U1 U2 U3 (a ROM IT-je SYS-re vált és visszaállítja)
KEYMASK     equ 28h             ; 7. sor: b3 = ESC, b5 = SPACE

V_PORT05    equ 0B12h           ; a 05h port tükre (b5: hang-IT, b4: hangjel)
P_PITCHLO   equ 04h
P_PITCHHI   equ 05h
P_ITCLR     equ 07h
P_TGRESET   equ 5Bh             ; olvasás: a hanggenerátor alaphelyzetbe
P_CRTCSEL   equ 70h
P_CRTCDAT   equ 71h
VBI_X       equ 3897            ; 195312,5 / 50,1245 Hz (PAL C64 képkocka)
CIA_DEFAULT equ 4025h           ; a kernal CIA1 időzítője (~60 Hz)

REG_VSID    equ 0E0h
SID_REGS    equ 25

            include "cas.inc"

start:
            assert start < 10000
            ld (saved_sp), sp
            ld sp, stack_top
            push ix
            push iy
            call main
            pop iy
            pop ix
            ld sp, (saved_sp)
            ret

; ---- szöveg kiírása (ROM: RST 30h / 21h = EDITOR karakterkiírás, C) -----------------
prstr:      ld a, (hl)
            or a
            ret z
            push hl
            ld c, a
            rst 30h
            db 21h
            pop hl
            inc hl
            jr prstr

; 32 bájtos PSID szövegmező kiírása (0 vagy a mező vége zárja), majd sorvége
prfield:    ld b, 32
.l:         ld a, (hl)
            or a
            jr z, .e
            cp 20h
            jr c, .n
            cp 7Fh
            jr c, .ok
.n:         ld a, '?'
.ok:        push hl
            push bc
            ld c, a
            rst 30h
            db 21h
            pop bc
            pop hl
            inc hl
            djnz .l
.e:         ld hl, s_crlf
            jr prstr

; HL = szám (0..65535) kiírása tízes számrendszerben
prnum:      ld de, numbuf + 5
            xor a
            ld (de), a
.l:         dec de
            push de
            ld c, 10
            call div16
            pop de
            add a, '0'
            ld (de), a
            ld a, h
            or l
            jr nz, .l
            ex de, hl
            jr prstr
; HL = HL / C, A = maradék
div16:      xor a
            ld b, 16
.l:         add hl, hl
            rla
            cp c
            jr c, .n
            sub c
            inc l
.n:         djnz .l
            ret

; ---- főprogram -------------------------------------------------------------
main:
            ; kártya keresése: a regiszterválasztó port visszaolvasható
            ld hl, slot_order
.slot:      ld a, (hl)
            cp 0FFh
            jr z, .nocard
            inc hl
            ld c, a
            ld a, 55h
            out (c), a
            in a, (c)
            cp 55h
            jr nz, .slot
            ld a, 0AAh
            out (c), a
            in a, (c)
            cp 0AAh
            jr z, .found
            jr .slot
.nocard:    ld hl, s_nocard
            call prstr
            ld hl, 1
            ret
.found:     ld a, c
            ld (sid_reset.psel1 + 1), a       ; a portcímek a kódba
            ld (wslow_v.psel2 + 1), a
            ld (wslow_A.psel4 + 1), a
            ld (play_file.psel3 + 1), a
            inc a
            ld (sid_reset.pdat1 + 1), a
            ld (wslow_v.pdat2 + 1), a
            ld (wslow_A.pdat4 + 1), a
            ld (play_file.pdat3 + 1), a
            inc a
            ld c, a
            xor a
            out (c), a              ; nincs automatikus léptetés
            ld a, c
            sub 2
            ld (card_base), a
            sub 10h                 ; slot * 10h -> slot * 40h (a 03h port 6-7. bitje)
            add a, a
            add a, a
            ld (card_slot6), a
            ld a, (V_HIMEM + 1)     ; a beolvasási puffer vége: a HIMEM alatt
            cp 0C0h
            jr c, .him
            ld a, 0C0h
.him:       dec a
            ld (pool_top), a        ; eddig foglalhatók lapok
            sub 2                   ; a fájl a lapra igazításhoz feljebb csúszhat
            ld (buf_limit + 1), a
            xor a
            ld (buf_limit), a
            ld hl, s_title
            call prstr
.loop:      call list_dir
            ld hl, s_prompt
            call prstr
            call read_line
            jr z, .quit
            call parse_name
            call load_file
            jr c, .loop
.play:      call play_file
            ld a, l
            cp 5                    ; dalváltás: újra beolvassuk a fájlt
            jr nz, .loop
            call load_file
            jr c, .loop
            jr .play
.quit:      ld hl, 0
            ret

; ---- egy beolvasott .sid lejátszása (sidbuf .. sidend) ----------------------
play_file:
            ; PSID fejléc (nagy-endián mezők)
            ld a, (sidbuf + 1)
            cp 'S'
            jr nz, .badfile
            ld a, (sidbuf + 2)
            cp 'I'
            jr nz, .badfile
            ld a, (sidbuf + 3)
            cp 'D'
            jr z, .okfile
.badfile:   ld hl, s_badfile
            call prstr
            ld hl, 2
            ret
.okfile:
            ld hl, s_name
            call prstr
            ld hl, sidbuf + 16h
            call prfield
            ld hl, s_author
            call prstr
            ld hl, sidbuf + 36h
            call prfield
            ld hl, s_rel
            call prstr
            ld hl, sidbuf + 56h
            call prfield

            ld ix, sidbuf
            ld h, (ix + 6)
            ld l, (ix + 7)
            ld de, sidbuf
            add hl, de              ; HL = az adatok eleje
            ld d, (ix + 8)
            ld e, (ix + 9)          ; DE = betöltési cím
            ld a, d
            or e
            jr nz, .hasload
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
.hasload:   ld (data_ptr), hl
            ld (load_addr), de
            ex de, hl
            ld hl, (sidend)
            or a
            sbc hl, de
            ld (data_len), hl
            ld h, (ix + 0Ah)
            ld l, (ix + 0Bh)
            ld a, h
            or l
            jr nz, .hasinit
            ld hl, (load_addr)
.hasinit:   ld (init_addr), hl
            ld h, (ix + 0Ch)
            ld l, (ix + 0Dh)
            ld (play_addr), hl
            ld a, (ix + 0Fh)        ; dalok száma
            ld (songs), a
            ld a, (ix + 11h)        ; kezdő dal
            or a
            jr nz, .hassong
            inc a
.hassong:   ld (song), a
            ld a, (song_req)        ; a fájlnév után megadott dal
            or a
            jr z, .nosongreq
            ld hl, songs
            cp (hl)
            jr z, .songok
            jr nc, .nosongreq
.songok:    ld (song), a
.nosongreq:

            ld hl, s_info
            call prstr
            ld hl, (load_addr)
            call prhex
            ld hl, s_dash
            call prstr
            ld hl, (load_addr)
            ld de, (data_len)
            add hl, de
            dec hl
            call prhex
            ld hl, s_song
            call prstr
            ld a, (song)
            ld l, a
            ld h, 0
            call prnum
            ld hl, s_slash
            call prstr
            ld a, (songs)
            ld l, a
            ld h, 0
            call prnum
            ld hl, s_keys
            call prstr

            ld a, (V_PORT05)
            ld (saved_p05), a
            ld a, (V_PAGING)
            ld (saved_paging), a
            call calc_speed         ; a fejlécből, mielőtt a helyére csúszik a zene
            di
            ld a, PAGE_RUN
            ld (V_PAGING), a
            out (P_PAGING), a
            ld hl, IRQVEC           ; saját IT-kezelő (a ROM-é ~5000 ciklus)
            ld de, irq_save
            ld bc, 3
            ldir
            ld a, 0C3h
            ld (IRQVEC), a
            ld hl, irq_handler
            ld (IRQVEC + 1), hl
            ld a, 1
            ld (irq_on), a
            ei
            call load_image
            jr nc, .loaded
            call stop_all
            ld hl, s_nomem
            call prstr
            ld hl, 3
            ret
.loaded:
            call install_stubs
            call sid_reset

            ; init: A = dal - 1
            ld a, (song)
            dec a
            ld (rA), a
            xor a
            ld (rX), a
            ld (rY), a
            ld (fC), a
            ld (fV), a
            ld (fD), a
            ld (rF), a              ; N = 0, Z = 0
            ld a, 04h
            ld (fI), a
            ld a, 0FFh
            ld (rS), a
            ld a, 2Fh
            ld (ZPG + 0), a
            ld a, 37h
            ld (ZPG + 1), a
            ld hl, (init_addr)
            xor a                   ; a CIA1 A időzítőjét az init írhatja
            ld (cia_lo), a
            ld (cia_hi), a
            ld a, 150               ; legfeljebb 3 másodperc
            call call_jsr

            ; lejátszócím: a fejlécből, vagy az IT-vektor ($0314, $FFFE)
            ld hl, (play_addr)
            ld a, h
            or l
            jr nz, .jsrmode
            ld hl, 0314h
            call rd16
            ld a, h
            or l
            jr z, .hwvec
            ld de, 0EA31h
            or a
            sbc hl, de
            add hl, de
            jr z, .hwvec
            ld (play_addr), hl
            ld a, 2                 ; kernal-féle IT: P, A, X, Y a veremben
            jr .mode
.hwvec:     ld hl, 0FFFEh
            call rd16
            ld a, h
            or l
            jr nz, .hw
            call stop_all
            ld hl, s_noplay
            call prstr
            ld hl, 4
            ret
.hw:        ld (play_addr), hl
            ld a, 1                 ; hardveres IT: P a veremben, RTI
            jr .mode
.jsrmode:   xor a
.mode:      ld (play_mode), a
            call timer_start
            xor a
            ld (cia_dirty), a

; ---- időzítő-IT-nként a lejátszó (VBI: 50,12 Hz, CIA: a zene tempója) ------
.frame:     ld a, (pending)         ; van kiszolgálatlan időzítő-IT?
            or a
            jr nz, .go
            halt
            jr .frame
.go:        di                      ; ha egy hívás kicsúszott, a következők behozzák
            ld a, (pending)
            dec a
            cp 3
            jr c, .pc
            ld a, 2
.pc:        ld (pending), a
            ei
            ld hl, it_cnt           ; minden it_div. IT-re
            dec (hl)
            jr nz, .frame
            ld a, (it_div)
            ld (hl), a
            ld a, REG_VSID + 1Bh    ; OSC3, ENV3 az árnyéklapra
.psel3:      out (0), a
.pdat3:      in a, (0)
            ld (IOSH + 1Bh), a
            ld (IOSH + 3Bh), a
            ld a, (play_mode)
            ld hl, (play_addr)
            or a
            jr nz, .irq
            ld a, 8
            call call_jsr
            jr .keys
.irq:       call call_irq
.keys:      ld a, (cia_dirty)       ; a zene átírta a CIA időzítőt
            or a
            call nz, timer_update
            ld hl, key_cnt          ; a billentyűk csak minden 8. hívásnál
            dec (hl)
            jp nz, .frame
            ld (hl), 8
            call read_keys
            cp KEYMASK
            jr nz, .esc
            call read_song_key      ; számbillentyű / nyilak: másik dal
            or a
            jr z, .frame
            ld hl, songs
            cp (hl)
            jr z, .sok
            jr nc, .frame
.sok:       ld hl, song
            cp (hl)
            jr z, .frame
            ld (song_req), a
            call stop_all
.krel:      halt                    ; megvárjuk, hogy elengedjék
            call read_song_key
            or a
            jr nz, .krel
            ld hl, 5
            ret
.esc:       call stop_all
.rel:       halt                    ; megvárjuk, hogy elengedjék
            call read_keys
            cp KEYMASK
            jr nz, .rel
            ld hl, 0
            ret

stop_all:   call sid_reset
            di
            ld a, (saved_paging)
            ld (V_PAGING), a
            out (P_PAGING), a
            ld a, (irq_on)          ; a ROM IT-kezelője vissza
            or a
            jr z, .i
            xor a
            ld (irq_on), a
            ld hl, irq_save
            ld de, IRQVEC
            ld bc, 3
            ldir
.i:         ld a, (timer_on)        ; a hang-IT ki, a kurzor-IT vissza
            or a
            jr z, .t
            xor a
            ld (timer_on), a
            ld a, (saved_p05)
            ld (V_PORT05), a
            out (P_PITCHHI), a
            ld a, 0Ah
            out (P_CRTCSEL), a
            ld a, 03h
            out (P_CRTCDAT), a
.t:         ei
            ret

; saját IT-kezelő a lejátszás alatt: nyugtáz, számol
irq_handler:
            push af
            out (P_ITCLR), a
            ld a, (ticks)
            inc a
            ld (ticks), a
            ld a, (pending)
            inc a
            ld (pending), a
            ld a, (emu_on)          ; őrkutya: a 6502-es kód túl sokáig fut?
            or a
            jr z, .r
            push hl
            ld a, (ticks)
            ld hl, wd_start
            sub (hl)
            pop hl
.wd_lim:    cp 0
            jr nc, .to
.r:         pop af
            ei
            ret
.to:        xor a
            ld (emu_on), a
            ld sp, (emu_sp)         ; az emu_run hívójához térünk vissza
            ei
            jp emu_timeout

; ---- időzítő: a hanggenerátor IT-je (195312,5 / (4096 - n) Hz) ---------------
; A képkocka-IT (a CRTC kurzor-IT-je) közös állapotbitet használ a hang-IT-vel,
; ezért közben tiltva van (CRTC R10 = 23h, mint a ROM magnórutinjában).
; A PSID fejléc speed mezőjének a dalhoz tartozó bitje: 0 = VBI (PAL 50,12 Hz),
; 1 = a CIA1 A időzítője (985248 / (T + 1) Hz; ha az init nem írta: 60 Hz).
calc_speed:
            ld a, (song)            ; bit = dal - 1 (32 fölött a 31.)
            dec a
            cp 32
            jr c, .b
            ld a, 31
.b:         ld c, a
            srl a
            srl a
            srl a
            ld e, a
            ld a, 15h
            sub e
            ld e, a
            ld d, 0
            ld hl, sidbuf
            add hl, de
            ld a, c
            and 7
            inc a
            ld b, a
            ld a, (hl)
.s:         rrca
            djnz .s
            ld a, 0
            rla
            ld (cia_mode), a
            ret
timer_start:
            ld a, 1
            ld (timer_on), a
            xor a
            ld (pending), a
timer_update:
            xor a
            ld (cia_dirty), a
            ld a, (cia_mode)
            or a
            ld hl, VBI_X
            jr z, .x
            ld hl, (cia_lo)         ; x = (T + 1) * 12992 / 65536
            ld a, h
            or l
            jr nz, .t
            ld hl, CIA_DEFAULT
.t:         inc hl
            ld de, 12992
            call mul16              ; DEHL = HL * DE
            ex de, hl               ; HL = a felső szó
.x:         ld c, 1                 ; IT-osztó: x / k <= 4090
.k:         push hl
            push bc
            call div16
            ld de, 4091
            or a
            sbc hl, de
            pop bc
            pop hl
            jr c, .kok
            inc c
            jr .k
.kok:       ld a, c
            ld (it_div), a
            ld (it_cnt), a
            call div16              ; HL = x / k
            ld a, h
            or a
            jr nz, .big
            ld a, l
            cp 2
            jr nc, .big
            ld hl, 2
.big:       ex de, hl               ; n = 4096 - x / k
            ld hl, 4096
            or a
            sbc hl, de
            di
            ld a, l
            out (P_PITCHLO), a
            ld a, (saved_p05)
            and 0C0h                ; magnómotorok
            or 20h                  ; hang-IT, hangjel ki (b4 = 0)
            or h
            ld (V_PORT05), a
            out (P_PITCHHI), a
            ld a, 0Ah               ; a kurzor-IT tiltása
            out (P_CRTCSEL), a
            ld a, 23h
            out (P_CRTCDAT), a
            in a, (P_TGRESET)
            out (P_ITCLR), a
            ei
            ret

; DEHL = HL * DE (előjel nélkül)
mul16:      ld b, h
            ld c, l
            ld hl, 0
            ld a, 16
.l:         add hl, hl
            ex de, hl
            adc hl, hl
            ex de, hl
            jr nc, .n
            add hl, bc
            jr nc, .n
            inc de
.n:         dec a
            jr nz, .l
            ret

; A = a lenyomott dalválasztó billentyű szerinti dal (0: nincs):
; 1-9, 0 = 10. dal, jobbra/balra nyíl: következő/előző
read_song_key:
            ld c, 0
            call read_row
            ld hl, row0map
            call .scan
            ret nz
            ld c, 1
            call read_row
            ld hl, row1map
            call .scan
            ret nz
            ld c, 8
            call read_row
            ld b, a
            ld a, (song)
            bit 5, b                ; jobbra
            jr z, .next
            bit 6, b                ; balra
            jr z, .prev
            xor a
            ret
.next:      inc a
            ret
.prev:      dec a
            ret
.scan:      cpl
            ld b, 8
.l:         rrca
            jr nc, .n
            ld e, a
            ld a, (hl)
            or a
            ret nz
            ld a, e
.n:         inc hl
            djnz .l
            xor a
            ret
row0map:    db 5, 3, 2, 0, 6, 0, 1, 4       ; a 0. sor bitjei
row1map:    db 0, 8, 9, 0, 0, 0, 10, 7      ; az 1. sor bitjei

; A = a C. billentyűsor (0 = lenyomva)
read_row:   di
            ld a, (V_PORT03)
            and 0F0h
            or c
            out (P_KBDROW), a
            in a, (P_KBDIN)
            ld b, a
            ld a, (V_PORT03)
            out (P_KBDROW), a
            ei
            ld a, b
            ret

; A = a billentyűzet 7. sorának ESC/SPACE bitjei
read_keys:  di
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

; HL kiírása 4 hexa jeggyel
prhex:      ld de, numbuf
            ld a, h
            call .byte
            ld a, l
            call .byte
            xor a
            ld (de), a
            ld hl, numbuf
            jp prstr
.byte:      push af
            rrca
            rrca
            rrca
            rrca
            call .nib
            pop af
.nib:       and 0Fh
            add a, '0'
            cp '9' + 1
            jr c, .d
            add a, 7
.d:         ld (de), a
            inc de
            ret

; SID regiszterek nullázása
sid_reset:  ld b, SID_REGS
            ld c, REG_VSID
.l:         ld a, c
.psel1:      out (0), a
            xor a
.pdat1:      out (0), a
            inc c
            djnz .l
            ret

; ---- 6502 memória ----------------------------------------------------------
; RT: lefoglalatlan lap -> ZEROPG (nullák), $D0-$DF -> IOSH. WT: 0 (lassú út).
mem_init:
            ld hl, RT
.rt:        ld (hl), ZEROPG >> 8
            inc l
            jr nz, .rt
            ld hl, WT
.wt:        ld (hl), 0
            inc l
            jr nz, .wt
            ld hl, RT + 0D0h
            ld b, 16
.io:        ld (hl), IOSH >> 8
            inc l
            djnz .io
            ld a, ZPG >> 8
            ld (RT + 0), a
            ld (WT + 0), a
            ld a, STKPG >> 8
            ld (RT + 1), a
            ld (WT + 1), a
            ld hl, ZPG              ; ZPG, STKPG, ZEROPG, IOSH nullázása
            ld de, ZPG + 1
            ld bc, 4 * 256 - 1
            ld (hl), 0
            ldir
            xor a
            ld (INV + (ZPG >> 8)), a
            inc a
            ld (INV + (STKPG >> 8)), a
            ; a lapkészlet: U3, majd a zene fölött a HIMEM-ig
            ld hl, pool_ranges
            ld (hl), 0C0h
            inc hl
            ld (hl), 0FFh
            inc hl
            ld a, (sidend + 1)
            inc a
            ld (hl), a
            inc hl
            ld a, (pool_top)
            ld (hl), a
            dec hl
            cp (hl)                 ; üres tartomány?
            jr nc, .r2
            ld (hl), 1              ; üres: 1 > 0
            inc hl
            ld (hl), 0
            dec hl
.r2:        inc hl
            inc hl
            ld (hl), 0              ; a lista vége
            ld hl, pool_ranges
            ld (pool_ptr), hl
            ld a, 1
            ld (pool_cur), a
            xor a
            ld (pool_end), a
            ret

; lap foglalása a 6502 A. lapjához: A = a Z80-as lap (Z = 1: elfogyott)
; megőrzi: BC, DE
alloc_page:
            push de
            push bc
            ld e, a
.try:       ld a, (pool_end)
            ld hl, pool_cur
            cp (hl)
            jr nc, .ok              ; cur <= end
            ld hl, (pool_ptr)
.next:      ld a, (hl)
            or a
            jr z, .fail
            ld (pool_cur), a
            inc hl
            ld a, (hl)
            ld (pool_end), a
            inc hl
            ld (pool_ptr), hl
            jr .try
.ok:        ld a, (hl)
            ld d, a
            inc a
            jr nz, .noend           ; 0FFh után vége a tartománynak
            ld (pool_end), a        ; (0 < 1)
            inc a
.noend:     ld (pool_cur), a
            ld h, d                 ; a lap nullázása
            ld l, 0
            ld b, l
.z:         ld (hl), b
            inc l
            jr nz, .z
            ld h, RT >> 8
            ld l, e
            ld (hl), d
            inc h
            ld (hl), d              ; WT = RT + 256
            ld h, INV >> 8
            ld l, d
            ld (hl), e
            ld a, d
            or a
            pop bc
            pop de
            ret
.fail:      xor a
            pop bc
            pop de
            ret

; a .sid adatainak bemásolása a 6502 lapjaira; Cy = 1: nincs elég memória
load_image:
            ; A zene a pufferben marad: annyival feljebb csúszik (< 256 bájt), hogy
            ; a Z80-as cím alsó bájtja a 6502-es címével egyezzen. Így a lapjai a
            ; Z80 memóriájában is folytonosak (a PC INC DE-vel léptethető).
            ld a, (load_addr)
            ld hl, data_ptr
            sub (hl)
            ld c, a
            ld b, 0                 ; BC = eltolás
            ld hl, (data_ptr)
            add hl, bc
            ld (img_z80), hl
            ld a, c
            or a
            jr z, .nomove
            ld hl, (data_ptr)
            ld de, (data_len)
            add hl, de
            dec hl                  ; a forrás vége
            push hl
            add hl, bc
            ex de, hl               ; DE = a cél vége
            pop hl
            ld bc, (data_len)
            lddr
.nomove:    ld hl, (img_z80)        ; az első lap eleje a zenéig: 0
            ld a, l
            or a
            jr z, .nz1
            ld b, a
            ld l, 0
.z1:        ld (hl), 0
            inc l
            djnz .z1
.nz1:       ld hl, (img_z80)
            ld de, (data_len)
            add hl, de
            ld (sidend), hl
            ld a, l                 ; az utolsó lap maradéka: 0
            or a
            jr z, .nz2
.z2:        ld (hl), 0
            inc l
            jr nz, .z2
.nz2:       call mem_init
            ld hl, (load_addr)
            ld c, h                 ; C = 6502-es lap
            ld de, (data_len)
            add hl, de
            dec hl
            ld a, h
            ld (img_last), a
            ld a, (img_z80 + 1)
            ld b, a                 ; B = Z80-as lap
.pg:        ld a, c
            cp 2
            jr c, .skip             ; a nullás lap és a verem helye fix
            ld h, INV >> 8
            ld l, b
            ld (hl), c
            call is_iopage
            jr z, .skip             ; $D4-$D7: SID
            ld h, RT >> 8
            ld l, c
            ld (hl), b
            inc h
            ld (hl), b
.skip:      ld a, (img_last)
            cp c
            jr z, .done
            inc c
            inc b
            jr .pg
.done:      or a
            ret

; Z = 1, ha az A. lap a SID I/O tartománya ($D4-$D7)
is_iopage:  cp 0D4h
            jr c, .no
            cp 0D8h
            jr nc, .no
            cp a
            ret
.no:        or 1
            ret

; a kernal IT-kezelő kilépési pontjai: PLA TAY PLA TAX PLA RTI
install_stubs:
            ld hl, 0EA31h
            call .stub
            ld hl, 0EA81h
            call .stub
            ld hl, 0FEBCh
.stub:      ld a, h                 ; csak ha a lap üres (nem a zenéé)
            ld d, WT >> 8
            ld e, a
            ld a, (de)
            or a
            ret nz                  ; a zene lapja: nem nyúlunk hozzá
            ld a, h
            push hl
            call alloc_page
            pop hl
            ret z
            ld d, a
            ld e, l
            ld hl, stub_code
            ld bc, 6
            ldir
            ret
stub_code:  db 68h, 0A8h, 68h, 0AAh, 68h, 40h

; HL = a 6502-es (HL) szó
rd16:       ld a, l
            ld l, h
            ld h, RT >> 8
            ld h, (hl)
            ld l, a
            ld a, (hl)
            inc l
            ld h, (hl)
            ld l, a
            ret

; ---- a 6502-es kód hívása ------------------------------------------------
; JSR-ként: HL = cím, A = időkorlát (képkocka)
call_jsr:   call set_wd
            ld a, (rS)
            ld (stop_s), a
            sub 2
            ld (rS), a
            jr emu_run
; IT-ként: HL = cím; play_mode 1: PC, P; 2: PC, P, A, X, Y (kernal)
call_irq:   ld a, 8
            call set_wd
            ld a, (rS)
            ld (stop_s), a
            ld e, a
            ld d, STKPG >> 8
            xor a
            ld (de), a
            dec e
            ld (de), a
            dec e
            push hl
            call getp_saved
            pop hl
            ld (de), a
            dec e
            ld a, (play_mode)
            cp 2
            jr nz, .hw
            ld a, (rA)
            ld (de), a
            dec e
            ld a, (rX)
            ld (de), a
            dec e
            ld a, (rY)
            ld (de), a
            dec e
.hw:        ld a, e
            ld (rS), a
            ld a, 04h               ; I = 1
            ld (fI), a
            jr emu_run
getp_saved: ld a, (fC)
            ld ixl, a
            ld a, (rF)
            ld l, a
            push hl
            pop af
            jp getp

; A = időkorlát (időzítő-IT-ben)
set_wd:     ld (irq_handler.wd_lim + 1), a
            ld a, (ticks)
            ld (wd_start), a
            ld a, 1
            ld (emu_on), a
            ret

; HL = a 6502-es PC; a regiszterek a változókból
emu_run:    ld (emu_sp), sp
            ld e, l
            ld l, h
            ld h, RT >> 8
            ld d, (hl)
            ld a, (rA)
            ld b, a
            ld a, (rX)
            ld c, a
            ld a, (rY)
            ld ixh, a
            ld a, (fC)
            ld ixl, a
            ld a, (rF)
            ld l, a
            push hl
            pop af
            jp emu_next

emu_exit:   ld a, 0                 ; (a jelzők megmaradnak)
            jr emu_save
emu_brk:    ld a, 1
            jr emu_save
emu_timeout:
            ld a, 2
emu_save:   push af
            pop hl                  ; H = állapot, L = jelzők
            xor a
            ld (emu_on), a
            ld a, l
            ld (rF), a
            ld a, h
            ld (emu_status), a
            ld a, ixl
            ld (fC), a
            ld a, b
            ld (rA), a
            ld a, c
            ld (rX), a
            ld a, ixh
            ld (rY), a
            ret

; ---- írás lassú útja: L = a 6502-es lap, A = alsó bájt ----------------------
; Kimenet: HL = írható Z80-as cím, A = L (a hívó LD L,A-t hajt végre)
wslow_A:    ld h, a                 ; gyors út: STA a SID-be ($D400-$D7FF)
            ld a, l
            and 0FCh
            cp 0D4h
            jr nz, .gen
            ld a, h
            and 1Fh
            cp SID_REGS
            jr nc, .scr
            add a, REG_VSID
.psel4:     out (0), a
            ld a, b
.pdat4:     out (0), a
.scr:       ld hl, SCRATCH
            ld a, l
            ret
.gen:       ld a, h
            push af
            ld a, b
            jr wslow_v
wslow_X:    push af
            ld a, c
            jr wslow_v
wslow_Y:    push af
            ld a, ixh
            jr wslow_v
wslow_SAX:  push af
            ld a, b
            and c
wslow_v:    ld h, a                 ; H = az írandó érték
            pop af
            push bc
            ld c, a                 ; C = alsó bájt
            ld a, l
            cp 0D0h
            jr c, ws_ram
            cp 0E0h
            jr nc, ws_ram
            cp 0DCh                 ; CIA1 A időzítő ($DC04/$DC05): a tempó
            jr nz, .nocia
            ld a, c
            and 0Fh
            cp 4
            jr z, .c4
            cp 5
            jr nz, ws_scratch
            ld a, h
            ld (cia_hi), a
            jr .cd
.c4:        ld a, h
            ld (cia_lo), a
.cd:        ld a, 1
            ld (cia_dirty), a
            jr ws_scratch
.nocia:     ld a, l
            call is_iopage
            jr nz, ws_scratch
            ld a, c
            and 1Fh
            cp SID_REGS
            jr nc, ws_scratch
            add a, REG_VSID
.psel2:      out (0), a
            ld a, h
.pdat2:      out (0), a
ws_scratch: pop bc
            ld hl, SCRATCH
            ld a, l
            ret
; olvasás-módosítás-írás: az I/O-ba nem ír
wslow_R:    push bc
            ld c, a
            ld a, l
            cp 0D0h
            jr c, ws_ram
            cp 0E0h
            jr c, ws_scratch
ws_ram:     ld a, l
            call alloc_page
            jr z, ws_scratch
            ld h, a
            ld l, c
            ld a, c
            pop bc
            ret

; ---- a kártya fájlkezelése (REG_USB_MSC_CMD, paraméterek az IO RAM-ban) -------
; az IO RAM ($D800-$DFFF) a kártya slotjának IOMEM-jében: U3 = IOMEM, a 03h
; port 6-7. bitje a slot; közben tiltott IT
io_on:      di
            push bc
            ld a, (V_PAGING)
            or 0C0h
            out (P_PAGING), a
            ld a, (V_PORT03)
            and 3Fh
            ld b, a
            ld a, (card_slot6)
            or b
            out (P_KBDROW), a
            pop bc
            ret
io_off:     ld a, (V_PAGING)
            out (P_PAGING), a
            ld a, (V_PORT03)
            out (P_KBDROW), a
            ei
            ret

; A = parancs; a kártya a regisztert 0-ra (kész) vagy hibakód + 80h-ra állítja
; ki: A = 0 és Z = 1, ha sikerült
card_cmd:   push bc
            ld b, a
            ld a, (card_base)
            ld c, a
            ld a, REG_MSC
            out (c), a
            inc c
            out (c), b
            dec c
.p:         ld a, REG_MSC
            out (c), a
            inc c
            in a, (c)
            dec c
            or a
            jr z, .ok
            cp 80h
            jr c, .p
.ok:        pop bc
            or a
            ret

; HL -> az IO RAM paraméterterülete (4 bájtos fájl/könyvtár azonosító)
put_handle: call io_on
            ld de, IO_PARAM
            ld bc, 4
            ldir
            jp io_off

; az aktuális könyvtár .sid fájljainak kiírása
list_dir:   call io_on
            ld hl, s_dot
            ld de, IO_PARAM
            ld bc, 3
            ldir
            call io_off
            ld a, 05h               ; MSC_OPENDIR
            call card_cmd
            ret nz
            call io_on
            ld hl, IO_RESULT
            ld de, dirh
            ld bc, 4
            ldir
            call io_off
            ld hl, s_files
            call prstr
.next:      ld hl, dirh
            call put_handle
            ld a, 07h               ; MSC_READDIR
            call card_cmd
            jr nz, .close
            call io_on
            ld a, (IO_RESULT)
            or a
            jr z, .end
            cp 63
            jr c, .len
            ld a, 63
.len:       ld c, a
            ld b, 0
            ld hl, IO_RESULT + 1
            ld de, entbuf
            ldir
            xor a
            ld (de), a
            ld a, (IO_ATTR)
            ld b, a
            call io_off
            bit 4, b                ; könyvtár
            jr nz, .next
            ld hl, entbuf
            call is_sid
            jr nz, .next
            ld hl, entbuf
            call prstr
            ld hl, s_sep
            call prstr
            jr .next
.end:       call io_off
.close:     ld hl, dirh
            call put_handle
            ld a, 06h               ; MSC_CLOSEDIR
            call card_cmd
            ld hl, s_crlf
            jp prstr

; Z = 1, ha a HL-en kezdődő (0-végű) név ".sid"-re végződik (kisbetű/nagybetű)
is_sid:     ld b, 0
.len:       ld a, (hl)
            or a
            jr z, .e
            inc hl
            inc b
            jr .len
.e:         ld a, b
            cp 5
            jr c, .no
            ld de, -4
            add hl, de
            ld de, s_ext
            ld b, 4
.c:         ld a, (hl)
            cp 'A'
            jr c, .lc
            cp 'Z' + 1
            jr nc, .lc
            or 20h
.lc:        ex de, hl
            cp (hl)
            ex de, hl
            ret nz
            inc hl
            inc de
            djnz .c
            ret                     ; Z = 1
.no:        or 1
            ret

; egy sor beolvasása a namebuf-ba (ROM: RST 30h / A1h = EDITOR karakter be)
; Z = 1: üres sor
read_line:  ld hl, namebuf
            ld b, 0
.l:         push hl
            push bc
            rst 30h
            db 0A1h
            ld a, c
            pop bc
            pop hl
            cp 13
            jr z, .e
            cp 20h
            jr c, .l
            ld e, a
            ld a, b
            cp 40
            jr nc, .l
            ld (hl), e
            inc hl
            inc b
            jr .l
.e:         ld (hl), 0
            ld a, b
            or a
            ret

; a név végéről a szóközök, ",dal" -> song_req, kiterjesztés nélkül + ".sid"
parse_name: xor a
            ld (song_req), a
            ld hl, namebuf
            ld c, 0                 ; volt-e pont
.f:         ld a, (hl)
            or a
            jr z, .end
            cp ','
            jr z, .num
            cp ' '
            jr z, .cut
            cp '.'
            jr nz, .n
            inc c
.n:         inc hl
            jr .f
.cut:       ld (hl), 0
.skip:      inc hl                  ; a szóköz után jöhet még ",dal"
            ld a, (hl)
            or a
            jr z, .end0
            cp ','
            jr nz, .skip
.num:       ld (hl), 0
            inc hl
            ld b, 0
.d:         ld a, (hl)
            sub '0'
            jr c, .dn
            cp 10
            jr nc, .dn
            ld e, a
            ld a, b
            add a, a
            add a, a
            add a, b
            add a, a
            add a, e
            ld b, a
            inc hl
            jr .d
.dn:        ld a, b
            ld (song_req), a
.end0:
.end:       ld a, c
            or a
            jr nz, .len
            ld hl, namebuf          ; nincs pont: + ".sid"
            xor a
            ld bc, 0
            cpir
            dec hl
            ex de, hl
            ld hl, s_ext
            ld bc, 5
            ldir
.len:       ld hl, namebuf
            ld b, 0
.l:         ld a, (hl)
            or a
            jr z, .le
            inc hl
            inc b
            jr .l
.le:        ld a, b
            ld (name_len), a
            ret

; a namebuf nevű fájl beolvasása a sidbuf-ba; Cy = 1: hiba (kiírva)
load_file:  call io_on
            ld hl, IO_PARAM
            ld (hl), 01h            ; FA_READ
            inc hl
            ld (hl), 0
            inc hl
            ld a, (name_len)
            ld (hl), a
            inc hl
            ex de, hl
            ld hl, namebuf
            ld c, a
            ld b, 0
            ldir
            call io_off
            ld a, 01h               ; MSC_FOPENFILE
            call card_cmd
            jr z, .opened
            ld hl, s_notfound
            call prstr
            scf
            ret
.opened:    call io_on
            ld hl, IO_RESULT
            ld de, fileh
            ld bc, 4
            ldir
            call io_off
            ld hl, sidbuf
            ld (dest), hl
.rd:        ld hl, fileh
            call put_handle
            call io_on
            ld hl, CHUNK
            ld (IO_PARAM + 4), hl
            call io_off
            ld a, 03h               ; MSC_FREAD (a fájl végén hibát is adhat)
            call card_cmd
            jr nz, .eof
            call io_on
            ld bc, (IO_RESULT)
            ld a, b
            or c
            jr z, .eofio
            ld hl, (dest)
            add hl, bc
            ex de, hl
            ld hl, (buf_limit)
            or a
            sbc hl, de
            jr c, .big
            ld hl, IO_RESULT + 2
            ld de, (dest)
            push bc
            ldir
            pop bc
            ld (dest), de
            call io_off
            ld hl, CHUNK
            or a
            sbc hl, bc
            jr z, .rd               ; teljes darab: van még
            jr .eof
.big:       call io_off
            call .close
            ld hl, s_toolarge
            call prstr
            scf
            ret
.eofio:     call io_off
.eof:       call .close
            ld hl, (dest)
            ld (sidend), hl
            ld de, sidbuf + 7Ch     ; legalább egy fejléc
            or a
            sbc hl, de
            ret nc
            ld hl, s_badfile
            call prstr
            scf
            ret
.close:     ld hl, fileh
            call put_handle
            ld a, 02h               ; MSC_FCLOSEFILE
            jp card_cmd

            include "cpu6502.asm"

; ---- adatok ----------------------------------------------------------------
slot_order: db 20h, 30h, 40h, 10h, 0FFh     ; a kártya portjai: 1., 2., 3., 0. slot
s_crlf:     db 13, 10, 0
s_nocard:   db "Nincs TVC256k++ kartya!", 13, 10, 0
s_badfile:  db "Nem PSID/RSID fajl!", 13, 10, 0
s_nomem:    db "Nincs eleg memoria!", 13, 10, 0
s_noplay:   db "Nincs lejatszo cim!", 13, 10, 0
s_author:   db "Szerzo: ", 0
s_rel:      db "Kiadva: ", 0
s_info:     db "Betoltes: $", 0
s_name:     db "Nev:    ", 0
s_title:    db 13, 10, "SID lejatszo - TVC256k++", 13, 10, 0
s_files:    db "SID fajlok: ", 0
s_prompt:   db 13, 10, "Fajlnev (,dal) - Enter: kilepes", 13, 10, 0
s_notfound: db "Nincs ilyen fajl!", 13, 10, 0
s_toolarge: db "Tul nagy fajl!", 13, 10, 0
s_sep:      db "  ", 0
s_dot:      db 2, "./"
s_ext:      db ".sid", 0
card_base:  db 0
saved_p05:  db 0
timer_on:   db 0
cia_mode:   db 0
cia_dirty:  db 0
cia_lo:     db 0
cia_hi:     db 0
            assert cia_hi == cia_lo + 1
it_div:     db 1
it_cnt:     db 1
card_slot6: db 0
buf_limit:  dw 0
sidend:     dw 0
song_req:   db 0
dirh:       ds 4
fileh:      ds 4
dest:       dw 0
name_len:   db 0
namebuf:    ds 48
entbuf:     ds 64
s_dash:     db "-$", 0
s_song:     db "  dal: ", 0
s_slash:    db "/", 0
s_keys:     db 13, 10, "1-9,0: dal  <- ->: elozo/kov.", 13, 10
            db "ESC/SPACE: vissza a listahoz", 13, 10, 0

saved_sp:   dw 0
saved_paging: db 0
data_ptr:   dw 0
data_len:   dw 0
load_addr:  dw 0
init_addr:  dw 0
play_addr:  dw 0
play_mode:  db 0
songs:      db 0
song:       db 0
img_first:  db 0
img_last:   db 0
src:        dw 0
dst6502:    dw 0
remain:     dw 0
pool_ranges: ds 7
pool_ptr:   dw 0
pool_cur:   db 0
pool_end:   db 0
numbuf:     ds 6
emu_status: db 0
; a 6502 állapota
rA:         db 0
rX:         db 0
rY:         db 0
rS:         db 0
            db STKPG >> 8           ; LD HL,(rS): a verem Z80-as címe
rF:         db 0                    ; a Z80 jelzői (S = N, Z)
fC:         db 0
fV:         db 0
fD:         db 0
fI:         db 0
stop_s:     db 0
ticks:      db 0
emu_on:     db 0
emu_sp:     dw 0
key_cnt:    db 1
pending:    db 0
wd_start:   db 0
irq_on:     db 0
irq_save:   ds 3
pool_top:   db 0
img_z80:    dw 0
SCRATCH:    db 0

            ds 256
stack_top:
            align 256
RT:         ds 256
WT:         ds 256
            assert WT == RT + 256
ZPG:        ds 256
STKPG:      ds 256
ZEROPG:     ds 256
IOSH:       ds 256
INV:        ds 256                  ; Z80-as lap -> 6502-es lap

prog_end:
sidbuf:                             ; ide olvassuk a .sid fájlt (a HIMEM-ig)
