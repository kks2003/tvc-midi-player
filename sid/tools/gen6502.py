#!/usr/bin/env python3
"""A 6502-emulátor Z80-as kódjának generátora: sid/cpu6502.asm.

    python3 tools/gen6502.py > cpu6502.asm               (1. menet: sorban)
    python3 tools/gen6502.py --sym build/x.sym > cpu6502.asm   (2. menet: pakolva)

A kezelők címének alsó bájtja maga az opkód, a felső bájt az OPHI táblában
van, így az elágazás:  LD A,(DE) / INC DE / LD L,A / LD H,OPHI / LD H,(HL) / JP (HL).
Ehhez a kezelők méretét ismerni kell: az 1. menet sorban adja ki őket, a
fordítás szimbólumfájljából (op_XX címkék) a 2. menet elpakolja őket.

Regiszterek a futás alatt (lásd sidplay.asm):
  B   = a 6502 A regisztere      C   = X      IXh = Y
  F   = a 6502 N és Z jelzője élőben (S és Z); IXl = az átvitel (0. bit);
        a többi jelző változóban: fV (2. bit), fD (08h), fI (04h)
  DE  = a 6502 PC Z80-as címe (a zene lapjai a Z80 memóriájában is
        folytonosak, ezért INC DE-vel léptethető)
  HL, A: munkaregiszterek; AF': munkaterület ott, ahol a jelzők megmaradnak
  Az időkorlátot (végtelen ciklus) az IT-kezelő figyeli, nem az emulátor.
A 6502 memóriája 256 bájtos lapokban: RT (olvasás), WT (írás; 0 = I/O vagy
lefoglalatlan lap: lassú út), INV (Z80-as lap -> 6502-es lap).
"""
import sys

NEXT = ["ld a,(de)", "inc de", "ld l,a", "ld h,OPHI>>8", "ld h,(hl)", "jp (hl)"]
# abszolút operandus: A = alsó bájt, L = felső bájt, DE = PC + 2 (jelzőket nem bánt)
FA = ["ex de,hl", "ld a,(hl)", "inc hl", "ld e,(hl)", "inc hl", "ex de,hl"]
EXA = ["ex af,af'"]
RDT = ["ld h,RT>>8", "ld h,(hl)", "ld l,a", "ld a,(hl)"]
STC = ["rla", "ld ixl,a"]          # a Z80 átvitele -> fC (S, Z megmarad)
_lab = [0]

def idx(reg):
    return ["add a,%s" % reg, "jr nc,$+3", "inc l"]

def read_value(mode):
    """Az operandus értéke A-ba (a jelzőket elronthatja)."""
    if mode == "imm":
        return ["ld a,(de)", "inc de"]
    if mode == "zp":
        return ["ld a,(de)", "inc de", "ld l,a", "ld h,ZPG>>8", "ld a,(hl)"]
    if mode in ("zpx", "zpy"):
        return ["ld a,(de)", "inc de", "add a,%s" % ("c" if mode == "zpx" else "ixh"),
                "ld l,a", "ld h,ZPG>>8", "ld a,(hl)"]
    if mode == "abs":
        return FA + RDT
    if mode == "absx":
        return FA + idx("c") + RDT
    if mode == "absy":
        return FA + idx("ixh") + RDT
    if mode == "indx":
        return ["ld a,(de)", "inc de", "add a,c", "ld l,a", "ld h,ZPG>>8", "ld a,(hl)",
                "inc l", "ld l,(hl)"] + RDT
    if mode == "indy":
        return ["ld a,(de)", "inc de", "ld l,a", "ld h,ZPG>>8", "ld a,(hl)", "inc l",
                "ld l,(hl)"] + idx("ixh") + RDT
    raise ValueError(mode)

