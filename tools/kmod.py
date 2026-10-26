"""Reader for Kenshi .mod / .base files (FCS format 16 and 17)."""
import struct
from dataclasses import dataclass, field
from pathlib import Path

NEW, CHANGED, DELETED = -2147483646, -2147483647, -2147483645


@dataclass
class Record:
    rtype: int
    name: str
    sid: str
    change: int
    fields: dict[str, object] = field(default_factory=dict)
    refs: dict[str, dict[str, tuple[int, int, int]]] = field(default_factory=dict)
    instances: dict[str, str] = field(default_factory=dict)


@dataclass
class ModFile:
    ftype: int
    author: str
    deps: list[str]
    refs: list[str]
    records: list[Record]


class Reader:
    def __init__(self, data: bytes) -> None:
        self.b = data
        self.p = 0

    def i32(self) -> int:
        v = struct.unpack_from("<i", self.b, self.p)[0]
        self.p += 4
        return v

    def f32(self) -> float:
        v = struct.unpack_from("<f", self.b, self.p)[0]
        self.p += 4
        return v

    def u8(self) -> int:
        v = self.b[self.p]
        self.p += 1
        return v

    def s(self) -> str:
        n = self.i32()
        if n < 0 or self.p + n > len(self.b):
            raise ValueError(f"bad string length {n} at {self.p - 4}")
        v = self.b[self.p:self.p + n].decode("utf-8", errors="replace")
        self.p += n
        return v


def split(s: str) -> list[str]:
    return [x.strip() for x in s.split(",") if x.strip()]


def read_record(r: Reader, ftype: int) -> Record:
    r.i32()  # instance count / unused
    rtype = r.i32()
    r.i32()  # numeric id
    name = r.s()
    sid = r.s()
    change = r.i32()
    rec = Record(rtype, name, sid, change)
    for _ in range(r.i32()):
        k = r.s(); rec.fields["b:" + k] = r.u8()
    for _ in range(r.i32()):
        k = r.s(); rec.fields["f:" + k] = r.f32()
    for _ in range(r.i32()):
        k = r.s(); rec.fields["i:" + k] = r.i32()
    for _ in range(r.i32()):
        k = r.s(); rec.fields["v3:" + k] = (r.f32(), r.f32(), r.f32())
    for _ in range(r.i32()):
        k = r.s(); rec.fields["v4:" + k] = (r.f32(), r.f32(), r.f32(), r.f32())
    for _ in range(r.i32()):
        k = r.s(); rec.fields["s:" + k] = r.s()
    for _ in range(r.i32()):
        k = r.s(); rec.fields["file:" + k] = r.s()
    for _ in range(r.i32()):
        cat = r.s()
        d: dict[str, tuple[int, int, int]] = {}
        for _ in range(r.i32()):
            t = r.s(); d[t] = (r.i32(), r.i32(), r.i32())
        rec.refs[cat] = d
    for _ in range(r.i32()):
        iid = r.s(); target = r.s()
        for _ in range(7):
            r.f32()
        for _ in range(r.i32()):
            r.s()
        rec.instances[iid] = target
    return rec


def read_mod(path: Path) -> ModFile:
    r = Reader(path.read_bytes())
    ftype = r.i32()
    if ftype == 17:
        hlen = r.i32()
        start = r.p
        r.i32()
        author, _desc, deps, refs = r.s(), r.s(), r.s(), r.s()
        r.p = start + hlen
        r.i32()  # last id
    elif ftype == 16:
        r.i32()
        author, _desc, deps, refs = r.s(), r.s(), r.s(), r.s()
        r.i32()
    else:
        raise ValueError(f"unsupported mod type {ftype}: {path}")
    count = r.i32()
    records = [read_record(r, ftype) for _ in range(count)]
    if r.p != len(r.b):
        raise ValueError(f"{path}: parsed {r.p} of {len(r.b)} bytes")
    return ModFile(ftype, author, split(deps), split(refs), records)
