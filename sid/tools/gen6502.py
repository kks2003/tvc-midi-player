#!/usr/bin/env python3
"""A 6502-emulátor Z80-as kódjának generátora: sid/cpu6502.asm.

    python3 tools/gen6502.py > cpu6502.asm

Regiszterek a futás alatt (lásd sidplay.asm):
  B   = a 6502 A regisztere
  C   = a Z jelző forrása (0 -> Z=1)
  IXh = az N jelző forrása (7. bit)
  DE  = a 6502 PC Z80-as címe (E = a PC alsó bájtja, D = a lap Z80-as helye),
        a PC felső bájtja a pch változóban
  HL, A, IXl: munkaregiszterek
  rX, rY, rS, fC (0. bit), fV (2. bit), fD (08h), fI (04h): változók
A 6502 memóriája 256 bájtos lapokban: RT (olvasás) és WT (írás) táblák adják
a 6502-es lap Z80-as lapját. WT = 0: lefoglalatlan lap vagy I/O (lassú út).
"""

out = []
def e(*lines):
    out.extend(lines)

def NEXT():
    return ["ld a,(de)", "inc e", "call z,pcwrap", "ld l,a", "ld h,OPLO>>8",
            "ld a,(hl)", "inc h", "ld h,(hl)", "ld l,a", "jp (hl)"]

FETCH = ["ld a,(de)", "inc e", "call z,pcwrap"]
NZ = ["ld c,a", "ld ixh,a"]
STORE_C = ["ld a,0", "rla", "ld (fC),a"]

# ---- címzési módok: a 6502-es cím HL-be (vagy Z80-as mutató HL-be) -------
def addr6502(mode):
    """6502-es cím HL-be (abs, absx, absy, indx, indy)."""
    if mode == "abs":
        return FETCH + ["ld l,a"] + FETCH + ["ld h,a"]
    if mode in ("absx", "absy"):
        r = "rX" if mode == "absx" else "rY"
        return addr6502("abs") + ["ld a,(%s)" % r, "add a,l", "ld l,a", "jr nc,$+3", "inc h"]
    if mode == "indx":
        return FETCH + ["ld hl,rX", "add a,(hl)", "ld l,a", "ld h,ZPG>>8",
                        "ld a,(hl)", "inc l", "ld h,(hl)", "ld l,a"]
    if mode == "indy":
        return FETCH + ["ld l,a", "ld h,ZPG>>8", "ld a,(hl)", "inc l", "ld h,(hl)", "ld l,a",
                        "ld a,(rY)", "add a,l", "ld l,a", "jr nc,$+3", "inc h"]
    raise ValueError(mode)

def zpptr(mode):
    """Nullás lap: Z80-as mutató HL-be."""
    if mode == "zp":
        return FETCH + ["ld l,a", "ld h,ZPG>>8"]
    r = "rX" if mode == "zpx" else "rY"
    return FETCH + ["ld hl,%s" % r, "add a,(hl)", "ld l,a", "ld h,ZPG>>8"]

RD = ["ld a,l", "ld l,h", "ld h,RT>>8", "ld h,(hl)", "ld l,a", "ld a,(hl)"]
def WR(var):
    return ["ld a,l", "ld l,h", "ld h,WT>>8", "ld h,(hl)", "inc h", "dec h",
            "call z,wslow_" + var, "ld l,a"]

def read_value(mode):
    """Az operandus értéke A-ba."""
    if mode == "imm":
        return FETCH
    if mode in ("zp", "zpx", "zpy"):
        return zpptr(mode) + ["ld a,(hl)"]
    return addr6502(mode) + RD

def write_ptr(mode, var):
    """Írható Z80-as mutató HL-be."""
    if mode in ("zp", "zpx", "zpy"):
        return zpptr(mode)
    return addr6502(mode) + WR(var)