def write_ptr(mode, var):
    """Írható Z80-as mutató HL-be; a jelzők megmaradnak. (kód, a kezelő végére
    kerülő lassú út)"""
    if mode == "zp":
        return ["ld a,(de)", "inc de", "ld l,a", "ld h,ZPG>>8"], []
    if mode in ("zpx", "zpy"):
        return EXA + ["ld a,(de)", "inc de", "add a,%s" % ("c" if mode == "zpx" else "ixh"),
                      "ld l,a", "ld h,ZPG>>8"] + EXA, []
    if mode == "abs":
        a = FA
    elif mode == "absx":
        a = FA + idx("c")
    elif mode == "absy":
        a = FA + idx("ixh")
    elif mode == "indx":
        a = ["ld a,(de)", "inc de", "add a,c", "ld l,a", "ld h,ZPG>>8", "ld a,(hl)",
             "inc l", "ld l,(hl)"]
    elif mode == "indy":
        a = ["ld a,(de)", "inc de", "ld l,a", "ld h,ZPG>>8", "ld a,(hl)", "inc l",
             "ld l,(hl)"] + idx("ixh")
    else:
        raise ValueError(mode)
    _lab[0] += 1
    s, b = ".s%d" % _lab[0], ".b%d" % _lab[0]
    code = EXA + a + ["ld h,WT>>8", "ld h,(hl)", "inc h", "dec h", "jr z," + s,
                      b + ":", "ld l,a"] + EXA
    slow = [s + ":", "call wslow_" + var, "jr " + b]
    return code, slow

ALU = {   # A = érték; a végén F = N, Z
    "LDA": ["ld b,a", "or a"],
    "LDX": ["ld c,a", "or a"],
    "LDY": ["ld ixh,a", "or a"],
    "LAX": ["ld b,a", "ld c,a", "or a"],
    "AND": ["and b", "ld b,a"],
    "ORA": ["or b", "ld b,a"],
    "EOR": ["xor b", "ld b,a"],
    "ADC": ["call do_adc"],
    "SBC": ["call do_sbc"],
    "CMP": ["ld l,a", "ld a,b", "sub l", "ccf"] + STC,
    "CPX": ["ld l,a", "ld a,c", "sub l", "ccf"] + STC,
    "CPY": ["ld l,a", "ld a,ixh", "sub l", "ccf"] + STC,
    "BIT": ["call do_bit"],
    "ANC": ["and b", "ld b,a", "push af", "rlca", "and 1", "ld ixl,a", "pop af"],
    "ALR": ["and b", "srl a", "ld b,a"] + STC,
    "SBX": ["ld l,a", "ld a,c", "and b", "sub l", "ld c,a", "ccf"] + STC,
}
RMW = {   # (HL) = a módosítandó bájt
    "ASL": ["sla (hl)"] + STC,
    "LSR": ["srl (hl)"] + STC,
    "ROL": ["ld a,ixl", "rra", "rl (hl)"] + STC,
    "ROR": ["ld a,ixl", "rra", "rr (hl)"] + STC,
    "INC": ["inc (hl)"],
    "DEC": ["dec (hl)"],
}
COMBO = {"SLO": ("ASL", "ORA"), "RLA": ("ROL", "AND"), "SRE": ("LSR", "EOR"),
         "RRA": ("ROR", "ADC"), "DCP": ("DEC", "CMP"), "ISC": ("INC", "SBC")}
ACC = {
    "ASL": ["sla b"] + STC,
    "LSR": ["srl b"] + STC,
    "ROL": ["ld a,ixl", "rra", "rl b"] + STC,
    "ROR": ["ld a,ixl", "rra", "rr b"] + STC,
}
STORE = {"STA": ("A", ["ld (hl),b"]), "STX": ("X", ["ld (hl),c"]),
         "STY": ("Y", ["ld a,ixh", "ld (hl),a"]),
         "SAX": ("SAX", ["push af", "ld a,b", "and c", "ld (hl),a", "pop af"])}
