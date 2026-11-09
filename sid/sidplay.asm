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
V_TIME      equ 0B1Dh
V_HIMEM     equ 0B19h
IO_PARAM    equ 0D900h          ; a kártya IO RAM-ja a slot IOMEM-jében
IO_RESULT   equ 0DA00h
IO_ATTR     equ 0DB00h
REG_MSC     equ 0D6h            ; REG_USB_MSC_CMD
REG_DRIVE   equ 0C5h
CHUNK       equ 1530            ; legfeljebb 6*256-2 bájt olvasásonként
PAGE_RUN    equ 0B0h            ; U0 U1 U2 U3 (a ROM IT-je SYS-re vált és visszaállítja)
KEYMASK     equ 28h             ; 7. sor: b3 = ESC, b5 = SPACE

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
            ld (play_file.psel3 + 1), a
            inc a
            ld (sid_reset.pdat1 + 1), a
            ld (wslow_v.pdat2 + 1), a
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
            call play_file
            jr .loop
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

            ld a, (V_PAGING)
            ld (saved_paging), a
            di
            ld a, PAGE_RUN
            ld (V_PAGING), a
            out (P_PAGING), a
            ei
            call mem_init
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
            ld (rN), a
            ld a, 04h
            ld (fI), a
            ld a, 1
            ld (rZ), a
            ld a, 0FFh
            ld (rS), a
            ld a, 2Fh
            ld (ZPG + 0), a
            ld a, 37h
            ld (ZPG + 1), a
            ld hl, (init_addr)
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

; ---- képkockánként a lejátszó --------------------------------------------
.frame:     halt
            ld a, REG_VSID + 1Bh    ; OSC3, ENV3 az árnyéklapra
.psel3:      out (0), a
.pdat3:      in a, (0)
            ld (IOSH + 1Bh), a
            ld (IOSH + 3Bh), a
            ld a, (play_mode)
            ld hl, (play_addr)
            or a
            jr nz, .irq
            ld a, 3
            call call_jsr
            jr .keys
.irq:       call call_irq
.keys:      call read_keys
            cp KEYMASK
            jr z, .frame
            call stop_all
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
            ei
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
            ; a lapkészlet: U3, a program fölött a verem alá, a .sid helye
            ld hl, pool_ranges
            ld (hl), 0C0h
            inc hl
            ld (hl), 0FFh
            inc hl
            ld a, (sidend + 1)
            inc a
            ld (hl), a
            inc hl
            ld a, (buf_limit + 1)
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
            ld a, sidbuf >> 8
            ld (hl), a
            inc hl
            ld a, (sidend + 1)
            dec a
            ld (hl), a
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
            ld hl, (load_addr)
            ld a, h
            ld (img_first), a
            ld de, (data_len)
            add hl, de
            dec hl
            ld a, h
            ld (img_last), a
            ld a, (img_first)
.pg:        ld c, a
            call is_iopage
            jr z, .skip
            ld h, WT >> 8
            ld l, c
            ld a, (hl)
            or a
            jr nz, .skip            ; már van (nullás lap, verem)
            ld a, c
            call alloc_page
            scf
            ret z
.skip:      ld a, (img_last)
            cp c
            jr z, .copy
            ld a, c
            inc a
            jr .pg
.copy:
            ; másolás lapdarabokban
            ld hl, (data_ptr)
            ld (src), hl
            ld hl, (load_addr)
            ld (dst6502), hl
            ld hl, (data_len)
            ld (remain), hl
.cp:        ld hl, (remain)
            ld a, h
            or l
            ret z                   ; Cy = 0 (or a)
            ld a, (dst6502)         ; n = min(remain, 256 - lo)
            neg
            ld c, a
            ld b, 0
            or a
            jr nz, .n
            inc b
.n:         ld hl, (remain)
            or a
            sbc hl, bc
            jr nc, .n2
            ld bc, (remain)
.n2:        ld hl, (remain)
            or a
            sbc hl, bc
            ld (remain), hl
            ld hl, (dst6502)
            ld a, h
            ld e, l
            ld h, WT >> 8
            ld l, a
            ld d, (hl)
            ld hl, (src)
            ld a, d
            or a
            jr z, .nocopy           ; I/O lap: kimarad
            push bc
            ldir
            pop bc
            jr .adv
.nocopy:    add hl, bc
.adv:       ld hl, (src)
            add hl, bc
            ld (src), hl
            ld hl, (dst6502)
            add hl, bc
            ld (dst6502), hl
            jr .cp

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
call_irq:   ld a, 3
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
getp_saved: push bc
            ld a, (rZ)
            ld c, a
            ld a, (rN)
            ld ixh, a
            call getp
            pop bc
            ret

set_wd:     ld b, a
            ld a, (V_TIME)
            add a, b
            ld (wd_cmp + 1), a
            ret

; HL = a 6502-es PC; a regiszterek a változókból
emu_run:    ld (pch - 1), hl        ; pcl, pch
            ld a, (rA)
            ld b, a
            ld a, (rZ)
            ld c, a
            ld a, (rN)
            ld ixh, a
            ld e, l
            ld l, h
            ld h, RT >> 8
            ld d, (hl)
            jp emu_next

emu_exit:   xor a
            jr emu_save
emu_brk:    ld a, 1
            jr emu_save
emu_timeout:
            ld a, 2
emu_save:   ld (emu_status), a
            ld a, b
            ld (rA), a
            ld a, c
            ld (rZ), a
            ld a, ixh
            ld (rN), a
            ret

; PC lapváltás (E túlcsordult): megőrzi A-t, HL-t
pcwrap:     push af
            push hl
            ld hl, pch
            inc (hl)
            ld l, (hl)
            ld h, RT >> 8
            ld d, (hl)
            pop hl
            pop af
            ret

; ---- írás lassú útja: L = a 6502-es lap, A = alsó bájt ----------------------
; Kimenet: HL = írható Z80-as cím, A = L (a hívó LD L,A-t hajt végre)
wslow_A:    push af
            ld a, b
            jr wslow_v
wslow_X:    push af
            ld a, (rX)
            jr wslow_v
wslow_Y:    push af
            ld a, (rY)
            jr wslow_v
wslow_SAX:  push af
            ld a, (rX)
            and b
wslow_v:    ld h, a                 ; H = az írandó érték
            pop af
            push bc
            ld c, a                 ; C = alsó bájt
            ld a, l
            cp 0D0h
            jr c, ws_ram
            cp 0E0h
            jr nc, ws_ram
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
s_keys:     db 13, 10, "ESC/SPACE: kilepes", 13, 10, 0

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
rZ:         db 0
rN:         db 0
fC:         db 0
fV:         db 0
fD:         db 0
fI:         db 0
stop_s:     db 0
pcl:        db 0
pch:        db 0
            assert pcl + 1 == pch
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

prog_end:
sidbuf:                             ; ide olvassuk a .sid fájlt (a HIMEM-ig)
