"""End-to-end checks of nameplates.lua in LuaJIT against a fake game (MyGUI 3.2 ImageBox rules, KenshiLua-like API)."""
import sys
from pathlib import Path

from lupa import luajit21 as lj

HERE = Path(__file__).parent
SRC = (HERE.parent / "mod" / "Nameplates" / "scripts" / "init" / "nameplates.lua").read_text(encoding="utf-8")
MOCK = (HERE / "mock_np.lua").read_text(encoding="utf-8")


FAKE_OGRE = r'''
local ffi = require("ffi")
pcall(ffi.cdef, "typedef struct { float m[16]; } NP_Matrix4;")
local function norm(x, y, z) local l = math.sqrt(x*x + y*y + z*z) return x/l, y/l, z/l end
local cx, cy, cz = 0, 60, 120
local fx, fy, fz = norm(0, -54, -120)
local rx, ry, rz = norm(-fz, 0, fx)
local ux, uy, uz = ry*fz - rz*fy, rz*fx - rx*fz, rx*fy - ry*fx
VIEW = ffi.new("NP_Matrix4")
-- camera-relative view without translation, as the real game's log showed
local v = { rx, ry, rz, 0,  ux, uy, uz, 0,  -fx, -fy, -fz, 0,  0, 0, 0, 1 }
for i = 1, 16 do VIEW.m[i-1] = v[i] end
PROJ = ffi.new("NP_Matrix4")
local t, a, n, f = math.tan(math.rad(45) / 2), 1920 / 1200, 1, 10000
local p = { 1/(a*t), 0, 0, 0,  0, 1/t, 0, 0,  0, 0, (f+n)/(n-f), 2*f*n/(n-f),  0, 0, -1, 0 }
for i = 1, 16 do PROJ.m[i-1] = p[i] end
FAKE_VTBL = ffi.new("uint8_t[64]")
FAKECAM = ffi.new("uintptr_t[2]")
FAKECAM[0] = ffi.cast("uintptr_t", FAKE_VTBL)
NP_TEST_OGRE = { NP_getViewMatrix = function() return VIEW end, NP_getProjMatrix = function() return PROJ end }
'''


class Game:
    def __init__(self, mode: str, modules_found: bool = True) -> None:
        self.mode = mode
        self.lua = lj.LuaRuntime(unpack_returned_tuples=True)
        scripts = (HERE.parent / "mod" / "Nameplates" / "scripts").as_posix()
        if modules_found:
            self.lua.execute(f"package.path = [[{scripts}/?.lua;]] .. package.path")
        self.lua.execute(MOCK)
        self.t = 0.0

    def load(self) -> None:
        code = SRC
        if self.mode == "exact":
            self.lua.execute(FAKE_OGRE)
            self.lua.execute("getPlayerInterface().camera.camera = FAKECAM")
            code = code.replace('pcall(ffi.load, "OgreMain_x64")', "pcall(function() return NP_TEST_OGRE end)")
            code = code.replace('ffi.C.GetModuleHandleA("OgreMain_x64.dll")', "ffi.C.GetModuleHandleA(nil)")
            code = code.replace('ffi.C.GetProcAddress(mod, "??_7Camera@Ogre@@6BMovableObject@1@@")', "ffi.cast('void*', FAKE_VTBL)")
            assert code != SRC
        self.lua.execute(code)
        logs = self.logs()
        assert any("loaded" in s for s in logs), logs

    def run(self, seconds: float, step: float = 1 / 60) -> None:
        n = int(round(seconds / step))
        for _ in range(n):
            self.t += step
            self.lua.execute(f"SIM_TIME = {self.t}; HANDLERS['MyGUI::Gui::eventFrameStart']({step})")

    def logs(self) -> list[str]:
        return list(self.lua.eval("LOG").values())

    def x(self, code: str) -> None:
        self.lua.execute(code)

    def e(self, expr: str):
        return self.lua.eval(expr)

    def plate(self, cid: str) -> dict:
        """Widgets drawn for one character's plate, found through its name caption."""
        name = self.e(f"(function() for _, c in ipairs(CHARS) do if c.id == '{cid}' then return c.name end end end)()")
        res = self.e(f'''(function()
            local out = {{}}
            local prefix = nil
            for _, w in ipairs(WIDGETS) do
                if w.kind == "text" and w:drawn() and w.caption:find("{name}", 1, true) == 1 then
                    prefix = w.name:sub(1, #w.name - 4)
                end
            end
            if prefix == nil then return nil end
            for _, w in ipairs(WIDGETS) do
                if w.name:sub(1, #prefix) == prefix then
                    local part = w.name:sub(#prefix + 1)
                    local d = w:drawn()
                    if d then
                        out[part] = {{ x = w.coord[1], y = w.coord[2], w = w.coord[3], h = w.coord[4], alpha = w.alpha,
                            colour = w.colour or w.textColour, caption = w.caption, layer = w.layerName,
                            uv = type(d) == "table" and d or nil }}
                    end
                end
            end
            return out
        end)()''')
        if res is None:
            return {}
        out = {}
        for k, v in res.items():
            d = dict(v.items())
            if d.get("colour") is not None:
                d["colour"] = tuple(d["colour"].values())
            if d.get("uv") is not None:
                d["uv"] = tuple(d["uv"].values())
            out[k] = d
        return out

    def drawn_groups(self) -> int:
        return self.e('''(function() local n = 0
            for _, w in ipairs(WIDGETS) do if w.kind == "image" and w.name:sub(-5) == "frame" and w.name:sub(-6) ~= "bframe" and w:drawn() then n = n + 1 end end
            return n end)()''')


