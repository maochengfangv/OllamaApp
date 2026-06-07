import argparse
import json
import os
import re
import struct
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple
from urllib.parse import quote


@dataclass(frozen=True)
class LinkMapSymbol:
    address: int
    size: int
    object_index: Optional[int]
    name: str
    raw: str


@dataclass(frozen=True)
class LinkMapParseResult:
    object_files: Dict[int, str]
    symbols: List[LinkMapSymbol]


def parse_int(value: str) -> int:
    value = value.strip()
    if value.lower().startswith("0x"):
        return int(value, 16)
    return int(value, 10)


def parse_linkmap(path: str) -> LinkMapParseResult:
    object_files: Dict[int, str] = {}
    symbols: List[LinkMapSymbol] = []

    section = None
    object_line = re.compile(r"^\[\s*(\d+)\]\s+(.*)$")
    symbol_line = re.compile(r"^(0x[0-9a-fA-F]+|\d+)\s+(0x[0-9a-fA-F]+|\d+)\s+\[\s*(\d+)\]\s+(.*)$")
    symbol_line_no_index = re.compile(r"^(0x[0-9a-fA-F]+|\d+)\s+(0x[0-9a-fA-F]+|\d+)\s+(.*)$")

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw_line in f:
            line = raw_line.rstrip("\n")

            if line.startswith("#"):
                if line.startswith("# Object files:"):
                    section = "objects"
                elif line.startswith("# Symbols:"):
                    section = "symbols"
                else:
                    continue
                continue

            if not line.strip():
                continue

            if section == "objects":
                m = object_line.match(line)
                if m:
                    idx = int(m.group(1))
                    object_files[idx] = m.group(2).strip()
                continue

            if section == "symbols":
                m = symbol_line.match(line)
                if m:
                    address = parse_int(m.group(1))
                    size = parse_int(m.group(2))
                    obj_idx = int(m.group(3))
                    name = m.group(4).strip()
                    symbols.append(LinkMapSymbol(address=address, size=size, object_index=obj_idx, name=name, raw=line))
                    continue

                m = symbol_line_no_index.match(line)
                if m:
                    address = parse_int(m.group(1))
                    size = parse_int(m.group(2))
                    name = m.group(3).strip()
                    symbols.append(LinkMapSymbol(address=address, size=size, object_index=None, name=name, raw=line))
                    continue

    return LinkMapParseResult(object_files=object_files, symbols=symbols)


def derive_module_name(object_path: str, main_module: str) -> str:
    p = object_path.strip()

    m = re.search(r"([^/]+\.framework)/", p)
    if m:
        return m.group(1)

    m = re.search(r"([^/]+\.a)\(", p)
    if m:
        return m.group(1)

    m = re.search(r"/([^/]+)\.build/", p)
    if m:
        return m.group(1)

    if p.endswith(".o"):
        return main_module

    base = os.path.basename(p)
    return base or main_module


def symbol_is_marked(symbol_name: str, mark: str) -> bool:
    return mark in symbol_name


def aggregate_linkmap(
    parsed: LinkMapParseResult,
    main_module: str,
    mark: str,
    only_marked: bool,
) -> Dict[str, int]:
    totals: Dict[str, int] = {}

    for sym in parsed.symbols:
        if only_marked and not symbol_is_marked(sym.name, mark):
            continue

        obj_path = parsed.object_files.get(sym.object_index or -1, "")
        module = derive_module_name(obj_path, main_module)
        totals[module] = totals.get(module, 0) + sym.size

    return totals


@dataclass(frozen=True)
class MachOSectionSize:
    segment: str
    section: str
    size: int


@dataclass(frozen=True)
class MachOSizeReport:
    arch: str
    segments: Dict[str, int]
    sections: Dict[Tuple[str, str], int]


FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA
FAT_MAGIC_64 = 0xCAFEBABF
FAT_CIGAM_64 = 0xBFBAFECA

MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE

LC_SEGMENT_64 = 0x19

CPU_TYPE_ARM64 = 0x0100000C
CPU_TYPE_X86_64 = 0x01000007


def _read_struct(f, offset: int, fmt: str, endian: str) -> Tuple:
    size = struct.calcsize(fmt)
    f.seek(offset)
    data = f.read(size)
    return struct.unpack(endian + fmt, data)


def _decode_cstr(raw16: bytes) -> str:
    return raw16.split(b"\x00", 1)[0].decode("utf-8", errors="replace")