# ---- műveletek -----------------------------------------------------------
ALU = {   # A = érték
    "LDA": ["ld b,a"] + NZ,
    "LDX": ["ld (rX),a"] + NZ,
    "LDY": ["ld (rY),a"] + NZ,
    "LAX": ["ld b,a", "ld (rX),a"] + NZ,
    "AND": ["and b", "ld b,a"] + NZ,
    "ORA": ["or b", "ld b,a"] + NZ,
    "EOR": ["xor b", "ld b,a"] + NZ,
    "ADC": ["call do_adc"],
    "SBC": ["call do_sbc"],
    "CMP": ["ld l,a", "ld a,b", "sub l"] + NZ + ["ccf"] + STORE_C,
    "CPX": ["ld l,a", "ld a,(rX)", "sub l"] + NZ + ["ccf"] + STORE_C,
    "CPY": ["ld l,a", "ld a,(rY)", "sub l"] + NZ + ["ccf"] + STORE_C,
    "BIT": ["ld l,a", "and b", "ld c,a", "ld a,l", "ld ixh,a", "and 40h",
            "rrca", "rrca", "rrca", "rrca", "ld (fV),a"],
    "NOPR": [],
    "ANC": ["and b", "ld b,a"] + NZ + ["rlca", "and 1", "ld (fC),a"],
    "ALR": ["and b", "srl a", "ld b,a"] + NZ + STORE_C,
    "SBX": ["ld l,a", "ld a,(rX)", "and b", "sub l", "ld (rX),a"] + NZ + ["ccf"] + STORE_C,
}
RMW = {   # (HL) = a módosítandó bájt
    "ASL": ["sla (hl)", "ld a,(hl)"] + NZ + STORE_C,
    "LSR": ["srl (hl)", "ld a,(hl)"] + NZ + STORE_C,
    "ROL": ["ld a,(fC)", "rra", "rl (hl)", "ld a,(hl)"] + NZ + STORE_C,
    "ROR": ["ld a,(fC)", "rra", "rr (hl)", "ld a,(hl)"] + NZ + STORE_C,
    "INC": ["inc (hl)", "ld a,(hl)"] + NZ,
    "DEC": ["dec (hl)", "ld a,(hl)"] + NZ,
}
COMBO = {"SLO": ("ASL", "ORA"), "RLA": ("ROL", "AND"), "SRE": ("LSR", "EOR"),
         "RRA": ("ROR", "ADC"), "DCP": ("DEC", "CMP"), "ISC": ("INC", "SBC")}
ACC = {
    "ASL": ["sla b", "ld c,b", "ld ixh,b"] + STORE_C,
    "LSR": ["srl b", "ld c,b", "ld ixh,b"] + STORE_C,
    "ROL": ["ld a,(fC)", "rra", "rl b", "ld c,b", "ld ixh,b"] + STORE_C,
    "ROR": ["ld a,(fC)", "rra", "rr b", "ld c,b", "ld ixh,b"] + STORE_C,
}
STORE = {"STA": ("A", ["ld (hl),b"]), "STX": ("X", ["ld a,(rX)", "ld (hl),a"]),
         "STY": ("Y", ["ld a,(rY)", "ld (hl),a"]),
         "SAX": ("SAX", ["ld a,(rX)", "and b", "ld (hl),a"])}

def push_a():   # A -> verem
    return ["ld l,a", "ld a,(rS)", "ld h,l", "ld l,a", "ld (hl),h", "ld h,STKPG>>8",
            ]
IMP = {
    "NOP": [],
    "CLC": ["xor a", "ld (fC),a"], "SEC": ["ld a,1", "ld (fC),a"],
    "CLD": ["xor a", "ld (fD),a"], "SED": ["ld a,08h", "ld (fD),a"],
    "CLI": ["xor a", "ld (fI),a"], "SEI": ["ld a,04h", "ld (fI),a"],
    "CLV": ["xor a", "ld (fV),a"],
    "TAX": ["ld a,b", "ld (rX),a"] + NZ, "TAY": ["ld a,b", "ld (rY),a"] + NZ,
    "TXA": ["ld a,(rX)", "ld b,a"] + NZ, "TYA": ["ld a,(rY)", "ld b,a"] + NZ,
    "TSX": ["ld a,(rS)", "ld (rX),a"] + NZ, "TXS": ["ld a,(rX)", "ld (rS),a"],
    "INX": ["ld hl,rX", "inc (hl)", "ld a,(hl)"] + NZ, "DEX": ["ld hl,rX", "dec (hl)", "ld a,(hl)"] + NZ,
    "INY": ["ld hl,rY", "inc (hl)", "ld a,(hl)"] + NZ, "DEY": ["ld hl,rY", "dec (hl)", "ld a,(hl)"] + NZ,
    "PHA": ["ld a,(rS)", "ld l,a", "ld h,STKPG>>8", "ld (hl),b", "dec a", "ld (rS),a"],
    "PHP": ["call getp", "ld c?", ],  # helyettesítve lent
    "PLA": ["ld a,(rS)", "inc a", "ld (rS),a", "ld l,a", "ld h,STKPG>>8", "ld a,(hl)", "ld b,a"] + NZ,
    "PLP": ["ld a,(rS)", "inc a", "ld (rS),a", "ld l,a", "ld h,STKPG>>8", "ld a,(hl)", "call setp"],
}
IMP["PHP"] = ["call getp", "ld ixl,a", "ld a,(rS)", "ld l,a", "ld h,STKPG>>8", "ld a,ixl",
              "ld (hl),a", "dec l", "ld a,l", "ld (rS),a"]