def near(a: float, b: float, tol: float) -> bool:
    return abs(a - b) <= tol


def main(mode: str) -> None:
    print("=== mode", mode)
    g = Game(mode)
    g.x('''
        BANDITS = newFaction("Bandits", -100, false)
        TRADERS = newFaction("Traders", 10, false)
        FRIENDS = newFaction("Friends", 80, false)
        H = newChar("h1", -10, 0, { enemy = true, faction = BANDITS, name = "Bandit" })
        N = newChar("n1", 10, 0, { faction = TRADERS, name = "Trader" })
        S = newChar("s1", 0, 10, { player = true, faction = PLAYER_FACTION, name = "Hero" })
        F = newChar("f1", 20, -10, { faction = FRIENDS, name = "Friend" })
    ''')
    g.load()
    g.run(1.0)

    # 1 hostile plate: drawn, red, full bar, frame/fill from the right atlas rects, on the lowest layer
    p = g.plate("h1")
    for part in ("frame", "fill", "name"):
        assert part in p, (part, p.keys())
    assert p["name"]["caption"] == "Bandit"
    assert p["frame"]["layer"] == "Wallpaper"
    assert p["frame"]["uv"] == (0, 0, 108, 13), p["frame"]["uv"]
    assert p["fill"]["uv"] == (0, 16, 104, 9), p["fill"]["uv"]
    r, gr, b, _ = p["fill"]["colour"]
    assert r > 0.7 and gr < 0.3, p["fill"]["colour"]
    s = 1200 / 1080
    assert near(p["fill"]["w"], 104 * s, 1.5), p["fill"]["w"]
    assert p["frame"]["alpha"] > 0.85, p["frame"]["alpha"]
    assert p["name"]["y"] + p["name"]["h"] <= p["frame"]["y"] + 2, (p["name"], p["frame"])
    assert "trail" not in p and "bfill" not in p
    print("1 hostile plate: ok", {k: (v["x"], v["y"], v["w"], v["h"]) for k, v in p.items()})

    # 2 like a strategy game: everyone on screen has a plate, coloured by reaction
    pn, pf, ps = g.plate("n1"), g.plate("f1"), g.plate("s1")
    assert pn and pf and ps, (pn.keys(), pf.keys(), ps.keys())
    rn, gn, bn, _ = pn["fill"]["colour"]
    assert rn > 0.8 and gn > 0.6 and bn < 0.3, pn["fill"]["colour"]
    rf, gf, bf, _ = pf["fill"]["colour"]
    assert gf > rf and gf > 0.6, pf["fill"]["colour"]
    rs, gs, bs, _ = ps["fill"]["colour"]
    assert bs > rs and bs > 0.8, ps["fill"]["colour"]
    print("2 everyone on screen: neutral yellow, friend green, squad blue: ok")

    # 3 inside a building with the roof on: no plate; roof lifted: plate again
    g.x("HOUSE = { open = false }; N.building = HOUSE")
    g.run(1.0)
    assert g.plate("n1") == {}, "plate over a roof"
    g.x("HOUSE.open = true")
    g.run(1.0)
    assert g.plate("n1"), "no plate with the roof lifted"
    g.x("N.building = nil")
    g.x("N.medical.anatomy[2].flesh = 70")
    g.run(1.0)
    assert near(g.plate("n1")["fill"]["w"], 104 * s * 0.7, 2), g.plate("n1")["fill"]["w"]
    print("3 indoors hidden until the roof is lifted: ok")

    # 4 a hit: the bar slides down, the trail holds then follows
    g.x("H.medical.anatomy[2].flesh = 40")
    g.run(0.2)
    p = g.plate("h1")
    assert "trail" in p and near(p["trail"]["w"], 104 * s, 2), p.get("trail")
    assert p["fill"]["w"] < 104 * s * 0.6, p["fill"]["w"]
    g.run(2.5)
    p = g.plate("h1")
    assert near(p["fill"]["w"], 104 * s * 0.4, 2), p["fill"]["w"]
    assert "trail" not in p or p["trail"]["w"] - p["fill"]["w"] < 3, p.get("trail")
    assert "spark" in p
    print("4 damage trail: ok")

    # 5 blood loss shows the thin bar
    g.x("H.medical.blood = 60")
    g.run(0.5)
    p = g.plate("h1")
    assert "bframe" in p and "bfill" in p
    assert near(p["bfill"]["w"], 104 * s * 0.6, 2), p["bfill"]["w"]
    assert p["bframe"]["y"] > p["frame"]["y"], "blood bar must sit under the health bar"
    print("5 blood bar: ok")

    # 6 knocked out: dark red bar of distance to death, name suffix
    g.x("H.medical.unconcious = true; H.medical.anatomy[2].flesh = -30")
    g.run(1.0)
    p = g.plate("h1")
    assert p["name"]["caption"] == "Bandit (KO)", p["name"]["caption"]
    r, gr, b, _ = p["fill"]["colour"]
    assert r < 0.7 and gr < 0.15, p["fill"]["colour"]
    assert near(p["fill"]["w"], 104 * s * 0.7, 2), p["fill"]["w"]
    print("6 knocked out: ok")

    # 7 death: the plate fades out and its widgets go back to the pool
    g.x("H.medical.dead = true")
    g.run(1.5)
    assert g.plate("h1") == {}
    pooled = g.e("#WIDGETS")
    print("7 dead hidden: ok")

    # 8 unloaded character: plate removed without errors
    g.x("N.alive = false")
    g.run(1.0)
    assert g.plate("n1") == {}
    print("8 unloaded: ok")

    # 9 zoomed out like a strategy camera: plates stay, get smaller and switch to the small font
    full = g.plate("f1")["frame"]["w"]
    g.x("ZOOM = 7")
    g.run(2.0)
    small = g.plate("f1")
    assert small, "plate vanished when zoomed out"
    assert small["frame"]["w"] < full * 0.7, (small["frame"]["w"], full)
    font = g.e('''(function() for _, w in ipairs(WIDGETS) do if w.kind == "text" and w:drawn() and w.caption == "Friend" then return w.font end end end)()''')
    assert font == "Kenshi_StandardFont_Small", font
    # zoom in and out around the size thresholds: plates must never blink
    low = 1.0
    for k in range(40):
        g.x(f"ZOOM = {5 + (k % 2) * 2.5}")
        g.run(0.1)
        fr = g.plate("f1").get("frame")
        low = min(low, fr["alpha"] if fr else 0)
    assert low > 0.8, ("plate blinked while zooming", low)
    g.x("ZOOM = 1")
    g.run(2.0)
    back = g.plate("f1")
    assert near(back["frame"]["w"], full, 2), (back["frame"]["w"], full)
    print("9 zoom out shrinks, zoom wobble does not blink: ok", full, "->", small["frame"]["w"], "px")

    # 10 animal without a head bone: height from the appearance and the learned ratio
    g.x('A = newChar("a1", -5, 20, { enemy = true, faction = BANDITS, name = "Beak Thing", robot = true, appearanceHeight = 3.6 })')
    g.run(1.0)
    pa, ph = g.plate("a1"), g.plate("f1")
    assert pa, "animal plate missing"
    print("10 boneless body: ok", pa["frame"]["y"], "vs human", ph["frame"]["y"])

    # 11 widget pool: many hostiles, at most maxPlates drawn, no widget leak when they leave
    g.x('''for i = 1, 45 do newChar("m" .. i, (i % 9) * 4 - 16, math.floor(i / 9) * 4 - 8, { enemy = true, faction = BANDITS, name = "Mob" .. i }) end''')
    g.run(1.5)
    drawn = g.drawn_groups()
    assert drawn <= 40, drawn
    # crowds come and go; while old plates fade out new ones fade in, so the pool may grow a little
    # during a swap, but it must stop growing and stay under two full sets of plates
    counts = []
    prev = "m"
    for cycle in range(6):
        tag = f"c{cycle}_"
        g.x(f'for _, c in ipairs(CHARS) do if c.id:sub(1, {len(prev)}) == "{prev}" then c.alive = false end end')
        g.x(f'for i = 1, 45 do newChar("{tag}" .. i, (i % 9) * 4 - 16, math.floor(i / 9) * 4 - 8, '
            f'{{ enemy = true, faction = BANDITS, name = "{tag}" .. i }}) end')
        g.run(1.5)
        assert g.drawn_groups() <= 40, g.drawn_groups()
        counts.append(g.e("#WIDGETS"))
        prev = tag
    assert counts[-1] == counts[-2] == counts[-3], ("widget pool keeps growing", counts)
    assert counts[-1] <= 2 * 40 * 10, counts      # 10 widgets per plate
    print("11 plate cap and widget pool: ok", drawn, "plates, widgets per cycle", counts)

    # 13 other modes from the settings: "fighting" hides idle people, shows them in a fight, keeps them a while
    g.x("for _, c in ipairs(CHARS) do c.alive = false end")
    g.x('''
        Q = newChar("q1", 4, 4, { faction = TRADERS, name = "Quiet" })
        Z = newChar("z1", -4, 4, { player = true, faction = PLAYER_FACTION, name = "Me" })
        Nameplates.show("neutral", "fighting")
    ''')
    g.run(1.0)
    assert g.plate("q1") == {}, "idle neutral in fighting mode"
    g.x('HANDLERS["Character::_NV_hitByMeleeAttack"](Q)')   # a fight = a hit (the game's combat-mode call is unsafe)
    g.run(1.0)
    assert g.plate("q1"), "fighting neutral has no plate"
    g.run(1.0)
    assert g.plate("q1"), "plate must stay a few seconds after the fight"
    g.run(13.0)                                     # fightSeconds 10 after the hit + keepSeconds 3
    assert g.plate("q1") == {}, "plate stayed too long"
    # the selected character always gets a plate
    g.x("Nameplates.show('neutral', 'never'); PI.selectedObject = Q.handle")
    g.run(1.0)
    assert g.plate("q1"), "selected character has no plate"
    g.x("PI.selectedObject = nil; Nameplates.show('neutral', 'always')")
    # "near": hostile 100 m away from your people is hidden, at 40 m shown, no blink at the 60 m edge
    g.x('''Nameplates.show("hostile", "near")
        R = newChar("r1", 0, 4 - 1000, { enemy = true, faction = BANDITS, name = "Raider" })''')
    g.run(1.0)
    assert g.plate("r1") == {}, "far hostile shown in near mode"
    g.x("R.z = 4 - 400")
    g.run(1.0)
    assert g.plate("r1"), "near hostile hidden"
    low = 1.0
    for k in range(30):
        g.x(f"R.z = 4 - {595 + (k % 2) * 20}")
        g.run(0.2)
        fr = g.plate("r1").get("frame")
        low = min(low, fr["alpha"] if fr else 0)
    assert low > 0.8, ("plate blinked at the range edge", low)
    g.x("Nameplates.show('hostile', 'always')")
    print("13 fighting / selected / near modes, no blinking at the edge: ok")

    # 14 bounty: skull left of the name, gold amount right of it; trader: coins; both: skull then coins
    g.x("for _, c in ipairs(CHARS) do c.alive = false end")
    g.x('''
        WB = newChar("wb", -12, 4, { enemy = true, faction = BANDITS, name = "Wanted" }); WB.bounty = 12500
        TR = newChar("tr", 8, 4, { faction = TRADERS, name = "Merchant" }); TR.trader = true
        BT = newChar("bt", 4, 16, { faction = TRADERS, name = "Smuggler" }); BT.trader = true; BT.bounty = 3000
        PL = newChar("pl", 20, 16, { faction = TRADERS, name = "Plain" })
    ''')
    g.run(1.5)
    pw, pt, pb, pp = g.plate("wb"), g.plate("tr"), g.plate("bt"), g.plate("pl")
    assert pw["bicon"]["uv"] == (0, 48, 32, 32) and "ticon" not in pw, pw.keys()
    assert pw["amount"]["caption"] == "12 500", pw["amount"]["caption"]
    assert pw["bicon"]["x"] + pw["bicon"]["w"] <= pw["name"]["x"] + 3, (pw["bicon"], pw["name"])
    assert pw["amount"]["x"] >= pw["name"]["x"] + pw["name"]["w"] - 4, (pw["amount"], pw["name"])
    r, gr, b, _ = pw["amount"]["colour"]
    assert r > 0.9 and gr > 0.7 and b < 0.4, pw["amount"]["colour"]
    assert pt["ticon"]["uv"] == (32, 48, 32, 32) and "bicon" not in pt and "amount" not in pt, pt.keys()
    assert pb["bicon"]["x"] < pb["ticon"]["x"] < pb["name"]["x"], (pb["bicon"]["x"], pb["ticon"]["x"], pb["name"]["x"])
    assert "bicon" not in pp and "ticon" not in pp and "amount" not in pp, pp.keys()
    # the whole line is centred over the bar
    line_l = pw["bicon"]["x"]
    line_r = pw["amount"]["x"] + pw["amount"]["w"]
    bar_c = pw["frame"]["x"] + pw["frame"]["w"] / 2
    assert abs((line_l + line_r) / 2 - bar_c) <= 4, (line_l, line_r, bar_c)
    # the bounty is paid off: marks go away
    g.x("WB.bounty = 0")
    g.run(1.0)
    pw = g.plate("wb")
    assert "bicon" not in pw and "amount" not in pw, pw.keys()
    print("14 bounty skull + amount, trader coins, centred line: ok")

    # 14b characters without full squad data: never ask the game whether they trade (it would crash)
    g.x('''
        NS = newChar("ns", -20, 8, { faction = TRADERS, name = "No squad", squad = false }); NS.trader = true
        NP = newChar("np", -24, 12, { faction = TRADERS, name = "No platoon", squad = "no platoon" }); NP.trader = true
        NT = newChar("nt", -28, 16, { faction = TRADERS, name = "No template", squad = "no template" }); NT.trader = true
    ''')
    g.run(1.5)
    assert g.e("TRADER_CRASHES") == 0, "isATrader was called for a character without squad data"
    for key in ("ns", "np", "nt"):
        assert "ticon" not in g.plate(key), key
    assert g.plate("tr")["ticon"]["uv"] == (32, 48, 32, 32), "a real trader keeps the coins"
    print("14b no squad / no platoon / no template: the trader check is skipped, no crash: ok")

    # 14c a character without animation: no bone or appearance call (the game would crash), plate still drawn
    g.x('NA = newChar("na", -8, 20, { enemy = true, faction = BANDITS, name = "No animation", noAnimation = true })')
    g.run(1.5)
    assert g.e("ANIM_CRASHES") == 0, "bone/appearance asked on a character without animation"
    assert g.plate("na").get("frame"), "the plate is still drawn"
    print("14c no animation: no bone or appearance call, plate drawn at the default height: ok")

    # 12 main menu / no player: no errors, plates cleared
    g.x("NO_PLAYER = true")
    g.run(0.5)
    assert g.drawn_groups() == 0
    g.x("NO_PLAYER = false")
    g.run(1.0)
    assert g.drawn_groups() > 0
    print("12 no player then back: ok")

    expected = "ffi setup failed" if mode == "fallback" else "<none>"
    errors = [s for s in g.logs() if ("error" in s.lower() or "failed" in s.lower() or "switched" in s) and expected not in s]
    assert not errors, errors
    want = "projection=fb" if mode == "fallback" else "projection=rp"
    assert want in g.e("Nameplates.status()"), g.e("Nameplates.status()")
    print("status:", g.e("Nameplates.status()"))
    print("log:", g.logs())
    print("ALL PASSED")


