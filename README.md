# Posh Nameplates

WoW-style nameplates for Kenshi: a name and a health bar over every character on screen.

Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3822135808
Goes well with [Posh Damage Numbers](https://github.com/seligdar/posh-damage-numbers).

## Requirements

- [RE_Kenshi](https://www.nexusmods.com/kenshi/mods/847) 0.3.3 or newer
- [KenshiLua](https://www.nexusmods.com/kenshi/mods/2068), enabled in the launcher
- Optional: [Mod Config Menu](https://steamcommunity.com/sharedfiles/filedetails/?id=3813761584) for the settings in game

To install without the Workshop, copy `mod/Nameplates` into `Kenshi/mods`.

## Translating

All texts are in `lang/`: the settings page in Mod Config Menu and the mark after the name of a knocked-out
character. To add a language:

1. Copy `lang/en.txt` to `lang/<code>.txt`, where `<code>` is the first two letters of `language=` in Kenshi's
   `settings.cfg` (`zh_CN` gives `zh.txt`).
2. Translate the text after ` = ` on each line and keep the key before it. Lines you leave out stay English.
3. Open a pull request. The texts are compiled into the settings plugin, so we rebuild it and publish the update.

Mod Config Menu draws with the game's fonts, so the characters — – « » … № come out as boxes; the build rejects them.

## Layout

- `mod/Nameplates` is the mod as it goes to the Workshop: `scripts/init/nameplates.lua` is the mod itself,
  `PoshNameplatesMCM.dll` and `scripts/np_settings.lua` are generated.
- `mcm/spec.py` lists the settings (ini keys, defaults, limits); `mcm/gen_mcm.py` turns it and `lang/*.txt` into
  the Mod Config Menu plugin source and the Lua settings module.
- `tools/make_np_atlas.py` draws `gui/gfx/Nameplates_atlas.png`.
- `tools/make_hire_list.py` reads the base game data and writes `scripts/np_hire.lua`: the character templates you
  can hire for money (crossed swords on the plate). The script cannot read conversations in the game safely, so the
  list is made here: `python tools/make_hire_list.py <Kenshi folder> mod/Nameplates/scripts/np_hire.lua`.
- `tests/` runs the script in LuaJIT against a fake game and loads the real plugin DLL in a fake Mod Config Menu.
- `workshop/` holds the Workshop description and preview.

## Building and testing

Building the plugin needs Visual Studio 2022 and the `sdk` folder of Mod Config Menu (set `MCM_SDK` if it is not in
the default Steam Workshop folder):

    mcm\build.bat

Tests need Python 3 with `lupa` and `Pillow`:

    cd tests
    python test_np.py
    python test_mcm_dll.py
    python test_e2e.py
    python test_sweep.py
    python test_hire_list.py <Kenshi folder>
