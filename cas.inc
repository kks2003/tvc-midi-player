; ============================================================================
; cas.inc - közös .cas / BASIC fejléc a lejátszókhoz (sjasmplus)
; A beemelő fájlban kell: start (a gépi kód belépési pontja), prog_end
; (a program vége), és a build/title.bin (32 bájtos cím).
; ============================================================================
BASIC_TEXT  equ 19EFh

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