SP = ["ld hl,(rS)"]                 # L = S, H = a verem lapja (rS után STKPG)
IMP = {
    "NOP": [],
    "CLC": ["ld a,0", "ld ixl,a"], "SEC": ["ld a,1", "ld ixl,a"],
    "CLD": ["ld a,0", "ld (fD),a"], "SED": ["ld a,08h", "ld (fD),a"],
    "CLI": ["ld a,0", "ld (fI),a"], "SEI": ["ld a,04h", "ld (fI),a"],
    "CLV": ["ld a,0", "ld (fV),a"],
    "TAX": ["ld c,b", "inc c", "dec c"], "TAY": ["ld a,b", "ld ixh,a", "or a"],
    "TXA": ["ld b,c", "inc b", "dec b"], "TYA": ["ld a,ixh", "ld b,a", "or a"],
    "TSX": ["ld a,(rS)", "ld c,a", "or a"], "TXS": ["ld a,c", "ld (rS),a"],
    "INX": ["inc c"], "DEX": ["dec c"], "INY": ["inc ixh"], "DEY": ["dec ixh"],
    "PHA": EXA + SP + ["ld (hl),b", "dec l", "ld a,l", "ld (rS),a"] + EXA,
    "PLA": SP + ["inc l", "ld a,l", "ld (rS),a", "ld a,(hl)", "ld b,a", "or a"],
    "PHP": ["push af", "call getp"] + SP + ["ld (hl),a", "dec l", "ld a,l", "ld (rS),a", "pop af"],
    "PLP": SP + ["inc l", "ld a,l", "ld (rS),a", "ld a,(hl)", "call setp"],
}
BRANCH = {"BPL": "p", "BMI": "m", "BEQ": "z", "BNE": "nz"}
BRMEM = {"BCC": (["ld a,ixl", "rra"], "nc"), "BCS": (["ld a,ixl", "rra"], "c"),
         "BVC": (["ld a,(fV)", "and 4"], "z"), "BVS": (["ld a,(fV)", "and 4"], "nz")}

OPS = {}
def group(mn, codes):
    for c, m in codes:
        OPS[c] = (mn, m)

for mn, b in (("ORA", 0x00), ("AND", 0x20), ("EOR", 0x40), ("ADC", 0x60), ("LDA", 0xA0),
              ("CMP", 0xC0), ("SBC", 0xE0)):
    group(mn, [(b + 0x01, "indx"), (b + 0x05, "zp"), (b + 0x09, "imm"), (b + 0x0D, "abs"),
               (b + 0x11, "indy"), (b + 0x15, "zpx"), (b + 0x19, "absy"), (b + 0x1D, "absx")])
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
    OPS[c] = (mn, "rel")
for c, mn in ((0x08, "PHP"), (0x18, "CLC"), (0x28, "PLP"), (0x38, "SEC"), (0x48, "PHA"), (0x58, "CLI"),
              (0x68, "PLA"), (0x78, "SEI"), (0x88, "DEY"), (0x8A, "TXA"), (0x98, "TYA"), (0x9A, "TXS"),
              (0xA8, "TAY"), (0xAA, "TAX"), (0xB8, "CLV"), (0xBA, "TSX"), (0xC8, "INY"), (0xCA, "DEX"),
              (0xD8, "CLD"), (0xE8, "INX"), (0xEA, "NOP"), (0xF8, "SED")):
    OPS[c] = (mn, "imp")
OPS[0x00] = ("BRK", "imp"); OPS[0x20] = ("JSR", "abs"); OPS[0x40] = ("RTI", "imp")
OPS[0x60] = ("RTS", "imp"); OPS[0x4C] = ("JMP", "abs"); OPS[0x6C] = ("JMP", "ind")
# nem dokumentált utasítások (a lejátszórutinokban előfordulók)
for mn, b in (("SLO", 0x00), ("RLA", 0x20), ("SRE", 0x40), ("RRA", 0x60), ("DCP", 0xC0), ("ISC", 0xE0)):
    group(mn, [(b + 0x03, "indx"), (b + 0x07, "zp"), (b + 0x0F, "abs"), (b + 0x13, "indy"),
               (b + 0x17, "zpx"), (b + 0x1B, "absy"), (b + 0x1F, "absx")])
group("SAX", [(0x83, "indx"), (0x87, "zp"), (0x8F, "abs"), (0x97, "zpy")])
group("LAX", [(0xA3, "indx"), (0xA7, "zp"), (0xAF, "abs"), (0xB3, "indy"), (0xB7, "zpy"),
              (0xBF, "absy"), (0xAB, "imm")])
for c in (0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA):
    OPS[c] = ("NOP", "imp")
for c, m in [(0x80, "imm"), (0x82, "imm"), (0x89, "imm"), (0xC2, "imm"), (0xE2, "imm"),
             (0x04, "zp"), (0x44, "zp"), (0x64, "zp"), (0x0C, "abs")] + \
        [(c, "zpx") for c in (0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4)] + \
        [(c, "absx") for c in (0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC)]:
    OPS[c] = ("NOPR", m)