BRANCH = {
    "BPL": ["ld a,ixh", "or a", "ld a,l", "jp p,branch_take"],
    "BMI": ["ld a,ixh", "or a", "ld a,l", "jp m,branch_take"],
    "BEQ": ["ld a,c", "or a", "ld a,l", "jp z,branch_take"],
    "BNE": ["ld a,c", "or a", "ld a,l", "jp nz,branch_take"],
    "BCC": ["ld a,(fC)", "rra", "ld a,l", "jp nc,branch_take"],
    "BCS": ["ld a,(fC)", "rra", "ld a,l", "jp c,branch_take"],
    "BVC": ["ld a,(fV)", "and 4", "ld a,l", "jp z,branch_take"],
    "BVS": ["ld a,(fV)", "and 4", "ld a,l", "jp nz,branch_take"],
}

OPS = {}
def op(code, mn, mode):
    OPS[code] = (mn, mode)

def group(mn, codes):
    for c, m in codes:
        op(c, mn, m)

def std8(mn, base):  # ORA/AND/EOR/ADC/STA/LDA/CMP/SBC minta
    group(mn, [(base + 0x01, "indx"), (base + 0x05, "zp"), (base + 0x09, "imm"), (base + 0x0D, "abs"),
               (base + 0x11, "indy"), (base + 0x15, "zpx"), (base + 0x19, "absy"), (base + 0x1D, "absx")])
for mn, b in (("ORA", 0x00), ("AND", 0x20), ("EOR", 0x40), ("ADC", 0x60), ("LDA", 0xA0),
              ("CMP", 0xC0), ("SBC", 0xE0)):
    std8(mn, b)
group("STA", [(0x81, "indx"), (0x85, "zp"), (0x8D, "abs"), (0x91, "indy"), (0x95, "zpx"),
              (0x99, "absy"), (0x9D, "absx")])
for mn, b in (("ASL", 0x00), ("ROL", 0x20), ("LSR", 0x40), ("ROR", 0x60)):
    group(mn, [(b + 0x06, "zp"), (b + 0x0A, "acc"), (b + 0x0E, "abs"), (b + 0x16, "zpx"), (b + 0x1E, "absx")])
for mn, b in (("DEC", 0xC0), ("INC", 0xE0)):
    group(mn, [(b + 0x06, "zp"), (b + 0x0E, "abs"), (b + 0x16, "zpx"), (b + 0x1E, "absx")])
group("BIT", [(0x24, "zp"), (0x2C, "abs")])
group("STX", [(0x86, "zp"), (0x8E, "abs"), (0x96, "zpy")])
group("STY", [(0x84, "zp"), (0x8C, "abs"), (0x94, "zpx")])
group("LDX", [(0xA2, "imm"), (0xA6, "zp"), (0xAE, "abs"), (0xB6, "zpy"), (0xBE, "absy")])
group("LDY", [(0xA0, "imm"), (0xA4, "zp"), (0xAC, "abs"), (0xB4, "zpx"), (0xBC, "absx")])
group("CPX", [(0xE0, "imm"), (0xE4, "zp"), (0xEC, "abs")])
group("CPY", [(0xC0, "imm"), (0xC4, "zp"), (0xCC, "abs")])
for c, mn in ((0x10, "BPL"), (0x30, "BMI"), (0x50, "BVC"), (0x70, "BVS"), (0x90, "BCC"),
              (0xB0, "BCS"), (0xD0, "BNE"), (0xF0, "BEQ")):
    op(c, mn, "rel")
for c, mn in ((0x08, "PHP"), (0x18, "CLC"), (0x28, "PLP"), (0x38, "SEC"), (0x48, "PHA"), (0x58, "CLI"),
              (0x68, "PLA"), (0x78, "SEI"), (0x88, "DEY"), (0x8A, "TXA"), (0x98, "TYA"), (0x9A, "TXS"),
              (0xA8, "TAY"), (0xAA, "TAX"), (0xB8, "CLV"), (0xBA, "TSX"), (0xC8, "INY"), (0xCA, "DEX"),
              (0xD8, "CLD"), (0xE8, "INX"), (0xEA, "NOP"), (0xF8, "SED")):
    op(c, mn, "imp")