def _pick_fat_slice(f, prefer_arch: str) -> Tuple[int, int, str]:
    magic = _read_struct(f, 0, "I", ">")[0]
    if magic not in (FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64):
        return (0, os.fstat(f.fileno()).st_size, "thin")

    endian = ">" if magic in (FAT_MAGIC, FAT_MAGIC_64) else "<"
    nfat = _read_struct(f, 0, "II", endian)[1]

    entries = []
    header_size = 8
    if magic in (FAT_MAGIC, FAT_CIGAM):
        arch_fmt = "iiIII"
        arch_size = struct.calcsize(endian + arch_fmt)
        for i in range(nfat):
            cputype, cpusubtype, offset, size, align = _read_struct(f, header_size + i * arch_size, arch_fmt, endian)
            entries.append((cputype, offset, size))
    else:
        arch_fmt = "iiQQI"
        arch_size = struct.calcsize(endian + arch_fmt)
        for i in range(nfat):
            cputype, cpusubtype, offset, size, align = _read_struct(f, header_size + i * arch_size, arch_fmt, endian)
            entries.append((cputype, offset, size))

    desired = CPU_TYPE_ARM64 if prefer_arch == "arm64" else CPU_TYPE_X86_64 if prefer_arch == "x86_64" else None
    if desired is not None:
        for cputype, off, size in entries:
            if cputype == desired:
                return (off, size, prefer_arch)

    cputype, off, size = entries[0]
    if cputype == CPU_TYPE_ARM64:
        return (off, size, "arm64")
    if cputype == CPU_TYPE_X86_64:
        return (off, size, "x86_64")
    return (off, size, str(cputype))


def macho_sizes(path: str, prefer_arch: str) -> MachOSizeReport:
    with open(path, "rb") as f:
        slice_off, slice_size, arch = _pick_fat_slice(f, prefer_arch=prefer_arch)
        magic = _read_struct(f, slice_off, "I", "<")[0]
        if magic == MH_MAGIC_64:
            endian = "<"
        elif magic == MH_CIGAM_64:
            endian = ">"
        else:
            raise ValueError(f"Unsupported Mach-O magic: 0x{magic:08x}")

        header = _read_struct(f, slice_off, "IiiIIII", endian)
        ncmds = header[4]
        sizeofcmds = header[5]
        cmd_off = slice_off + 32

        segments: Dict[str, int] = {}
        sections: Dict[Tuple[str, str], int] = {}

        cur = cmd_off
        for _ in range(ncmds):
            cmd, cmdsize = _read_struct(f, cur, "II", endian)
            if cmd == LC_SEGMENT_64:
                raw = f.read(cmdsize)
                segname = _decode_cstr(raw[8:24])
                vmaddr, vmsize, fileoff, filesize = struct.unpack(endian + "QQQQ", raw[24:24 + 32])
                nsects = struct.unpack(endian + "I", raw[64:68])[0]
                segments[segname] = segments.get(segname, 0) + int(filesize)

                sect_off = 72
                for i in range(nsects):
                    base = sect_off + i * 80
                    sectname = _decode_cstr(raw[base:base + 16])
                    segname2 = _decode_cstr(raw[base + 16:base + 32])
                    sect_size = struct.unpack(endian + "Q", raw[base + 40:base + 48])[0]
                    key = (segname2, sectname)
                    sections[key] = sections.get(key, 0) + int(sect_size)
            cur += cmdsize

        return MachOSizeReport(arch=arch, segments=segments, sections=sections)


def diff_int_map(a: Dict[str, int], b: Dict[str, int]) -> List[Tuple[str, int, int, int]]:
    keys = set(a.keys()) | set(b.keys())
    rows = []
    for k in keys:
        av = a.get(k, 0)
        bv = b.get(k, 0)
        rows.append((k, av, bv, bv - av))
    rows.sort(key=lambda x: abs(x[3]), reverse=True)
    return rows


def diff_section_map(a: Dict[Tuple[str, str], int], b: Dict[Tuple[str, str], int]) -> List[Tuple[str, str, int, int, int]]:
    keys = set(a.keys()) | set(b.keys())
    rows = []
    for seg, sect in keys:
        av = a.get((seg, sect), 0)
        bv = b.get((seg, sect), 0)
        rows.append((seg, sect, av, bv, bv - av))
    rows.sort(key=lambda x: abs(x[4]), reverse=True)
    return rows


def format_bytes(n: int) -> str:
    sign = "-" if n < 0 else ""
    n = abs(n)
    if n < 1024:
        return f"{sign}{n} B"
    if n < 1024 * 1024:
        return f"{sign}{n / 1024:.2f} KB"
    return f"{sign}{n / (1024 * 1024):.2f} MB"