OPS[0xEB] = ("SBC", "imm"); OPS[0x0B] = ("ANC", "imm"); OPS[0x2B] = ("ANC", "imm")
OPS[0x4B] = ("ALR", "imm"); OPS[0xCB] = ("SBX", "imm")

def body(code):
    mn, mode = OPS[code]
    if mn == "BRK":
        return ["jp emu_brk"]
    if mn == "NOPR":
        return ["inc de"] * (2 if mode in ("abs", "absx") else 1) + NEXT
    if mn in ALU:
        return read_value(mode) + ALU[mn] + NEXT
    if mn in STORE:
        var, st = STORE[mn]
        p, slow = write_ptr(mode, var)
        return p + st + NEXT + slow
    if mn in RMW:
        if mode == "acc":
            return ACC[mn] + NEXT
        p, slow = write_ptr(mode, "R")
        return p + RMW[mn] + NEXT + slow
    if mn in COMBO:
        r, a = COMBO[mn]
        p, slow = write_ptr(mode, "R")
        return p + RMW[r] + ["ld a,(hl)"] + ALU[a] + NEXT + slow
    if mn in IMP:
        return IMP[mn] + NEXT
    if mn in BRANCH:
        return ["jp %s,br_taken" % BRANCH[mn], "inc de"] + NEXT
    if mn in BRMEM:
        t, cc = BRMEM[mn]
        return EXA + t + ["jp %s,br_taken_alt" % cc] + EXA + ["inc de"] + NEXT
    if mn == "JMP" and mode == "abs":
        return FA + ["ld h,RT>>8", "ld h,(hl)", "ld l,a", "ex de,hl"] + NEXT
    if mn == "JMP":
        return FA + ["ld h,RT>>8", "ld h,(hl)", "ld l,a", "ld a,(hl)", "inc l", "ld l,(hl)",
                     "ld h,RT>>8", "ld h,(hl)", "ld l,a", "ex de,hl"] + NEXT
    if mn == "JSR":     # a verembe a JSR utolsó bájtjának 6502-es címe kerül
        return EXA + ["inc de", "ld h,INV>>8", "ld l,d", "ld a,(hl)"] + SP + \
            ["ld (hl),a", "dec l", "ld (hl),e", "dec l", "ld a,l", "ld (rS),a",
             "ex de,hl", "ld a,(hl)", "dec hl", "ld e,(hl)", "ld l,a", "ld h,RT>>8",
             "ld d,(hl)"] + EXA + NEXT
    if mn == "RTS":
        return EXA + SP + ["inc l", "ld e,(hl)", "inc l", "ld d,(hl)", "ld a,l", "ld (rS),a",
                           "ld hl,stop_s", "cp (hl)", "jp z,emu_exit_alt",
                           "ld l,d", "ld h,RT>>8", "ld d,(hl)", "inc de"] + EXA + NEXT
    if mn == "RTI":
        return SP + ["inc l", "ld a,(hl)", "push af", "inc l", "ld e,(hl)", "inc l", "ld d,(hl)",
                     "ld a,l", "ld (rS),a", "ld hl,stop_s", "cp (hl)", "jr z,.x",
                     "ld l,d", "ld h,RT>>8", "ld d,(hl)", "pop af", "call setp"] + NEXT + \
            [".x:", "pop af", "call setp", "jp emu_exit"]
    raise ValueError((code, mn, mode))

def fmt(lines):
    return [l if l.endswith(":") else "            " + l for l in lines]