def rects(g: Game) -> list[tuple[str, int, int, int, int]]:
    """Drawn frame and name boxes (name boxes trimmed to the measured text width)."""
    res = g.e('''(function()
        local out = {}
        for _, w in ipairs(WIDGETS) do
            if w:drawn() and ((w.kind == "image" and w.name:sub(-5) == "frame" and w.name:sub(-6) ~= "bframe") or w.kind == "text") then
                local x, y, ww, hh = w.coord[1], w.coord[2], w.coord[3], w.coord[4]
                if w.kind == "text" then
                    local tw = w:getTextSize()
                    x, ww, y, hh = x + (ww - tw) / 2, tw, y + 2, hh - 3
                end
                out[#out + 1] = { w.name, x, y, ww, hh, w.caption or "" }
            end
        end
        return out
    end)()''')
    return [tuple(v.values()) for v in res.values()]


def overlaps(a, b) -> bool:
    return a[1] < b[1] + b[3] - 1 and b[1] < a[1] + a[3] - 1 and a[2] < b[2] + b[4] - 1 and b[2] < a[2] + a[4] - 1


def crowd(mode: str) -> None:
    print("=== crowd", mode)
    g = Game(mode)
    g.x('''
        BANDITS = newFaction("Bandits", -100, false)
        TRADERS = newFaction("Traders", 10, false)
        for i = 1, 14 do newChar("b" .. i, (i % 3) * 0.7, (i % 4) * 0.7, { enemy = true, faction = BANDITS, name = "Bandit " .. i }) end
        L = newChar("lone", 60, 0, { enemy = true, faction = BANDITS, name = "Loner" })
    ''')
    g.load()
    g.run(2.0)
    r = rects(g)
    plates_drawn = [x for x in r if not x[0].endswith("name")]
    names = [x[5] for x in r if x[0].endswith("name")]
    bad = [(a[0], b[0]) for i, a in enumerate(r) for b in r[i + 1:] if overlaps(a, b)]
    assert not bad, ("plates overlap in a crowd", bad[:5])
    assert 5 <= len(plates_drawn) <= 7, (len(plates_drawn), names)
    assert "Loner" in names, names
    lone = g.plate("lone")
    print("1 crowd of 14 at one spot: ok,", len(plates_drawn), "plates drawn, none overlap; loner untouched at y", lone["frame"]["y"])

    # hostile plates keep the lowest places; hurt neutrals go above them
    g.x('''
        for _, c in ipairs(CHARS) do c.alive = false end
        for i = 1, 3 do newChar("t" .. i, i * 0.5, 0, { faction = TRADERS, name = "Trader " .. i }) end
        for i = 1, 3 do newChar("t" .. i, 0, 0, {}) end
    ''')
    g.x('''
        for _, c in ipairs(CHARS) do if c.id:sub(1, 1) == "t" and c.alive then c.medical.anatomy[2].flesh = 60 end end
        for i = 1, 2 do newChar("h" .. i, i * 0.5, 0.3, { enemy = true, faction = BANDITS, name = "Raider " .. i }) end
    ''')
    g.run(2.5)
    r = rects(g)
    frames = {x[0][:-5]: x for x in r if x[0].endswith("frame")}
    caps = {x[0][:-4]: x[5] for x in r if x[0].endswith("name")}
    ys = sorted(((f[2], caps.get(k, "?")) for k, f in frames.items()), reverse=True)
    order = [c for _, c in ys]
    assert order[0].startswith("Raider") and order[1].startswith("Raider"), order
    bad = [(a[0], b[0]) for i, a in enumerate(r) for b in r[i + 1:] if overlaps(a, b)]
    assert not bad, bad[:5]
    print("2 hostile first, bottom to top:", order)

    # when one character walks away the stack closes smoothly, not in one jump
    g.x('for _, c in ipairs(CHARS) do if c.id == "h1" then c.x = 80 end end')
    before = {k: f[2] for k, f in frames.items()}
    g.run(1 / 60)
    r = rects(g)
    now = {x[0][:-5]: x[2] for x in r if x[0].endswith("frame")}
    jumps = [abs(now[k] - before[k]) for k in now if k in before]
    assert max(jumps) < 25, jumps
    g.run(2.0)
    r = rects(g)
    bad = [(a[0], b[0]) for i, a in enumerate(r) for b in r[i + 1:] if overlaps(a, b)]
    assert not bad, bad[:5]
    print("3 stack slides when someone leaves: ok, biggest one-frame move", max(jumps), "px")
    errors = [x for x in g.logs() if "error" in x.lower()]
    assert not errors, errors
    print("CROWD PASSED")


def blunt_stun() -> None:
    """A blunt hit puts damage into stun: the bar shows flesh minus stun, like the game; stun wearing off refills it."""
    g = Game("exact")
    g.x('''
        B = newFaction("Bandits", -100, false)
        H = newChar("h1", -10, 0, { enemy = true, faction = B, name = "Bandit" })
    ''')
    g.load()
    g.run(1.0)
    s = 1200 / 1080
    full = g.plate("h1")["fill"]["w"]
    assert abs(full - 104 * s) < 1.5, full
    g.x("H.medical.anatomy[2].flesh = 90; H.medical.anatomy[2].fleshStun = 40")     # health 50 of 100
    g.run(2.0)
    w = g.plate("h1")["fill"]["w"]
    assert abs(w - 104 * s * 0.5) < 2, w
    g.x("H.medical.anatomy[2].fleshStun = 0")                                      # stun worn off: 90
    g.run(2.0)
    w = g.plate("h1")["fill"]["w"]
    assert abs(w - 104 * s * 0.9) < 2, w
    print("blunt: the bar is flesh minus stun, and refills as stun wears off: ok")


def unique_and_old_lua() -> None:
    """Unique NPCs get their own name colour (switchable); an old KenshiLua without the settings module still works."""
    g = Game("exact")
    g.x('''
        T = newFaction("Traders", 10, false)
        U = newChar("u1", -10, 0, { faction = T, name = "Boss", unique = true })
        O = newChar("o1", 10, 0, { faction = T, name = "Guard" })
    ''')
    g.load()
    g.run(1.0)
    uc, oc = g.plate("u1")["name"]["colour"], g.plate("o1")["name"]["colour"]
    want = (0.82, 0.55, 1.00)   # MARKS.unique
    assert all(abs(a - b) < 0.02 for a, b in zip(uc[:3], want)), uc
    assert not all(abs(a - b) < 0.02 for a, b in zip(oc[:3], want)), oc
    g.x('Nameplates.settings().showUnique = false')
    g.run(1.0)
    assert g.plate("u1")["name"]["colour"][:3] == oc[:3], "switched off: like everyone else"
    print("unique: own name colour for unique NPCs, switch works: ok")

    old = Game("exact", modules_found=False)
    old.x('B = newFaction("Bandits", -100, false); H = newChar("h1", -10, 0, { enemy = true, faction = B, name = "Bandit" })')
    old.load()
    old.run(1.0)
    assert any("np_settings not found" in s for s in old.logs()), old.logs()
    assert old.plate("h1").get("frame"), "plates work with the default settings"
    print("old KenshiLua: no settings module, plates still work with defaults: ok")


def hotkey() -> None:
    """Plates only by a key: hold shows them while the key is down, toggle switches on press; no focus, no plates."""
    g = Game("exact")
    g.x('NP_TEST_KEYS = { down = function(vk) return KEY_DOWN[vk] == true end, focused = function() return FOCUS end }; '
        'KEY_DOWN = {}; FOCUS = true')
    g.x('''
        BANDITS = newFaction("Bandits", -100, false)
        H = newChar("h1", -10, 0, { enemy = true, faction = BANDITS, name = "Bandit" })
        N = newChar("n1", 10, 0, { faction = newFaction("Traders", 10, false), name = "Trader" })
    ''')
    g.load()
    g.run(1.0)
    shown = g.drawn_groups()
    assert shown > 0, "off: plates as usual"

    g.x('Nameplates.settings().hotkeyMode = "hold"')
    g.run(0.5)
    assert g.drawn_groups() == 0, "hold: no plates without the key"
    g.x('KEY_DOWN[0x4E] = true')
    g.run(1.0)
    assert g.drawn_groups() == shown, "hold: plates while N (the default) is held"
    g.x('FOCUS = false')
    g.run(0.5)
    assert g.drawn_groups() == 0, "another program has the focus: no plates"
    g.x('FOCUS = true; KEY_DOWN[0x4E] = false')
    g.run(0.5)
    assert g.drawn_groups() == 0, "hold: key released, plates gone"

    g.x('local c = Nameplates.settings(); c.hotkeyMode = "toggle"; c.hotkey = "G"')
    g.run(0.5)
    assert g.drawn_groups() == 0, "toggle starts off"
    g.x('KEY_DOWN[0x47] = true'); g.run(0.2); g.x('KEY_DOWN[0x47] = false'); g.run(1.0)
    assert g.drawn_groups() == shown, "toggle: one press shows plates and they stay"
    g.x('KEY_DOWN[0x4E] = true'); g.run(0.3); g.x('KEY_DOWN[0x4E] = false'); g.run(0.3)
    assert g.drawn_groups() == shown, "toggle: another key does nothing"
    g.x('KEY_DOWN[0x47] = true'); g.run(0.2); g.x('KEY_DOWN[0x47] = false'); g.run(0.5)
    assert g.drawn_groups() == 0, "toggle: the next press hides them"

    g.x('Nameplates.settings().hotkeyMode = "off"')
    g.run(1.0)
    assert g.drawn_groups() == shown, "off again: plates as usual"
    assert not [s for s in g.logs() if "error" in s.lower()], g.logs()
    print("hotkey: off / while held / switch, focus needed: ok")


def ko_language() -> None:
    """The knocked-out mark follows the game language from settings.cfg; a language with a lang file of its own
    (here a made-up zh.txt) gets its text, a language without one gets English."""
    import os
    import tempfile
    sys.path.insert(0, str(HERE.parent / "mcm"))
    import gen_mcm
    from spec import MOD
    keys, langs = gen_mcm.load_langs(MOD)
    english = langs[0].texts
    zh = gen_mcm.Lang("zh", {k: english[k] for k in keys} | {"script.ko_suffix": "(昏迷)"})
    with_zh = Path(tempfile.mkdtemp())
    (with_zh / "np_settings.lua").write_text(gen_mcm.lua_for(MOD, langs + [zh]), encoding="utf-8")

    cases = [("language=ru_RU", None, "Bandit (без сознания)"), ("language=en_GB", None, "Bandit (KO)"),
             ("language=de_DE", None, "Bandit (KO)"), ("language=zh_CN", None, "Bandit (KO)"),
             ("language=zh_CN", with_zh, "Bandit (昏迷)"), (None, None, "Bandit (KO)")]
    here = os.getcwd()
    try:
        for cfg, modules, want in cases:
            game_dir = Path(tempfile.mkdtemp())
            if cfg:
                (game_dir / "settings.cfg").write_text(f"resolution=1920x1080\n{cfg}\nfloaters=0\n", encoding="utf-8")
            os.chdir(game_dir)
            g = Game("exact")
            if modules:
                g.x(f"package.path = [[{modules.as_posix()}/?.lua;]] .. package.path")
            g.x('B = newFaction("Bandits", -100, false); H = newChar("h1", -10, 0, { enemy = true, faction = B, name = "Bandit" })')
            g.load()
            g.x("H.medical.unconcious = true; H.medical.anatomy[2].flesh = -30")
            g.run(1.0)
            got = g.plate("h1")["name"]["caption"]
            assert got == want, (cfg, modules, got)
    finally:
        os.chdir(here)
    print("knocked-out mark: ru, en, unknown language -> English, zh with its own lang file, no settings.cfg: ok")


if __name__ == "__main__":
    for m in ("fallback", "exact"):
        main(m)
        crowd(m)
    hotkey()
    ko_language()
    unique_and_old_lua()
    blunt_stun()