def print_table(rows: Iterable[Tuple], headers: List[str], limit: Optional[int]) -> None:
    rows = list(rows)
    if limit is not None:
        rows = rows[:limit]

    cols = len(headers)
    widths = [len(h) for h in headers]
    for r in rows:
        for i in range(cols):
            widths[i] = max(widths[i], len(str(r[i])))

    def line(parts: List[str]) -> str:
        return "  ".join(p.ljust(widths[i]) for i, p in enumerate(parts))

    print(line(headers))
    print(line(["-" * w for w in widths]))
    for r in rows:
        print(line([str(x) for x in r]))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--linkmap-a", dest="linkmap_a")
    ap.add_argument("--linkmap-b", dest="linkmap_b")
    ap.add_argument("--macho-a", dest="macho_a")
    ap.add_argument("--macho-b", dest="macho_b")
    ap.add_argument("--main-module", default="App")
    ap.add_argument("--mark", default="[O]")
    ap.add_argument("--all-symbols", action="store_true")
    ap.add_argument("--arch", default="arm64", choices=["arm64", "x86_64"])
    ap.add_argument("--top", type=int, default=50)
    ap.add_argument("--json-out", dest="json_out")
    args = ap.parse_args()

    report: Dict[str, object] = {
        "inputs": {
            "linkmap_a": args.linkmap_a,
            "linkmap_b": args.linkmap_b,
            "macho_a": args.macho_a,
            "macho_b": args.macho_b,
            "main_module": args.main_module,
            "mark": args.mark,
            "only_marked": not args.all_symbols,
            "arch": args.arch,
        }
    }

    if args.linkmap_a and args.linkmap_b:
        parsed_a = parse_linkmap(args.linkmap_a)
        parsed_b = parse_linkmap(args.linkmap_b)
        agg_a = aggregate_linkmap(parsed_a, main_module=args.main_module, mark=args.mark, only_marked=not args.all_symbols)
        agg_b = aggregate_linkmap(parsed_b, main_module=args.main_module, mark=args.mark, only_marked=not args.all_symbols)

        rows = diff_int_map(agg_a, agg_b)
        pretty = [(k, format_bytes(a), format_bytes(b), format_bytes(d)) for (k, a, b, d) in rows]
        print("\nLinkMap module size diff")
        print_table(pretty, ["Module", "A", "B", "Delta"], args.top)

        report["linkmap"] = {
            "module_bytes_a": agg_a,
            "module_bytes_b": agg_b,
            "diff": [{"module": k, "a": a, "b": b, "delta": d} for (k, a, b, d) in rows],
        }
    elif args.linkmap_a:
        parsed = parse_linkmap(args.linkmap_a)
        agg = aggregate_linkmap(parsed, main_module=args.main_module, mark=args.mark, only_marked=not args.all_symbols)
        rows = sorted(((k, v) for k, v in agg.items()), key=lambda x: x[1], reverse=True)
        pretty = [(k, format_bytes(v)) for (k, v) in rows]
        print("\nLinkMap module size")
        print_table(pretty, ["Module", "Size"], args.top)
        report["linkmap"] = {"module_bytes": agg}

    if args.macho_a and args.macho_b:
        a = macho_sizes(args.macho_a, prefer_arch=args.arch)
        b = macho_sizes(args.macho_b, prefer_arch=args.arch)

        seg_rows = diff_int_map(a.segments, b.segments)
        seg_pretty = [(k, format_bytes(av), format_bytes(bv), format_bytes(dv)) for (k, av, bv, dv) in seg_rows]
        print("\nMach-O segment filesize diff")
        print_table(seg_pretty, ["Segment", "A", "B", "Delta"], args.top)

        sect_rows = diff_section_map(a.sections, b.sections)
        sect_pretty = [(f"{seg},{sect}", format_bytes(av), format_bytes(bv), format_bytes(dv)) for (seg, sect, av, bv, dv) in sect_rows]
        print("\nMach-O section size diff")
        print_table(sect_pretty, ["Section", "A", "B", "Delta"], args.top)

        report["macho"] = {
            "arch_a": a.arch,
            "arch_b": b.arch,
            "segments_a": a.segments,
            "segments_b": b.segments,
            "segment_diff": [{"segment": k, "a": av, "b": bv, "delta": dv} for (k, av, bv, dv) in seg_rows],
            "sections_a": {f"{seg},{sect}": size for (seg, sect), size in a.sections.items()},
            "sections_b": {f"{seg},{sect}": size for (seg, sect), size in b.sections.items()},
            "section_diff": [{"segment": seg, "section": sect, "a": av, "b": bv, "delta": dv} for (seg, sect, av, bv, dv) in sect_rows],
        }
    elif args.macho_a:
        a = macho_sizes(args.macho_a, prefer_arch=args.arch)
        seg = sorted(a.segments.items(), key=lambda x: x[1], reverse=True)
        seg_pretty = [(k, format_bytes(v)) for (k, v) in seg]
        print("\nMach-O segment filesize")
        print_table(seg_pretty, ["Segment", "Size"], args.top)

        sect = sorted(((f"{s},{c}", v) for (s, c), v in a.sections.items()), key=lambda x: x[1], reverse=True)
        sect_pretty = [(k, format_bytes(v)) for (k, v) in sect]
        print("\nMach-O section size")
        print_table(sect_pretty, ["Section", "Size"], args.top)
        report["macho"] = {"arch": a.arch, "segments": a.segments, "sections": {f"{seg},{sect}": size for (seg, sect), size in a.sections.items()}}

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