COMMON = """
; belépés: a regiszterek betöltve, DE = a PC (lásd sidplay.asm emu_run)
emu_next:
@NEXT@
; elágazás: DE = az eltolás bájtja
br_taken:   ex af,af'
br_taken_alt:
            ld a,(de)
            inc de
            ld l,a
            rla
            sbc a,a
            ld h,a
            add hl,de
            ex de,hl
            ex af,af'
@NEXT@
emu_exit_alt:
            ex af,af'
            jp emu_exit

; ADC/SBC: A = operandus
do_adc:     ld l,a
            ld a,(fD)
            or a
            jr nz,.dec
            ld a,ixl
            rra
            ld a,b
            adc a,l
            ld b,a
            push af
            pop hl
            ld a,l
            ld ixl,a
            ld (fV),a
            ret
.dec:       ld a,ixl
            rra
            ld a,b
            adc a,l
            daa
            ld b,a
            push af
            pop hl
            ld a,l
            ld ixl,a
            ret
do_sbc:     ld l,a
            ld a,(fD)
            or a
            jr nz,.dec
            ld a,ixl
            cpl
            rra
            ld a,b
            sbc a,l
            ld b,a
            ccf
            push af
            pop hl
            ld a,l
            ld ixl,a
            ld (fV),a
            ret
.dec:       ld a,ixl
            cpl
            rra
            ld a,b
            sbc a,l
            daa
            ld b,a
            ccf
            push af
            pop hl
            ld a,l
            ld ixl,a
            ret
; BIT: A = M; Z = (A and M) = 0, N = M 7. bitje, V = M 6. bitje
do_bit:     ld l,a
            and b
            push af
            ld a,l
            pop hl                  ; L = F, A = M
            ld h,a
            and 40h
            rrca
            rrca
            rrca
            rrca
            ld (fV),a
            ld a,l
            and 7Fh
            ld l,a
            ld a,h
            and 80h
            or l
            ld l,a
            push hl
            pop af
            ret
; a P regiszter összerakása A-ba az élő jelzőkből (B és 5. bit = 1)
getp:       push af
            pop hl
            ld a,l
            and 80h
            ld h,a
            bit 6,l
            jr z,.nz
            set 1,h
.nz:        ld a,(fV)
            and 4
            jr z,.nv
            set 6,h
.nv:        ld a,ixl
            and 1
            or h
            ld h,a
            ld a,(fD)
            or h
            ld h,a
            ld a,(fI)
            or h
            or 30h
            ret
; A = P -> jelzők
setp:       ld l,a
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
            ld ixl,a
            ld a,l
            and 80h
            ld h,a
            ld a,l
            and 02h
            rrca
            rrca
            rrca
            or h
            ld l,a
            push hl
            pop af
            ret
""".replace("@NEXT@", "\n".join(fmt(NEXT)))

def main():
    sizes = None
    if len(sys.argv) > 2 and sys.argv[1] == "--sym":
        addr = {}
        for line in open(sys.argv[2]):
            if ": EQU " in line:
                k, v = line.split(": EQU ")
                k = k.strip()
                if k.startswith("op_") and len(k) == 5 or k == "op_end":
                    addr[k] = int(v, 16)
        order = sorted(addr.values())
        sizes = {int(k[3:], 16): order[order.index(a) + 1] - a
                 for k, a in addr.items() if k != "op_end"}
    out = ["; ============================================================================",
           "; cpu6502.asm - GENERÁLT FÁJL (tools/gen6502.py), kézzel ne módosítsd!",
           "; 6502-emulátor Z80-on a SID-lejátszóhoz.",
           "; ============================================================================",
           COMMON]
    bodies = {}
    for code in range(256):
        _lab[0] = 0
        b = body(code) if code in OPS else ["jp emu_brk"]
        bodies[code] = (["; %s %s" % OPS[code]] if code in OPS else ["; KIL / nem támogatott"]) + fmt(b)
    table = {}
    if sizes is None:               # 1. menet: sorban, csak a méretekhez
        for code in range(256):
            out += ["op_%02X:" % code] + bodies[code]
            table[code] = "op_%02X >> 8" % code
        out += ["op_end:"]
    else:                           # 2. menet: a cím alsó bájtja = opkód
        out += ["            align 256", "cpu_base:"]
        left, cur, placed = set(range(256)), 0, []
        while left:
            op = min(left, key=lambda o: (o - cur) % 256)
            t = cur + (o_gap := (op - cur) % 256)
            placed.append((t, op))
            cur = t + sizes[op]
            left.remove(op)
        for t, op in placed:
            out += ["            ds cpu_base + %d - $" % t, "op_%02X:" % op,
                    "            assert (op_%02X & 255) == %d" % (op, op)] + bodies[op]
            table[op] = "op_%02X >> 8" % op
        out += ["op_end:"]
    out += ["", "; az utasításkezelők címének felső bájtja (az alsó az opkód)",
            "            align 256", "OPHI:"]
    for i in range(0, 256, 8):
        out.append("            db " + ", ".join(table[c] for c in range(i, i + 8)))
    print("\n".join(out))

main()