op(0x00, "BRK", "imp"); op(0x20, "JSR", "abs"); op(0x40, "RTI", "imp"); op(0x60, "RTS", "imp")
op(0x4C, "JMP", "abs"); op(0x6C, "JMP", "ind")
# nem dokumentált utasítások (a lejátszórutinokban előfordulók)
for mn, b in (("SLO", 0x00), ("RLA", 0x20), ("SRE", 0x40), ("RRA", 0x60), ("DCP", 0xC0), ("ISC", 0xE0)):
    group(mn, [(b + 0x03, "indx"), (b + 0x07, "zp"), (b + 0x0F, "abs"), (b + 0x13, "indy"),
               (b + 0x17, "zpx"), (b + 0x1B, "absy"), (b + 0x1F, "absx")])
group("SAX", [(0x83, "indx"), (0x87, "zp"), (0x8F, "abs"), (0x97, "zpy")])
group("LAX", [(0xA3, "indx"), (0xA7, "zp"), (0xAF, "abs"), (0xB3, "indy"), (0xB7, "zpy"),
              (0xBF, "absy"), (0xAB, "imm")])
for c in (0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA):
    op(c, "NOP", "imp")
for c, m in [(0x80, "imm"), (0x82, "imm"), (0x89, "imm"), (0xC2, "imm"), (0xE2, "imm"),
             (0x04, "zp"), (0x44, "zp"), (0x64, "zp"), (0x0C, "abs")] + \
        [(c, "zpx") for c in (0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4)] + \
        [(c, "absx") for c in (0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC)]:
    op(c, "NOPR", m)
op(0xEB, "SBC", "imm"); op(0x0B, "ANC", "imm"); op(0x2B, "ANC", "imm")
op(0x4B, "ALR", "imm"); op(0xCB, "SBX", "imm")

def body(code):
    mn, mode = OPS[code]
    if mn == "BRK":
        return ["jp emu_brk"]
    if mn in ALU:
        return read_value(mode) + ALU[mn] + NEXT()
    if mn in STORE:
        var, st = STORE[mn]
        return write_ptr(mode, var) + st + NEXT()
    if mn in RMW:
        if mode == "acc":
            return ACC[mn] + NEXT()
        return write_ptr(mode, "R") + RMW[mn] + NEXT()
    if mn in COMBO:
        r, a = COMBO[mn]
        return write_ptr(mode, "R") + RMW[r] + ["ld a,(hl)"] + ALU[a] + NEXT()
    if mn in IMP:
        return IMP[mn] + NEXT()
    if mn in BRANCH:
        return FETCH + ["ld l,a"] + BRANCH[mn] + NEXT()
    if mn == "JMP" and mode == "abs":
        return FETCH + ["ld l,a"] + FETCH + ["ld (pch),a", "ld e,l", "ld l,a", "ld h,RT>>8",
                                             "ld d,(hl)", "jp wd_check"]
    if mn == "JMP":
        return FETCH + ["ld l,a"] + FETCH + ["ld h,a"] + \
            ["ld a,l", "ld l,h", "ld h,RT>>8", "ld h,(hl)", "ld l,a",
             "ld e,(hl)", "inc l", "ld a,(hl)", "ld (pch),a", "ld l,a", "ld h,RT>>8",
             "ld d,(hl)", "jp wd_check"]
    if mn == "JSR":
        return FETCH + ["ld ixl,a", "ld a,(rS)", "ld l,a", "ld h,STKPG>>8", "ld a,(pch)",
                        "ld (hl),a", "dec l", "ld (hl),e", "dec l", "ld a,l", "ld (rS),a"] + \
            FETCH + ["ld (pch),a", "ld l,a", "ld h,RT>>8", "ld d,(hl)", "ld a,ixl", "ld e,a"] + NEXT()
    if mn == "RTS":
        return ["ld a,(rS)", "ld l,a", "ld h,STKPG>>8", "inc l", "ld e,(hl)", "inc l",
                "ld a,(hl)", "ld (pch),a", "ld a,l", "ld (rS),a", "ld hl,stop_s", "cp (hl)",
                "jp z,emu_exit", "inc e", "jr nz,$+6", "ld hl,pch", "inc (hl)",
                "ld a,(pch)", "ld l,a", "ld h,RT>>8", "ld d,(hl)"] + NEXT()
    if mn == "RTI":
        return ["ld a,(rS)", "ld l,a", "ld h,STKPG>>8", "inc l", "ld a,(hl)", "push hl",
                "call setp", "pop hl", "inc l", "ld e,(hl)", "inc l",
                "ld a,(hl)", "ld (pch),a", "ld a,l", "ld (rS),a", "ld hl,stop_s", "cp (hl)",
                "jp z,emu_exit", "ld a,(pch)", "ld l,a", "ld h,RT>>8", "ld d,(hl)"] + NEXT()
    raise ValueError((code, mn, mode))

