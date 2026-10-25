-- Fake Kenshi/KenshiLua environment for testing nameplates.lua outside the game.
LOG = {}
KenshiLua = { log = function(msg) LOG[#LOG + 1] = msg end }

-- hand / lektor -----------------------------------------------------------------
local Hand = {}
Hand.__index = Hand
function Hand.new(ch) return setmetatable({ ch = ch }, Hand) end
function Hand:toString() return "hand:" .. self.ch.id end
function Hand:getCharacter() if self.ch.alive then return self.ch end return nil end
HANDLES_MADE = 0
lektor = { new = function(kind)
    assert(kind == "hand")
    local l = {}
    function l:push(h) HANDLES_MADE = HANDLES_MADE + 1 self[#self + 1] = Hand.new(h.ch) end
    return l
end }

-- factions ----------------------------------------------------------------------------
function newFaction(name, rel, ally) return { name = name, rel = rel, ally = ally } end
PLAYER_FACTION = { name = "Nameless", relations = {
    isAlly = function(self, f) return f.ally == true end,
    getFactionRelation = function(self, f) return f.rel end,
} }

-- the real getBoneWorldPosition / getAppearance read Character::animation (+0x448) without a null check:
-- the game crashes on a character without one; here it is counted and raised
ANIM_CRASHES = 0
local ffiMock = require("ffi")
local function animationOrCrash(c)
    if ffiMock.cast("uintptr_t", c.animation) == 0 then
        ANIM_CRASHES = ANIM_CRASHES + 1
        error("CRASH: no animation")
    end
end
-- characters ----------------------------------------------------------------------
local Char = {}
Char.__index = Char
CHARS = {}
local VITAL = { true, true, true, false, false, false, false }   -- head, chest, stomach collapse
function newChar(id, x, z, opts)
    opts = opts or {}
    local parts = {}
    for i = 1, 7 do
        parts[i] = { flesh = 100, fleshStun = 0, collapses = VITAL[i], fatal = VITAL[i], maxHealth = function() return 100 end }
    end
    local med = { anatomy = parts, blood = 100, unconcious = false, dead = false }
    function med:getMaxBlood() return self.noBlood and 0 or 100 end
    local c = setmetatable({ id = id, alive = true, x = x, y = 0, z = z, player = opts.player, enemy = opts.enemy,
        faction = opts.faction, robot = opts.robot, height = opts.height or 17, lying = false, medical = med,
        name = opts.name or ("Char" .. id), appearanceHeight = opts.appearanceHeight or 1.8, unique = opts.unique }, Char)
    c.handle = Hand.new(c)
    c.animation = ffiMock.cast("void*", opts.noAnimation and 0 or 1)
    -- Character.platoon -> ActivePlatoon.me (Platoon) -> squadTemplate; opts.squad = false / "no platoon" /
    -- "no template" breaks the chain like characters the game has no squad data for
    if opts.squad == false then c.squad = nil
    elseif opts.squad == "no platoon" then c.squad = { me = nil }
    elseif opts.squad == "no template" then c.squad = { me = { squadTemplate = nil } }
    else c.squad = { me = { squadTemplate = {} } } end
    CHARS[#CHARS + 1] = c
    return c
end
function Char:getPosition() return { x = self.x, y = self.y, z = self.z } end
function Char:getBoneWorldPosition(name)
    animationOrCrash(self)
    if self.robot then error("no such bone") end
    local h = self.lying and 3 or self.height
    if name == "Bip01 Head" then h = h - 1 end
    return { x = self.x, y = self.y + h, z = self.z }
end
function Char:isPlayerCharacter() return self.player == true end
function Char:isUnique() return self.unique == true end
function Char:isDead() return self.medical.dead end
function Char:getMedical() return self.medical end
function Char:getName() return self.name end
function Char:getFaction() return self.faction end
-- the real one reads the melee and ranged combat objects without null checks: never to be called
COMBAT_CALLS = 0
function Char:isInCombatMode(melee, ranged) COMBAT_CALLS = COMBAT_CALLS + 1 error("CRASH: isInCombatMode") end
-- the real Character::isATrader is "return platoon->getIsTrader()" and reads platoon->me->squadTemplate with
-- no null checks: the game crashes (crash 2026-10-18 20:29); here it is counted and raised
TRADER_CRASHES = 0
function Char:isATrader()
    local ap = self.squad
    if ap == nil or ap.me == nil or ap.me.squadTemplate == nil then
        TRADER_CRASHES = TRADER_CRASHES + 1
        error("CRASH: isATrader on a character without a full squad chain")
    end
    return self.trader == true
end
-- the bounty manager lives in the Character field "crimes"
local Crimes = {}
Crimes.__index = Crimes
function Crimes:getTotalBounty() return self.owner.bounty or 0 end
local charIndex = Char.__index
Char.__index = function(t, k)
    if k == "crimes" then return setmetatable({ owner = t }, Crimes) end
    if k == "platoon" then return rawget(t, "squad") end
    return charIndex[k]
end
-- isIndoors returns a hand: null outdoors, the building's hand inside
local NULL_HAND = { isNull = function() return true end, isValid = function() return false end }
function Char:isIndoors()
    if self.building == nil then return NULL_HAND end
    local b = self.building
    return { isNull = function() return false end, isValid = function() return true end, getBuilding = function() return b end }
end
function Char:getAppearance()
    animationOrCrash(self)
    local c = self
    return { getCharacterHeight = function() return c.appearanceHeight end }
end

-- world / camera --------------------------------------------------------------------
ZOOM = 1
local function camPos() return { x = 0, y = 6 + 54 * ZOOM, z = 120 * ZOOM } end
local camera = {
    camera = nil,
    getCameraPos = function() return camPos() end,
    getFacingDirection = function() return { x = 0, y = 0, z = -1 } end,
    getCenter = function() return { x = 0, y = 6, z = 0 } end,
    isVisible = function(self, pos)
        local c = camPos()
        local dx, dy, dz = pos.x - c.x, pos.y - c.y, pos.z - c.z
        local l = math.sqrt(0.45 * 0.45 + 1)
        local d = (dy * -0.45 + dz * -1) / l
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        return d > 0 and d / dist > math.cos(math.rad(35))
    end,
}
PI = { camera = camera, getCamera = function() return camera end,
    isEnemy = function(self, c) return c.enemy == true end,
    getFaction = function() return PLAYER_FACTION end,
    getInteriorsVisible = function(self, b) return b.open == true end,
    selectedObject = nil }
setmetatable(PI, { __index = function(t, k)
    if k == "playerCharacters" then
        local list = {}
        for _, c in ipairs(CHARS) do if c.alive and c.player then list[#list + 1] = c end end
        return list
    end
end })
NO_PLAYER = false
function getPlayerInterface() if NO_PLAYER then return nil end return PI end
function getGameWorld()
    if NO_PLAYER then return nil end
    return { player = PI, getCharacterUpdateList = function()
        local set = {}
        for _, c in ipairs(CHARS) do if c.alive then set[c] = true end end
        return set
    end }
end

-- MyGUI -------------------------------------------------------------------------------
-- ImageBox follows MyGUI 3.2 MyGUI_ImageBox.cpp: the tile size is kept from the first rect,
-- items are cut from the rect by the tile, and nothing is drawn without a selected item.
WIDGETS = {}
local ITEM_NONE = -1
local Widget = {}
Widget.__index = Widget
local function rectEmpty(r) return r.r - r.l <= 0 or r.b - r.t <= 0 end
function Widget:_recalcIndexes()
    self.items = {}
    local r, tile = self.rect, self.tile
    if r.r <= r.l or r.b <= r.t then return end
    if tile.w <= 0 or tile.h <= 0 then return end
    local ch, cv = math.floor((r.r - r.l) / tile.w), math.floor((r.b - r.t) / tile.h)
    local y = r.t
    for v = 1, cv do
        local x = r.l
        for h = 1, ch do
            self.items[#self.items + 1] = { x, y, tile.w, tile.h }
            x = x + tile.w
        end
        y = y + tile.h
    end
end
function Widget:_updateSelectIndex(i)
    self.index = i
    if i == ITEM_NONE or i >= #self.items then
        self.drawTexture, self.uv = "", nil
        return
    end
    self.drawTexture, self.uv = self.texture, self.items[i + 1]
end
function Widget:setImageTexture(t)
    self.texture = t
    if #self.items == 0 then
        self.drawTexture, self.uv = t, { 0, 0, 128, 64 }
    else
        self:_recalcIndexes()
        self:_updateSelectIndex(self.index)
    end
end
function Widget:setImageTile(w, h)
    self.tile = { w = w, h = h }
    if rectEmpty(self.rect) then self.rect = { l = 0, t = 0, r = w, b = h } end
    if self.index == ITEM_NONE then self.index = 0 end
    self:_recalcIndexes()
    self:_updateSelectIndex(self.index)
end
function Widget:setImageCoord(x, y, w, h)
    self.rect = { l = x, t = y, r = x + w, b = y + h }
    if self.tile.w == 0 and self.tile.h == 0 then self.tile = { w = w, h = h } end
    if self.index == ITEM_NONE then self.index = 0 end
    self:_recalcIndexes()
    self:_updateSelectIndex(self.index)
end
function Widget:setImageIndex(i) self:_updateSelectIndex(i) end
function Widget:setNeedMouseFocus() end
function Widget:setInheritsPick() end
function Widget:setVisible(v) self.visible = v end
function Widget:getVisible() return self.visible end
function Widget:setCoord(x, y, w, h)
    assert(x == math.floor(x) and y == math.floor(y) and w == math.floor(w) and h == math.floor(h), "non-integer coord")
    assert(w >= 1 and h >= 1, "empty widget size")
    self.coord = { x, y, w, h }
end
function Widget:setAlpha(a) assert(a >= 0 and a <= 1.0001, "alpha out of range " .. a) self.alpha = a end
function Widget:setColour(c) assert(type(c) == "table" and #c == 4, "bad colour") self.colour = c end
function Widget:destroy() self.destroyed = true end
function Widget:drawn()
    if not self.visible or self.destroyed or (self.alpha or 0) <= 0 then return nil end
    if self.kind == "text" then
        if self.font == nil or self.caption == nil or self.caption == "" then return nil end
        return self.caption
    end
    if self.drawTexture == nil or self.drawTexture == "" or self.uv == nil then return nil end
    return self.uv
end
-- TextBox
function Widget:setFontName(f) self.font = f end
function Widget:setTextAlign(a) assert(type(a) == "number", "align must be a number") self.textAlign = a end
function Widget:setCaption(s) assert(type(s) == "string") self.caption = s self.captionSets = (self.captionSets or 0) + 1 end
function Widget:getTextSize()
    local n = 0
    local s = self.caption or ""
    for i = 1, #s do
        local b = s:byte(i)
        if b < 128 or b >= 192 then n = n + 1 end   -- count characters, not UTF-8 bytes
    end
    return n * 10, 17                                  -- Exo 2 at 17 px is about 10 px per letter
end
function Widget:setTextColour(c) assert(type(c) == "table" and #c == 4, "bad colour") self.textColour = c end

local function newWidget(kind, name, layer)
    local wd = setmetatable({ kind = kind, name = name, layerName = layer, items = {}, index = ITEM_NONE,
        rect = { l = 0, t = 0, r = 0, b = 0 }, tile = { w = 0, h = 0 } }, Widget)
    WIDGETS[#WIDGETS + 1] = wd
    return wd
end
MyGUI = {
    getViewSize = function() return 1920, 1200 end,
    createImageBox = function(skin, l, t, w, h, name, layer)
        assert(skin == "ImageBox")
        return newWidget("image", name, layer)
    end,
    createTextBox = function(skin, l, t, w, h, name, layer)
        assert(skin == "Kenshi_TextBoxEmptySkin", "unknown text skin " .. tostring(skin))
        return newWidget("text", name, layer)
    end,
    Colour = { new = function(r, g, b, a) return { r, g, b, a } end },
    Align = { Center = 0 },
}

-- events --------------------------------------------------------------------------------
HANDLERS = {}
Events = { on = function(name, fn) HANDLERS[name] = fn end }

SIM_TIME = 0
os.clock = function() return SIM_TIME end
