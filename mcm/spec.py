"""Settings of Posh Nameplates: structure, defaults and limits. Their texts are in lang/*.txt under the same keys
(label: <Key>, tooltip: <Key>.tip, choice button: <Key>.<value>, section title: section.<id>)."""
from dataclasses import dataclass, field


@dataclass
class Item:
    key: str                       # ini key and text key
    kind: str                      # bool, int, float, choice, colour
    root: str                      # Lua table the value goes to
    path: tuple[str, ...]          # keys inside that table
    default: object
    lo: float = 0
    hi: float = 0
    decimals: int = 2
    values: tuple[str, ...] = ()
    restart: bool = False


@dataclass
class Section:
    id: str
    items: list[Item] = field(default_factory=list)


@dataclass
class Mod:
    mod_id: str                    # MCM page id and ini section
    title: str                     # English mod name (MCM wants it untranslated)
    dll: str
    ini: str
    lua_module: str
    folder: str                    # mod folder, for reading the ini when the plugin is not loaded
    sections: list[Section]
    script_texts: tuple[str, ...]  # texts the script itself shows: lang key script.<name>


def hexcol(r: float, g: float, b: float) -> str:
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))



MOD = Mod(
    mod_id='PoshNameplates', title='Posh Nameplates', dll='PoshNameplatesMCM.dll',
    ini='Nameplates.ini', lua_module='np_settings', folder='Nameplates',
    sections=[
        Section('who', [
            Item('Enabled', 'bool', 'CONFIG', ('enabled',), True),
            Item('HotkeyMode', 'choice', 'CONFIG', ('hotkeyMode',), 'off', values=('off', 'hold', 'toggle')),
            Item('Hotkey', 'choice', 'CONFIG', ('hotkey',), 'N', values=('N', 'G', 'X', 'Z', 'U', 'P', 'CapsLock', 'Alt')),
            Item('ShowHostile', 'choice', 'CONFIG', ('show', 'hostile'), 'always', values=('always', 'near', 'fighting', 'never')),
            Item('ShowUnfriendly', 'choice', 'CONFIG', ('show', 'unfriendly'), 'always', values=('always', 'near', 'fighting', 'never')),
            Item('ShowNeutral', 'choice', 'CONFIG', ('show', 'neutral'), 'always', values=('always', 'near', 'fighting', 'never')),
            Item('ShowFriendly', 'choice', 'CONFIG', ('show', 'friendly'), 'always', values=('always', 'near', 'fighting', 'never')),
            Item('ShowSquad', 'choice', 'CONFIG', ('show', 'squad'), 'always', values=('always', 'near', 'fighting', 'never')),
            Item('HideIndoors', 'bool', 'CONFIG', ('hideIndoors',), True),
            Item('HideDowned', 'bool', 'CONFIG', ('hideDowned',), False),
            Item('SquadRange', 'int', 'CONFIG', ('squadRange',), 60, lo=10, hi=300),
            Item('FightSeconds', 'int', 'CONFIG', ('fightSeconds',), 10, lo=1, hi=60),
            Item('KeepSeconds', 'float', 'CONFIG', ('keepSeconds',), 3.0, lo=0.0, hi=10.0, decimals=1),
            Item('MaxPlates', 'int', 'CONFIG', ('maxPlates',), 40, lo=5, hi=80),
        ]),
        Section('look', [
            Item('ShowNames', 'bool', 'CONFIG', ('showNames',), True),
            Item('ShowBlood', 'bool', 'CONFIG', ('showBlood',), True),
            Item('ShowBounty', 'bool', 'CONFIG', ('showBounty',), True),
            Item('ShowTrader', 'bool', 'CONFIG', ('showTrader',), True),
            Item('ShowUnique', 'bool', 'CONFIG', ('showUnique',), True),
            Item('FullSizeBodyPx', 'int', 'CONFIG', ('fullSizeBodyPx',), 70, lo=20, hi=200),
            Item('MinScale', 'float', 'CONFIG', ('minScale',), 0.55, lo=0.3, hi=1.0),
            Item('MinBodyPx', 'int', 'CONFIG', ('minBodyPx',), 6, lo=2, hi=60),
            Item('Stacking', 'bool', 'CONFIG', ('stacking',), True),
            Item('StackMaxRise', 'int', 'CONFIG', ('stackMaxRise',), 5, lo=1, hi=10),
        ]),
        Section('colours', [
            Item('ColourHostile', 'colour', 'COLOURS', ('hostile', 'bar'), '#DB291F'),
            Item('ColourUnfriendly', 'colour', 'COLOURS', ('unfriendly', 'bar'), '#ED781F'),
            Item('ColourNeutral', 'colour', 'COLOURS', ('neutral', 'bar'), '#EBC229'),
            Item('ColourFriendly', 'colour', 'COLOURS', ('friendly', 'bar'), '#4CC740'),
            Item('ColourSquad', 'colour', 'COLOURS', ('squad', 'bar'), '#4794FF'),
            Item('ColourDying', 'colour', 'MARKS', ('dying',), '#940F0F'),
            Item('ColourTrail', 'colour', 'MARKS', ('trail',), '#FFF0B8'),
            Item('ColourBlood', 'colour', 'MARKS', ('blood',), '#C7121A'),
            Item('ColourUnique', 'colour', 'MARKS', ('unique',), '#D18CFF'),
        ]),
        Section('relations', [
            Item('UnfriendlyBelow', 'int', 'CONFIG', ('unfriendlyBelow',), -25, lo=-100, hi=0),
            Item('FriendlyAbove', 'int', 'CONFIG', ('friendlyAbove',), 50, lo=0, hi=100),
        ]),
    ],
    script_texts=('ko_suffix',),
)