e("; ============================================================================",
  "; cpu6502.asm - GENERÁLT FÁJL (tools/gen6502.py), kézzel ne módosítsd!",
  "; 6502-emulátor Z80-on a SID-lejátszóhoz.",
  "; ============================================================================",
  "")
e("; belépés: a regiszterek betöltve, DE = a PC (lásd sidplay.asm emu_run)",
  "emu_next:")
e(*["            " + l for l in NEXT()])
e("", "; elágazás: A = eltolás, E = a következő utasítás alsó bájtja",
  "branch_take:",
  "            ld l,a", "            add a,e", "            ld e,a", "            bit 7,l",
  "            jr nz,.neg", "            jr nc,.same", "            ld hl,pch", "            inc (hl)",
  "            ld l,(hl)", "            ld h,RT>>8", "            ld d,(hl)",
  ".same:")
e(*["            " + l for l in NEXT()])
e(".neg:", "            jr c,wd_check", "            ld hl,pch", "            dec (hl)",
  "            ld l,(hl)", "            ld h,RT>>8", "            ld d,(hl)",
  "; visszafelé ugrás: őrkutya (a ROM TIME számlálója)",
  "wd_check:", "            ld a,(0B1Dh)", "wd_cmp:     cp 0", "            jp z,emu_timeout")
e(*["            " + l for l in NEXT()])
e("", "; ADC/SBC: A = operandus",
  "do_adc:", "            ld l,a", "            ld a,(fD)", "            or a", "            jr nz,.dec",
  "            ld a,(fC)", "            rra", "            ld a,b", "            adc a,l",
  "            ld b,a", "            ld c,a", "            ld ixh,a", "            push af", "            pop hl",
  "            ld a,l", "            ld (fC),a", "            ld (fV),a", "            ret",
  ".dec:", "            ld a,(fC)", "            rra", "            ld a,b", "            adc a,l",
  "            daa", "            ld b,a", "            ld c,a", "            ld ixh,a",
  "            ld a,0", "            rla", "            ld (fC),a", "            ret",
  "do_sbc:", "            ld l,a", "            ld a,(fD)", "            or a", "            jr nz,.dec",
  "            ld a,(fC)", "            cpl", "            rra", "            ld a,b", "            sbc a,l",
  "            ld b,a", "            ld c,a", "            ld ixh,a", "            ccf", "            push af",
  "            pop hl", "            ld a,l", "            ld (fC),a", "            ld (fV),a", "            ret",
  ".dec:", "            ld a,(fC)", "            cpl", "            rra", "            ld a,b", "            sbc a,l",
  "            daa", "            ld b,a", "            ld c,a", "            ld ixh,a", "            ccf",
  "            ld a,0", "            rla", "            ld (fC),a", "            ret")
e("", "; a P regiszter összerakása A-ba (B és 5. bit = 1)",
  "getp:", "            ld a,ixh", "            and 80h", "            ld l,a",
  "            ld a,(fV)", "            and 4", "            jr z,.nv", "            set 6,l",
  ".nv:        ld a,c", "            or a", "            jr nz,.nz", "            set 1,l",
  ".nz:        ld a,(fC)", "            and 1", "            or l", "            ld l,a",
  "            ld a,(fD)", "            or l", "            ld l,a", "            ld a,(fI)", "            or l",
  "            or 30h", "            ret",
  "; A = P -> jelzők",
  "setp:", "            ld l,a", "            and 80h", "            ld ixh,a",
  "            ld a,l", "            and 40h", "            rrca", "            rrca", "            rrca", "            rrca",
  "            ld (fV),a", "            ld a,l", "            and 08h", "            ld (fD),a",
  "            ld a,l", "            and 04h", "            ld (fI),a", "            ld a,l", "            and 01h",
  "            ld (fC),a", "            ld a,l", "            and 02h", "            xor 02h", "            ld c,a",
  "            ret", "")
for code in range(256):
    e("op_%02X:" % code)
    if code in OPS:
        e("; %s %s" % OPS[code])
        e(*["            " + l for l in body(code)])
    else:
        e("; KIL / nem támogatott", "            jp emu_brk")
e("", "; ugrótáblák (lapra igazítva): az utasításkezelők címének alsó és felső bájtja",
  "            align 256", "OPLO:")
for i in range(0, 256, 8):
    e("            db " + ", ".join("op_%02X & 255" % c for c in range(i, i + 8)))
e("OPHI:")
for i in range(0, 256, 8):
    e("            db " + ", ".join("op_%02X >> 8" % c for c in range(i, i + 8)))
print("\n".join(out))
