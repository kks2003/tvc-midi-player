; ============================================================================
; cpu6502.asm - GENERÁLT FÁJL (tools/gen6502.py), kézzel ne módosítsd!
; 6502-emulátor Z80-on a SID-lejátszóhoz.
; ============================================================================

; belépés: a regiszterek betöltve, DE = a PC (lásd sidplay.asm emu_run)
emu_next:
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)

; elágazás: A = eltolás, E = a következő utasítás alsó bájtja
branch_take:
            ld l,a
            add a,e
            ld e,a
            bit 7,l
            jr nz,.neg
            jr nc,.same
            ld hl,pch
            inc (hl)
            ld l,(hl)
            ld h,RT>>8
            ld d,(hl)
.same:
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
.neg:
            jr c,wd_check
            ld hl,pch
            dec (hl)
            ld l,(hl)
            ld h,RT>>8
            ld d,(hl)
; visszafelé ugrás: őrkutya (a ROM TIME számlálója)
wd_check:
            ld a,(0B1Dh)
wd_cmp:     cp 0
            jp z,emu_timeout
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)

; ADC/SBC: A = operandus
do_adc:
            ld l,a
            ld a,(fD)
            or a
            jr nz,.dec
            ld a,(fC)
            rra
            ld a,b
            adc a,l
            ld b,a
            ld c,a
            ld ixh,a
            push af
            pop hl
            ld a,l
            ld (fC),a
            ld (fV),a
            ret
.dec:
            ld a,(fC)
            rra
            ld a,b
            adc a,l
            daa
            ld b,a
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ret
do_sbc:
            ld l,a
            ld a,(fD)
            or a
            jr nz,.dec
            ld a,(fC)
            cpl
            rra
            ld a,b
            sbc a,l
            ld b,a
            ld c,a
            ld ixh,a
            ccf
            push af
            pop hl
            ld a,l
            ld (fC),a
            ld (fV),a
            ret
.dec:
            ld a,(fC)
            cpl
            rra
            ld a,b
            sbc a,l
            daa
            ld b,a
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ret

; a P regiszter összerakása A-ba (B és 5. bit = 1)
getp:
            ld a,ixh
            and 80h
            ld l,a
            ld a,(fV)
            and 4
            jr z,.nv
            set 6,l
.nv:        ld a,c
            or a
            jr nz,.nz
            set 1,l
.nz:        ld a,(fC)
            and 1
            or l
            ld l,a
            ld a,(fD)
            or l
            ld l,a
            ld a,(fI)
            or l
            or 30h
            ret
; A = P -> jelzők
setp:
            ld l,a
            and 80h
            ld ixh,a
            ld a,l
            and 40h
            rrca
            rrca
            rrca
            rrca
            ld (fV),a
            ld a,l
            and 08h
            ld (fD),a
            ld a,l
            and 04h
            ld (fI),a
            ld a,l
            and 01h
            ld (fC),a
            ld a,l
            and 02h
            xor 02h
            ld c,a
            ret

op_00:
; BRK imp
            jp emu_brk
op_01:
; ORA indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_02:
; KIL / nem támogatott
            jp emu_brk
op_03:
; SLO indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_04:
; NOPR zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_05:
; ORA zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_06:
; ASL zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_07:
; SLO zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_08:
; PHP imp
            call getp
            ld ixl,a
            ld a,(rS)
            ld l,a
            ld h,STKPG>>8
            ld a,ixl
            ld (hl),a
            dec l
            ld a,l
            ld (rS),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_09:
; ORA imm
            ld a,(de)
            inc e
            call z,pcwrap
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_0A:
; ASL acc
            sla b
            ld c,b
            ld ixh,b
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_0B:
; ANC imm
            ld a,(de)
            inc e
            call z,pcwrap
            and b
            ld b,a
            ld c,a
            ld ixh,a
            rlca
            and 1
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_0C:
; NOPR abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_0D:
; ORA abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_0E:
; ASL abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_0F:
; SLO abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_10:
; BPL rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,ixh
            or a
            ld a,l
            jp p,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_11:
; ORA indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_12:
; KIL / nem támogatott
            jp emu_brk
