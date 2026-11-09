; ============================================================================
; sidplay.asm - C64 SID-zene lejátszó Videoton TVC 64k + TVC256k++ kártyára
; (sjasmplus). Az eredeti .sid (PSID) fájl változatlanul kerül a programba
; (build.sh), a TVC futás közben dolgozza fel a fejlécét, és a benne lévő
; 6502-es lejátszórutint egy Z80-as 6502-emulátorral (cpu6502.asm) futtatja.
; A SID-regiszterek írása a kártya vSID-jére megy ($E0..$F8 regiszterek).
;
; Kell: TVC 64k (a U3 RAM is), TVC256k++ kártya az 1..3. vagy 0. slotban.
;
; Memória: a 6502 64 KB-os címtere 256 bájtos lapokban, igény szerint
; foglalva: a U3 ($C000-$FFFF), a program fölötti szabad RAM a BASIC verem
; alá, végül a .sid fájl helye (a lapokba másolás után).
; A $D000-$DFFF tartomány I/O: a $D400-$D7FF írása a SID-be megy, az olvasás
; egy árnyéklapról jön (OSC3/ENV3 képkockánként frissítve a kártyáról).
;
; Visszatérési érték (X=USR(...)): 0 rendben (ESC/SPACE), 1 nincs kártya,
; 2 nem PSID/RSID fájl, 3 nincs elég memória, 4 nincs lejátszócím.
; ============================================================================

P_PAGING    equ 02h
P_KBDROW    equ 03h
P_KBDIN     equ 58h
V_PAGING    equ 0003h
V_PORT03    equ 0B11h
V_TIME      equ 0B1Dh
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

; ---- szöveg kiírása (ROM: RST 30h / 01 = karakter a C-ből) -----------------
prstr:      ld a, (hl)
            or a
            ret z
            push hl
            ld c, a
            rst 30h
            db 01h
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
            db 01h
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
            ld (main.psel3 + 1), a
            inc a
            ld (sid_reset.pdat1 + 1), a
            ld (wslow_v.pdat2 + 1), a
            ld (main.pdat3 + 1), a
            inc a
            ld c, a
            xor a
            out (c), a              ; nincs automatikus léptetés

            ; PSID fejléc (nagy-endián mezők)
            ld a, (sidfile + 1)
            cp 'S'
            jr nz, .badfile
            ld a, (sidfile + 2)
            cp 'I'
            jr nz, .badfile
            ld a, (sidfile + 3)
            cp 'D'
            jr z, .okfile
.badfile:   ld hl, s_badfile
            call prstr
            ld hl, 2
            ret
.okfile:
            ld hl, s_author
            call prstr
            ld hl, sidfile + 36h
            call prfield
            ld hl, s_rel
            call prstr
            ld hl, sidfile + 56h
            call prfield

            ld ix, sidfile
            ld h, (ix + 6)
            ld l, (ix + 7)
            ld de, sidfile
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
            ld hl, sidend
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
            ld a, (prog_end_page)
            ld (hl), a
            inc hl
            ld a, (saved_sp + 1)
            sub 2
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
            ld a, (sidfile_page)
            ld (hl), a
            inc hl
            ld a, (prog_end_page)
            sub 2
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
s_info:     db "Cim: $", 0
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
prog_end_page: db (prog_end >> 8) + 1
sidfile_page:  db (sidfile >> 8) + 1

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

sidfile:    incbin "build/tune.sid"
sidend:
prog_end:
