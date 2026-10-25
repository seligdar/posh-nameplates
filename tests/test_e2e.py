"""End to end: the real MCM plugin DLL from the mod folder is loaded into this process (as RE_Kenshi would), the
script runs in LuaJIT against the fake game, the ini is rewritten as MCM would and Apply is called; the script must
follow. Usage: test_e2e.py
"""
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
from test_mcm_dll import DLL, describe  # noqa: E402
from spec import MOD  # noqa: E402
import test_np  # noqa: E402

def load_plugin():
    d = Path(tempfile.mkdtemp()) / MOD.folder
    d.mkdir()
    shutil.copy(DLL, d / MOD.dll)
    _rows, (lib, keep, cb) = describe(d / MOD.dll, "en_GB")
    return d, lib, keep, cb


def write_ini(d: Path, ini: str, section: str, values: dict) -> None:
    text = f"[{section}]\n" + "".join(f"{k}={v}\n" for k, v in values.items())
    (d / ini).write_text(text, encoding="utf-8")


def drawn_fills(g) -> list:
    res = g.e('''(function()
        local out = {}
        for _, w in ipairs(WIDGETS) do
            if w.kind == "image" and w.name:sub(-4) == "fill" and w.name:sub(-5) ~= "bfill" and w:drawn() then
                out[#out + 1] = w.colour
            end
        end
        return out
    end)()''')
    return [tuple(c.values()) for c in res.values()]


def drawn_names(g) -> int:
    return g.e('''(function() local n = 0
        for _, w in ipairs(WIDGETS) do if w.kind == "text" and w:drawn() then n = n + 1 end end
        return n end)()''')


def nameplates() -> None:
    d, lib, keep, _cb = load_plugin()
    g = test_np.Game("fallback")
    g.x('''
        BANDITS = newFaction("Bandits", -100, false)
        for i = 1, 12 do newChar("h" .. i, (i % 4) * 8 - 12, math.floor(i / 4) * 8, { enemy = true, faction = BANDITS, name = "Bandit " .. i }) end
    ''')
    g.load()
    logs = g.logs()
    assert any(str(d / "Nameplates.ini") in s and "defaults" in s for s in logs), logs
    g.run(1.5)
    fills = drawn_fills(g)
    assert len(fills) == 12 and all(c[0] > 0.7 and c[1] < 0.3 for c in fills), fills
    assert drawn_names(g) == 12
    print("nameplates: plugin found, defaults used before MCM wrote anything: ok")

    write_ini(d, "Nameplates.ini", "PoshNameplates", {"ColourHostile": "#00FF00", "MaxPlates": 5, "ShowNames": 0})
    keep["apply"]()
    g.run(2.0)
    fills = drawn_fills(g)
    assert len(fills) == 5, len(fills)
    assert all(c[1] > 0.9 and c[0] < 0.1 for c in fills), fills
    assert drawn_names(g) == 0, "names must hide"
    assert any("settings changed" in s and "ColourHostile" in s for s in g.logs()), g.logs()
    print("nameplates: colour, plate count and names follow MCM without restart: ok")

    write_ini(d, "Nameplates.ini", "PoshNameplates", {"Enabled": 0})
    keep["apply"]()
    g.run(1.0)
    assert drawn_fills(g) == [], "plates must go when switched off"
    write_ini(d, "Nameplates.ini", "PoshNameplates", {"Enabled": 1})
    keep["apply"]()
    g.run(1.5)
    assert len(drawn_fills(g)) == 12 and drawn_names(g) == 12, "plates back with defaults"
    print("nameplates: switched off and on again from MCM: ok")


if __name__ == "__main__":
    nameplates()
    print("ALL PASSED")