op_13:
; SLO indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_14:
; NOPR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_15:
; ORA zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_16:
; ASL zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_17:
; SLO zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_18:
; CLC imp
            xor a
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_19:
; ORA absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_1A:
; NOP imp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_1B:
; SLO absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_1C:
; NOPR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_1D:
; ORA absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_1E:
; ASL absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_1F:
; SLO absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            sla (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            or b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_20:
; JSR abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld ixl,a
            ld a,(rS)
            ld l,a
            ld h,STKPG>>8
            ld a,(pch)
            ld (hl),a
            dec l
            ld (hl),e
            dec l
            ld a,l
            ld (rS),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld (pch),a
            ld l,a
            ld h,RT>>8
            ld d,(hl)
            ld a,ixl
            ld e,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_21:
; AND indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_22:
; KIL / nem támogatott
            jp emu_brk
op_23:
; RLA indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_24:
; BIT zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld l,a
            and b
            ld c,a
            ld a,l
            ld ixh,a
            and 40h
            rrca
            rrca
            rrca
            rrca
            ld (fV),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_25:
; AND zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_26:
; ROL zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_27:
; RLA zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_28:
; PLP imp
            ld a,(rS)
            inc a
            ld (rS),a
            ld l,a
            ld h,STKPG>>8
            ld a,(hl)
            call setp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_29:
; AND imm
            ld a,(de)
            inc e
            call z,pcwrap
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_2A:
; ROL acc
            ld a,(fC)
            rra
            rl b
            ld c,b
            ld ixh,b
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_2B:
; ANC imm
            ld a,(de)
            inc e
            call z,pcwrap
            and b
            ld b,a
            ld c,a
            ld ixh,a
            rlca
            and 1
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_2C:
; BIT abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            and b
            ld c,a
            ld a,l
            ld ixh,a
            and 40h
            rrca
            rrca
            rrca
            rrca
            ld (fV),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_2D:
; AND abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_2E:
; ROL abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_2F:
; RLA abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_30:
; BMI rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,ixh
            or a
            ld a,l
            jp m,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_31:
; AND indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_32:
; KIL / nem támogatott
            jp emu_brk
op_33:
; RLA indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_34:
; NOPR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_35:
; AND zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_36:
; ROL zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_37:
; RLA zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_38:
; SEC imp
            ld a,1
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_39:
; AND absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_3A:
; NOP imp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_3B:
; RLA absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_3C:
; NOPR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_3D:
; AND absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_3E:
; ROL absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_3F:
; RLA absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            and b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_40:
; RTI imp
            ld a,(rS)
            ld l,a
            ld h,STKPG>>8
            inc l
            ld a,(hl)
            push hl
            call setp
            pop hl
            inc l
            ld e,(hl)
            inc l
            ld a,(hl)
            ld (pch),a
            ld a,l
            ld (rS),a
            ld hl,stop_s
            cp (hl)
            jp z,emu_exit
            ld a,(pch)
            ld l,a
            ld h,RT>>8
            ld d,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_41:
; EOR indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_42:
; KIL / nem támogatott
            jp emu_brk
op_43:
; SRE indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_44:
; NOPR zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_45:
; EOR zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_46:
; LSR zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_47:
; SRE zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_48:
; PHA imp
            ld a,(rS)
            ld l,a
            ld h,STKPG>>8
            ld (hl),b
            dec a
            ld (rS),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_49:
; EOR imm
            ld a,(de)
            inc e
            call z,pcwrap
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_4A:
; LSR acc
            srl b
            ld c,b
            ld ixh,b
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_4B:
; ALR imm
            ld a,(de)
            inc e
            call z,pcwrap
            and b
            srl a
            ld b,a
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_4C:
; JMP abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld (pch),a
            ld e,l
            ld l,a
            ld h,RT>>8
            ld d,(hl)
            jp wd_check
op_4D:
; EOR abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_4E:
; LSR abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_4F:
; SRE abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_50:
; BVC rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(fV)
            and 4
            ld a,l
            jp z,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_51:
; EOR indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_52:
; KIL / nem támogatott
            jp emu_brk
op_53:
; SRE indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_54:
; NOPR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_55:
; EOR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_56:
; LSR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_57:
; SRE zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_58:
; CLI imp
            xor a
            ld (fI),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_59:
; EOR absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_5A:
; NOP imp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_5B:
; SRE absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_5C:
; NOPR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_5D:
; EOR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_5E:
; LSR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_5F:
; SRE absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            srl (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            xor b
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_60:
; RTS imp
            ld a,(rS)
            ld l,a
            ld h,STKPG>>8
            inc l
            ld e,(hl)
            inc l
            ld a,(hl)
            ld (pch),a
            ld a,l
            ld (rS),a
            ld hl,stop_s
            cp (hl)
            jp z,emu_exit
            inc e
            jr nz,$+6
            ld hl,pch
            inc (hl)
            ld a,(pch)
            ld l,a
            ld h,RT>>8
            ld d,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_61:
; ADC indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_62:
; KIL / nem támogatott
            jp emu_brk
op_63:
; RRA indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_64:
; NOPR zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_65:
; ADC zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_66:
; ROR zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_67:
; RRA zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_68:
; PLA imp
            ld a,(rS)
            inc a
            ld (rS),a
            ld l,a
            ld h,STKPG>>8
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_69:
; ADC imm
            ld a,(de)
            inc e
            call z,pcwrap
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_6A:
; ROR acc
            ld a,(fC)
            rra
            rr b
            ld c,b
            ld ixh,b
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_6B:
; KIL / nem támogatott
            jp emu_brk
op_6C:
; JMP ind
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld e,(hl)
            inc l
            ld a,(hl)
            ld (pch),a
            ld l,a
            ld h,RT>>8
            ld d,(hl)
            jp wd_check
op_6D:
; ADC abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_6E:
; ROR abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_6F:
; RRA abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_70:
; BVS rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(fV)
            and 4
            ld a,l
            jp nz,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_71:
; ADC indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_72:
; KIL / nem támogatott
            jp emu_brk
op_73:
; RRA indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_74:
; NOPR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_75:
; ADC zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_76:
; ROR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_77:
; RRA zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_78:
; SEI imp
            ld a,04h
            ld (fI),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_79:
; ADC absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_7A:
; NOP imp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_7B:
; RRA absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_7C:
; NOPR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_7D:
; ADC absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_7E:
; ROR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_7F:
; RRA absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            ld a,(fC)
            rra
            rr (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,0
            rla
            ld (fC),a
            ld a,(hl)
            call do_adc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_80:
; NOPR imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_81:
; STA indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_A
            ld l,a
            ld (hl),b
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_82:
; NOPR imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_83:
; SAX indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_SAX
            ld l,a
            ld a,(rX)
            and b
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_84:
; STY zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(rY)
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_85:
; STA zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld (hl),b
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_86:
; STX zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(rX)
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_87:
; SAX zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(rX)
            and b
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_88:
; DEY imp
            ld hl,rY
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_89:
; NOPR imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_8A:
; TXA imp
            ld a,(rX)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_8B:
; KIL / nem támogatott
            jp emu_brk
op_8C:
; STY abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_Y
            ld l,a
            ld a,(rY)
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_8D:
; STA abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_A
            ld l,a
            ld (hl),b
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_8E:
; STX abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_X
            ld l,a
            ld a,(rX)
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_8F:
; SAX abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_SAX
            ld l,a
            ld a,(rX)
            and b
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_90:
; BCC rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(fC)
            rra
            ld a,l
            jp nc,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_91:
; STA indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_A
            ld l,a
            ld (hl),b
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_92:
; KIL / nem támogatott
            jp emu_brk
op_93:
; KIL / nem támogatott
            jp emu_brk
op_94:
; STY zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(rY)
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_95:
; STA zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld (hl),b
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_96:
; STX zpy
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rY
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(rX)
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_97:
; SAX zpy
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rY
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(rX)
            and b
            ld (hl),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_98:
; TYA imp
            ld a,(rY)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_99:
; STA absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_A
            ld l,a
            ld (hl),b
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_9A:
; TXS imp
            ld a,(rX)
            ld (rS),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_9B:
; KIL / nem támogatott
            jp emu_brk
op_9C:
; KIL / nem támogatott
            jp emu_brk
op_9D:
; STA absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_A
            ld l,a
            ld (hl),b
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_9E:
; KIL / nem támogatott
            jp emu_brk
op_9F:
; KIL / nem támogatott
            jp emu_brk
op_A0:
; LDY imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld (rY),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A1:
; LDA indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A2:
; LDX imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A3:
; LAX indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A4:
; LDY zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld (rY),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A5:
; LDA zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A6:
; LDX zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A7:
; LAX zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld b,a
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A8:
; TAY imp
            ld a,b
            ld (rY),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_A9:
; LDA imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_AA:
; TAX imp
            ld a,b
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_AB:
; LAX imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld b,a
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_AC:
; LDY abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld (rY),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_AD:
; LDA abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_AE:
; LDX abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_AF:
; LAX abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B0:
; BCS rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(fC)
            rra
            ld a,l
            jp c,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B1:
; LDA indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B2:
; KIL / nem támogatott
            jp emu_brk
op_B3:
; LAX indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B4:
; LDY zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld (rY),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B5:
; LDA zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B6:
; LDX zpy
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rY
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B7:
; LAX zpy
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rY
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld b,a
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B8:
; CLV imp
            xor a
            ld (fV),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_B9:
; LDA absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_BA:
; TSX imp
            ld a,(rS)
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_BB:
; KIL / nem támogatott
            jp emu_brk
op_BC:
; LDY absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld (rY),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_BD:
; LDA absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_BE:
; LDX absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_BF:
; LAX absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld b,a
            ld (rX),a
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C0:
; CPY imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(rY)
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C1:
; CMP indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C2:
; NOPR imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C3:
; DCP indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C4:
; CPY zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld l,a
            ld a,(rY)
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C5:
; CMP zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C6:
; DEC zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C7:
; DCP zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C8:
; INY imp
            ld hl,rY
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_C9:
; CMP imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_CA:
; DEX imp
            ld hl,rX
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_CB:
; SBX imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(rX)
            and b
            sub l
            ld (rX),a
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_CC:
; CPY abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            ld a,(rY)
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_CD:
; CMP abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_CE:
; DEC abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_CF:
; DCP abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D0:
; BNE rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,c
            or a
            ld a,l
            jp nz,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D1:
; CMP indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D2:
; KIL / nem támogatott
            jp emu_brk
op_D3:
; DCP indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D4:
; NOPR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D5:
; CMP zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D6:
; DEC zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D7:
; DCP zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D8:
; CLD imp
            xor a
            ld (fD),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_D9:
; CMP absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_DA:
; NOP imp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_DB:
; DCP absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_DC:
; NOPR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_DD:
; CMP absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_DE:
; DEC absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_DF:
; DCP absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            dec (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            ld l,a
            ld a,b
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E0:
; CPX imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(rX)
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E1:
; SBC indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E2:
; NOPR imm
            ld a,(de)
            inc e
            call z,pcwrap
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E3:
; ISC indx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E4:
; CPX zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld l,a
            ld a,(rX)
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E5:
; SBC zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E6:
; INC zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E7:
; ISC zp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E8:
; INX imp
            ld hl,rX
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_E9:
; SBC imm
            ld a,(de)
            inc e
            call z,pcwrap
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_EA:
; NOP imp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_EB:
; SBC imm
            ld a,(de)
            inc e
            call z,pcwrap
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_EC:
; CPX abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld l,a
            ld a,(rX)
            sub l
            ld c,a
            ld ixh,a
            ccf
            ld a,0
            rla
            ld (fC),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_ED:
; SBC abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_EE:
; INC abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_EF:
; ISC abs
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F0:
; BEQ rel
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,c
            or a
            ld a,l
            jp z,branch_take
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F1:
; SBC indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F2:
; KIL / nem támogatott
            jp emu_brk
op_F3:
; ISC indy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            inc l
            ld h,(hl)
            ld l,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F4:
; NOPR zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F5:
; SBC zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F6:
; INC zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F7:
; ISC zpx
            ld a,(de)
            inc e
            call z,pcwrap
            ld hl,rX
            add a,(hl)
            ld l,a
            ld h,ZPG>>8
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F8:
; SED imp
            ld a,08h
            ld (fD),a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_F9:
; SBC absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_FA:
; NOP imp
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_FB:
; ISC absy
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rY)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_FC:
; NOPR absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_FD:
; SBC absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,RT>>8
            ld h,(hl)
            ld l,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_FE:
; INC absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)
op_FF:
; ISC absx
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld a,(de)
            inc e
            call z,pcwrap
            ld h,a
            ld a,(rX)
            add a,l
            ld l,a
            jr nc,$+3
            inc h
            ld a,l
            ld l,h
            ld h,WT>>8
            ld h,(hl)
            inc h
            dec h
            call z,wslow_R
            ld l,a
            inc (hl)
            ld a,(hl)
            ld c,a
            ld ixh,a
            ld a,(hl)
            call do_sbc
            ld a,(de)
            inc e
            call z,pcwrap
            ld l,a
            ld h,OPLO>>8
            ld a,(hl)
            inc h
            ld h,(hl)
            ld l,a
            jp (hl)

; ugrótáblák (lapra igazítva): az utasításkezelők címének alsó és felső bájtja
            align 256
OPLO:
            db op_00 & 255, op_01 & 255, op_02 & 255, op_03 & 255, op_04 & 255, op_05 & 255, op_06 & 255, op_07 & 255
            db op_08 & 255, op_09 & 255, op_0A & 255, op_0B & 255, op_0C & 255, op_0D & 255, op_0E & 255, op_0F & 255
            db op_10 & 255, op_11 & 255, op_12 & 255, op_13 & 255, op_14 & 255, op_15 & 255, op_16 & 255, op_17 & 255
            db op_18 & 255, op_19 & 255, op_1A & 255, op_1B & 255, op_1C & 255, op_1D & 255, op_1E & 255, op_1F & 255
            db op_20 & 255, op_21 & 255, op_22 & 255, op_23 & 255, op_24 & 255, op_25 & 255, op_26 & 255, op_27 & 255
            db op_28 & 255, op_29 & 255, op_2A & 255, op_2B & 255, op_2C & 255, op_2D & 255, op_2E & 255, op_2F & 255
            db op_30 & 255, op_31 & 255, op_32 & 255, op_33 & 255, op_34 & 255, op_35 & 255, op_36 & 255, op_37 & 255
            db op_38 & 255, op_39 & 255, op_3A & 255, op_3B & 255, op_3C & 255, op_3D & 255, op_3E & 255, op_3F & 255
            db op_40 & 255, op_41 & 255, op_42 & 255, op_43 & 255, op_44 & 255, op_45 & 255, op_46 & 255, op_47 & 255
            db op_48 & 255, op_49 & 255, op_4A & 255, op_4B & 255, op_4C & 255, op_4D & 255, op_4E & 255, op_4F & 255
            db op_50 & 255, op_51 & 255, op_52 & 255, op_53 & 255, op_54 & 255, op_55 & 255, op_56 & 255, op_57 & 255
            db op_58 & 255, op_59 & 255, op_5A & 255, op_5B & 255, op_5C & 255, op_5D & 255, op_5E & 255, op_5F & 255
            db op_60 & 255, op_61 & 255, op_62 & 255, op_63 & 255, op_64 & 255, op_65 & 255, op_66 & 255, op_67 & 255
            db op_68 & 255, op_69 & 255, op_6A & 255, op_6B & 255, op_6C & 255, op_6D & 255, op_6E & 255, op_6F & 255
            db op_70 & 255, op_71 & 255, op_72 & 255, op_73 & 255, op_74 & 255, op_75 & 255, op_76 & 255, op_77 & 255
            db op_78 & 255, op_79 & 255, op_7A & 255, op_7B & 255, op_7C & 255, op_7D & 255, op_7E & 255, op_7F & 255
            db op_80 & 255, op_81 & 255, op_82 & 255, op_83 & 255, op_84 & 255, op_85 & 255, op_86 & 255, op_87 & 255
            db op_88 & 255, op_89 & 255, op_8A & 255, op_8B & 255, op_8C & 255, op_8D & 255, op_8E & 255, op_8F & 255
            db op_90 & 255, op_91 & 255, op_92 & 255, op_93 & 255, op_94 & 255, op_95 & 255, op_96 & 255, op_97 & 255
            db op_98 & 255, op_99 & 255, op_9A & 255, op_9B & 255, op_9C & 255, op_9D & 255, op_9E & 255, op_9F & 255
            db op_A0 & 255, op_A1 & 255, op_A2 & 255, op_A3 & 255, op_A4 & 255, op_A5 & 255, op_A6 & 255, op_A7 & 255
            db op_A8 & 255, op_A9 & 255, op_AA & 255, op_AB & 255, op_AC & 255, op_AD & 255, op_AE & 255, op_AF & 255
            db op_B0 & 255, op_B1 & 255, op_B2 & 255, op_B3 & 255, op_B4 & 255, op_B5 & 255, op_B6 & 255, op_B7 & 255
            db op_B8 & 255, op_B9 & 255, op_BA & 255, op_BB & 255, op_BC & 255, op_BD & 255, op_BE & 255, op_BF & 255
            db op_C0 & 255, op_C1 & 255, op_C2 & 255, op_C3 & 255, op_C4 & 255, op_C5 & 255, op_C6 & 255, op_C7 & 255
            db op_C8 & 255, op_C9 & 255, op_CA & 255, op_CB & 255, op_CC & 255, op_CD & 255, op_CE & 255, op_CF & 255
            db op_D0 & 255, op_D1 & 255, op_D2 & 255, op_D3 & 255, op_D4 & 255, op_D5 & 255, op_D6 & 255, op_D7 & 255
            db op_D8 & 255, op_D9 & 255, op_DA & 255, op_DB & 255, op_DC & 255, op_DD & 255, op_DE & 255, op_DF & 255
            db op_E0 & 255, op_E1 & 255, op_E2 & 255, op_E3 & 255, op_E4 & 255, op_E5 & 255, op_E6 & 255, op_E7 & 255
            db op_E8 & 255, op_E9 & 255, op_EA & 255, op_EB & 255, op_EC & 255, op_ED & 255, op_EE & 255, op_EF & 255
            db op_F0 & 255, op_F1 & 255, op_F2 & 255, op_F3 & 255, op_F4 & 255, op_F5 & 255, op_F6 & 255, op_F7 & 255
            db op_F8 & 255, op_F9 & 255, op_FA & 255, op_FB & 255, op_FC & 255, op_FD & 255, op_FE & 255, op_FF & 255
OPHI:
            db op_00 >> 8, op_01 >> 8, op_02 >> 8, op_03 >> 8, op_04 >> 8, op_05 >> 8, op_06 >> 8, op_07 >> 8
            db op_08 >> 8, op_09 >> 8, op_0A >> 8, op_0B >> 8, op_0C >> 8, op_0D >> 8, op_0E >> 8, op_0F >> 8
            db op_10 >> 8, op_11 >> 8, op_12 >> 8, op_13 >> 8, op_14 >> 8, op_15 >> 8, op_16 >> 8, op_17 >> 8
            db op_18 >> 8, op_19 >> 8, op_1A >> 8, op_1B >> 8, op_1C >> 8, op_1D >> 8, op_1E >> 8, op_1F >> 8
            db op_20 >> 8, op_21 >> 8, op_22 >> 8, op_23 >> 8, op_24 >> 8, op_25 >> 8, op_26 >> 8, op_27 >> 8
            db op_28 >> 8, op_29 >> 8, op_2A >> 8, op_2B >> 8, op_2C >> 8, op_2D >> 8, op_2E >> 8, op_2F >> 8
            db op_30 >> 8, op_31 >> 8, op_32 >> 8, op_33 >> 8, op_34 >> 8, op_35 >> 8, op_36 >> 8, op_37 >> 8
            db op_38 >> 8, op_39 >> 8, op_3A >> 8, op_3B >> 8, op_3C >> 8, op_3D >> 8, op_3E >> 8, op_3F >> 8
            db op_40 >> 8, op_41 >> 8, op_42 >> 8, op_43 >> 8, op_44 >> 8, op_45 >> 8, op_46 >> 8, op_47 >> 8
            db op_48 >> 8, op_49 >> 8, op_4A >> 8, op_4B >> 8, op_4C >> 8, op_4D >> 8, op_4E >> 8, op_4F >> 8
            db op_50 >> 8, op_51 >> 8, op_52 >> 8, op_53 >> 8, op_54 >> 8, op_55 >> 8, op_56 >> 8, op_57 >> 8
            db op_58 >> 8, op_59 >> 8, op_5A >> 8, op_5B >> 8, op_5C >> 8, op_5D >> 8, op_5E >> 8, op_5F >> 8
            db op_60 >> 8, op_61 >> 8, op_62 >> 8, op_63 >> 8, op_64 >> 8, op_65 >> 8, op_66 >> 8, op_67 >> 8
            db op_68 >> 8, op_69 >> 8, op_6A >> 8, op_6B >> 8, op_6C >> 8, op_6D >> 8, op_6E >> 8, op_6F >> 8
            db op_70 >> 8, op_71 >> 8, op_72 >> 8, op_73 >> 8, op_74 >> 8, op_75 >> 8, op_76 >> 8, op_77 >> 8
            db op_78 >> 8, op_79 >> 8, op_7A >> 8, op_7B >> 8, op_7C >> 8, op_7D >> 8, op_7E >> 8, op_7F >> 8
            db op_80 >> 8, op_81 >> 8, op_82 >> 8, op_83 >> 8, op_84 >> 8, op_85 >> 8, op_86 >> 8, op_87 >> 8
            db op_88 >> 8, op_89 >> 8, op_8A >> 8, op_8B >> 8, op_8C >> 8, op_8D >> 8, op_8E >> 8, op_8F >> 8
            db op_90 >> 8, op_91 >> 8, op_92 >> 8, op_93 >> 8, op_94 >> 8, op_95 >> 8, op_96 >> 8, op_97 >> 8
            db op_98 >> 8, op_99 >> 8, op_9A >> 8, op_9B >> 8, op_9C >> 8, op_9D >> 8, op_9E >> 8, op_9F >> 8
            db op_A0 >> 8, op_A1 >> 8, op_A2 >> 8, op_A3 >> 8, op_A4 >> 8, op_A5 >> 8, op_A6 >> 8, op_A7 >> 8
            db op_A8 >> 8, op_A9 >> 8, op_AA >> 8, op_AB >> 8, op_AC >> 8, op_AD >> 8, op_AE >> 8, op_AF >> 8
            db op_B0 >> 8, op_B1 >> 8, op_B2 >> 8, op_B3 >> 8, op_B4 >> 8, op_B5 >> 8, op_B6 >> 8, op_B7 >> 8
            db op_B8 >> 8, op_B9 >> 8, op_BA >> 8, op_BB >> 8, op_BC >> 8, op_BD >> 8, op_BE >> 8, op_BF >> 8
            db op_C0 >> 8, op_C1 >> 8, op_C2 >> 8, op_C3 >> 8, op_C4 >> 8, op_C5 >> 8, op_C6 >> 8, op_C7 >> 8
            db op_C8 >> 8, op_C9 >> 8, op_CA >> 8, op_CB >> 8, op_CC >> 8, op_CD >> 8, op_CE >> 8, op_CF >> 8
            db op_D0 >> 8, op_D1 >> 8, op_D2 >> 8, op_D3 >> 8, op_D4 >> 8, op_D5 >> 8, op_D6 >> 8, op_D7 >> 8
            db op_D8 >> 8, op_D9 >> 8, op_DA >> 8, op_DB >> 8, op_DC >> 8, op_DD >> 8, op_DE >> 8, op_DF >> 8
            db op_E0 >> 8, op_E1 >> 8, op_E2 >> 8, op_E3 >> 8, op_E4 >> 8, op_E5 >> 8, op_E6 >> 8, op_E7 >> 8
            db op_E8 >> 8, op_E9 >> 8, op_EA >> 8, op_EB >> 8, op_EC >> 8, op_ED >> 8, op_EE >> 8, op_EF >> 8
            db op_F0 >> 8, op_F1 >> 8, op_F2 >> 8, op_F3 >> 8, op_F4 >> 8, op_F5 >> 8, op_F6 >> 8, op_F7 >> 8
            db op_F8 >> 8, op_F9 >> 8, op_FA >> 8, op_FB >> 8, op_FC >> 8, op_FD >> 8, op_FE >> 8, op_FF >> 8
