"""The shipped list of hireable templates (mod/Nameplates/scripts/np_hire.lua) is what tools/make_hire_list.py
makes from the base game data now, so it is not stale after a game patch. Usage: test_hire_list.py <Kenshi folder>
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent


def main() -> None:
    kenshi = Path(sys.argv[1])
    shipped = HERE.parent / "mod" / "Nameplates" / "scripts" / "np_hire.lua"
    fresh = Path(tempfile.mkdtemp()) / "np_hire.lua"
    subprocess.run([sys.executable, str(HERE.parent / "tools" / "make_hire_list.py"), str(kenshi), str(fresh)], check=True)
    assert fresh.read_text(encoding="utf-8") == shipped.read_text(encoding="utf-8"), "np_hire.lua differs from the base data"
    n = shipped.read_text(encoding="utf-8").count("] = true")
    for name in ("Sword for hire", "hire medic", "hire engineer", "Griffin"):
        assert f"-- {name}" + chr(10) in shipped.read_text(encoding="utf-8"), name
    print(f"np_hire.lua matches the base data: {n} templates: ok")


if __name__ == "__main__":
    main()
