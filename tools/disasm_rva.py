"""Disassemble around an RVA of the cached title image and resolve string references.

Usage: python disasm_rva.py <rva-hex> [count]
Reads the image at %LOCALAPPDATA%\\victory\\cache\\images\\victory-image-*.dll, maps the RVA
through the PE section table, disassembles `count` instructions (default 120) from the previous
`cc cc` padding (a function start if one is within 4 KiB), and prints every RIP-relative
reference with the printable text it points at.
"""
import os
import struct
import sys

from capstone import Cs, CS_ARCH_X86, CS_MODE_64

IMAGE = os.path.join(
    os.environ["LOCALAPPDATA"],
    "victory",
    "cache",
    "images",
    "victory-image-b99f876b74d4a77f.dll",
)


def load():
    data = open(IMAGE, "rb").read()
    lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    opt_size = struct.unpack_from("<H", data, lfanew + 0x14)[0]
    n_sect = struct.unpack_from("<H", data, lfanew + 6)[0]
    table_at = lfanew + 0x18 + opt_size
    sections = []
    for i in range(n_sect):
        off = table_at + i * 40
        name = data[off : off + 8].rstrip(b"\0").decode("latin1")
        vsize, va, raw_size, raw = struct.unpack_from("<IIII", data, off + 8)
        sections.append((name, va, va + vsize, raw, raw_size))
    return data, sections


def to_offset(sections, rva):
    for _, va, vend, raw, _ in sections:
        if va <= rva < vend:
            return raw + (rva - va)
    return None


def cstring(data, sections, rva, limit=120):
    off = to_offset(sections, rva)
    if off is None or off >= len(data):
        return None
    end = data.find(b"\0", off, off + limit)
    if end < 0:
        return None
    text = data[off:end]
    if len(text) < 4:
        return None
    try:
        return text.decode("utf-8")
    except UnicodeDecodeError:
        return None


def main():
    rva = int(sys.argv[1], 16)
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    data, sections = load()
    back = 0
    while back < 4096:
        b = to_offset(sections, rva - back - 2)
        if b is not None and data[b : b + 2] == b"\xcc\xcc":
            back += 2
            break
        back += 1
    start = rva - back
    off = to_offset(sections, start)
    code = data[off : off + 1200]
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    print(f"function guess 0x{start:x} (target 0x{rva:x}, {back} bytes of padding before)")
    for insn in md.disasm(code, start):
        note = ""
        for op in insn.operands:
            if op.type == 3 and op.mem.base == 0x29:  # RIP
                target = insn.address + insn.size + op.mem.disp
                text = cstring(data, sections, target)
                if text:
                    note = f'   ; 0x{target:x} "{text}"'
                else:
                    note = f"   ; 0x{target:x}"
        print(f"0x{insn.address:x}  {insn.mnemonic:<7} {insn.op_str}{note}")
        count -= 1
        if count <= 0:
            break


if __name__ == "__main__":
    main()
