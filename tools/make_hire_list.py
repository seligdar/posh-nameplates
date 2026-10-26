"""List of character templates the player can hire for money in the base game -> scripts/np_hire.lua.

A template is "for hire" when one of the conversations that start when the player talks to it (its dialogue
packages, the packages they inherit from, and its own dialogue) has a line with a join-squad action
(DA_JOIN_SQUAD_WITH_EDIT 3, DA_JOIN_SQUAD_FAST 18) reached through a "player has N cats" condition
(DC_PLAYERMONEY 2). Conversations that need the speaker to be a prisoner, a slave, caged or in shackles do not
count: those are for captives, not for people you meet in a bar.

The script cannot read conversations in the game safely (the game's own lookups add entries to a map its worker
thread uses), so the list is made here from the base data and shipped with the mod.

Usage: make_hire_list.py <Kenshi folder> <out np_hire.lua>
"""
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from kmod import read_mod  # noqa: E402

BASE_FILES = ("gamedata.base", "rebirth.mod", "Newwworld.mod", "Dialogue.mod")
REMOVED = (2147483647, 2147483647, 2147483647)
DELETED16 = -2147483645
CHARACTER, DIALOGUE, DIALOGUE_PACKAGE = 1, 18, 73
JOIN_ACTIONS = {3, 18}
EV_PLAYER_TALK_TO_ME = 1
DC_PLAYERMONEY = 2
# imprisoned by target / by other, is imprisoned, deathrow, is slave, escaped slave, locked cage, locked shackles
CAPTIVE_CONDITIONS = {7, 8, 14, 15, 58, 61, 62, 63}
MAX_DEPTH = 60


@dataclass
class Rec:
    rtype: int
    name: str
    fields: dict[str, object] = field(default_factory=dict)
    refs: dict[str, dict[str, tuple[int, int, int]]] = field(default_factory=dict)
    deleted: bool = False


def merged_base(kenshi: Path) -> dict[str, Rec]:
    """The base files merged in load order, like the game does it."""
    table: dict[str, Rec] = {}
    for name in BASE_FILES:
        for r in read_mod(kenshi / "data" / name).records:
            m = table.setdefault(r.sid, Rec(r.rtype, r.name))
            if r.name:
                m.name = r.name
            m.fields.update(r.fields)
            for cat, refs in r.refs.items():
                dst = m.refs.setdefault(cat, {})
                for target, value in refs.items():
                    if value == REMOVED:
                        dst.pop(target, None)
                    else:
                        dst[target] = value
            if r.change == DELETED16 or m.fields.get("b:REMOVED"):
                m.deleted = True
    return table


class HireScan:
    def __init__(self, table: dict[str, Rec]) -> None:
        self.t = table
        self.memo: dict[tuple[str, bool], bool] = {}

    def alive(self, sid: str) -> bool:
        r = self.t.get(sid)
        return r is not None and not r.deleted

    def condition_names(self, r: Rec) -> list[tuple[int, int, int, int]]:
        """(condition, who, compare by, value) of a dialogue or line"""
        out = []
        for c, v in r.refs.get("conditions", {}).items():
            if c in self.t:
                f = self.t[c].fields
                out.append((f.get("i:condition name"), f.get("i:who", 0), f.get("i:compare by", 0), v[0]))
        return out

    def has_money_condition(self, r: Rec) -> bool:
        return any(c[0] == DC_PLAYERMONEY for c in self.condition_names(r))

    def captive_only(self, r: Rec) -> bool:
        return any(c[0] in CAPTIVE_CONDITIONS and c[1] == 0 and c[2] == 0 and c[3] != 0 for c in self.condition_names(r))

    def paid_join(self, sid: str, paid: bool, depth: int) -> bool:
        key = (sid, paid)
        if key in self.memo:
            return self.memo[key]
        self.memo[key] = False                      # a line reached again on its own path ends the walk
        if depth > MAX_DEPTH or not self.alive(sid):
            return False
        r = self.t[sid]
        paid = paid or self.has_money_condition(r)
        found = paid and any(a in self.t and self.t[a].fields.get("i:action name") in JOIN_ACTIONS
                             for a in r.refs.get("effects", {}))
        if not found:
            found = any(self.paid_join(c, paid, depth + 1) for c in r.refs.get("lines", {}))
        self.memo[key] = found
        return found

    def dialogue_hires(self, sid: str) -> bool:
        r = self.t[sid]
        if r.rtype != DIALOGUE or self.captive_only(r):
            return False
        paid = self.has_money_condition(r)
        return any(self.paid_join(line, paid, 0) for line in r.refs.get("lines", {}))

    def talk_dialogues(self, package: str, seen: set[str]) -> list[str]:
        if package in seen or not self.alive(package):
            return []
        seen.add(package)
        r = self.t[package]
        out = [d for d, v in r.refs.get("dialogs", {}).items() if self.alive(d) and v[0] == EV_PLAYER_TALK_TO_ME]
        for parent in r.refs.get("inheritsFrom", {}):
            out += self.talk_dialogues(parent, seen)
        return out

    def for_hire(self, r: Rec) -> bool:
        dialogues: set[str] = set()
        for key in ("dialogue package", "dialogue package player"):
            for p in r.refs.get(key, {}):
                dialogues.update(self.talk_dialogues(p, set()))
        dialogues.update(d for d in r.refs.get("dialogue", {}) if self.alive(d))
        return any(self.dialogue_hires(d) for d in dialogues)


def lua_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> None:
    kenshi, out = Path(sys.argv[1]), Path(sys.argv[2])
    table = merged_base(kenshi)
    scan = HireScan(table)
    hire = sorted(((sid, r.name) for sid, r in table.items()
                   if r.rtype == CHARACTER and not r.deleted and scan.for_hire(r)), key=lambda x: (x[1], x[0]))
    lines = [
        "-- np_hire: character templates the player can hire for money in the base game (string id = template name).",
        "-- Generated by tools/make_hire_list.py from the base game data; edit that instead.",
        "return {",
    ]
    lines += [f"    [{lua_string(sid)}] = true,  -- {name}" for sid, name in hire]
    lines += ["}", ""]
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(hire)} templates for hire -> {out}")


if __name__ == "__main__":
    main()
