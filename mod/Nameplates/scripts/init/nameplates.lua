-- Posh Nameplates for Kenshi (KenshiLua script)
--
-- WoW-style plates above characters: name plus a health bar coloured by how the character's
-- faction treats you (red hostile, orange unfriendly, yellow neutral, green friendly, blue your squad).
--
-- What the bar shows:
--   * the health of the body part that is closest to knocking the character out (head, chest, stomach);
--   * a light "trail" shows what was just lost and slides down after a short pause;
--   * when the character is knocked out the bar turns dark red and shows how far they are from death;
--   * a thin red bar under it appears when the character has lost blood.
-- Like a strategy game: everyone on screen gets a plate, except characters inside a building whose roof
-- is on. Other modes per faction kind ("near", "fighting") are in the settings. A plate stays a few seconds
-- after it stops being needed, so plates do not blink. When you zoom out the plates shrink (smaller bar
-- and font) instead of disappearing.
-- Next to the name: a skull and the amount when there is a bounty on the character's head, coins for traders.
-- Unique characters (faction leaders, bosses, unique recruits) get their own name colour, except in your squad,
-- where every name stays squad blue.
-- Plates follow the character smoothly and fade in and out.
-- In crowds plates stack upwards like WoW's, hostile ones keep the lowest places; plates pushed too high fade out.
-- Optionally plates show only by a key: while it is held, or switched on and off by it (CONFIG.hotkeyMode).
-- They are drawn on the lowest UI layer, so game windows and damage numbers cover them.
--
-- Everything that touches the game is wrapped in pcall: a failure turns the feature off and is
-- written once to KenshiLua's log, it never stops the game.

local TAG = "[Nameplates] "
local log = (KenshiLua and KenshiLua.log) or print

-- Modules next to this script. KenshiLua versions without mod-local require cannot find them, so the mod's
-- folder (a local mod, or the Steam Workshop copy next to the game) is added to package.path and tried again.
local MOD_FOLDERS = { "mods/Nameplates/scripts/?.lua", "../../workshop/content/233860/3822135808/scripts/?.lua" }
local function requireLocal(name)
    local ok, mod = pcall(require, name)
    if ok then return mod end
    if package and type(package.path) == "string" then
        for _, f in ipairs(MOD_FOLDERS) do
            if not package.path:find(f, 1, true) then package.path = package.path .. ";" .. f end
        end
        local ok2, mod2 = pcall(require, name)
        if ok2 then
            log(TAG .. name .. " found in the mod folder; a newer KenshiLua finds it by itself")
            return mod2
        end
    end
    log(TAG .. "module " .. name .. " not found, please update KenshiLua: " .. tostring(mod))
    return nil
end
-- without the settings module the defaults below are used and Mod Config Menu changes are not read
local SETTINGS = requireLocal("np_settings") or {
    apply = function() return {}, false end,
    poll = function() return nil end,
    iniPath = function() return "(no settings module)" end,
    pluginLoaded = function() return false end,
    text = function(name) return ({ ko_suffix = "(KO)" })[name] end,
}

-- ===================================================================================
-- SETTINGS
-- ===================================================================================
local CONFIG = {
    enabled = true,
    hotkeyMode = "off",          -- "off": plates as set below; "hold": only while the hotkey is held;
                                 -- "toggle": the hotkey switches plates on and off
    hotkey = "N",                -- one of HOTKEYS
    -- who gets a plate (the character you selected always gets one):
    --   "always"   whenever the character is on screen;
    --   "near"     within squadRange of any of your characters, or fighting;
    --   "fighting" hitting, hit or wounded in the last fightSeconds, or knocked out by it;
    --   "never"
    show = {
        hostile = "always",
        unfriendly = "always",
        neutral = "always",
        friendly = "always",
        squad = "always",
    },
    hideIndoors = true,          -- no plates for characters inside a building, unless its roof is lifted
    hideDowned = false,          -- no plates for knocked-out NPCs, everyone outside your squad (unless selected)
    squadRange = 60,             -- metres from the nearest of your characters for "near"
    fightSeconds = 10,           -- after the last hit or wound a character counts as fighting this long
    keepSeconds = 3,             -- a plate stays at least this long after it stops being needed
    showNames = true,
    showBlood = true,            -- thin blood bar under the health bar when blood is below full
    showBounty = true,           -- skull and the bounty amount next to the name of wanted characters
    showTrader = true,           -- coins next to the name of traders
    showUnique = true,           -- unique characters' names in MARKS.unique
    unfriendlyBelow = -25,       -- faction relation at or below this is "unfriendly" (orange)
    friendlyAbove = 50,          -- faction relation at or above this is "friendly" (green)
    maxPlates = 40,              -- selected first, then hostile, then by distance from your people
    minBodyPx = 6,               -- characters smaller than this on screen (1080p pixels) get no plate
    fullSizeBodyPx = 70,         -- plates are full size for characters this tall on screen, smaller below
    minScale = 0.55,             -- the smallest plate size when the camera is far away
    stacking = true,             -- in crowds plates move up so they do not cover each other (like WoW)
    stackMaxRise = 5,            -- a plate pushed higher than this many plate heights fades out
    scanInterval = 0.4,          -- seconds between choosing who gets plates
    healthInterval = 0.1,        -- seconds between health readings
    layer = "Wallpaper",         -- the lowest MyGUI layer: under windows and under damage numbers
    fallbackFovDegrees = 45,     -- used only when the exact camera matrices are unavailable
}

local COLOURS = {
    hostile    = { bar = { 0.86, 0.16, 0.12 }, name = { 1.00, 0.55, 0.48 } },
    unfriendly = { bar = { 0.93, 0.47, 0.12 }, name = { 1.00, 0.72, 0.45 } },
    neutral    = { bar = { 0.92, 0.76, 0.16 }, name = { 1.00, 0.92, 0.56 } },
    friendly   = { bar = { 0.30, 0.78, 0.25 }, name = { 0.66, 1.00, 0.60 } },
    squad      = { bar = { 0.28, 0.58, 1.00 }, name = { 0.64, 0.82, 1.00 } },
}
-- Windows virtual-key codes of the keys offered in the settings: keys Kenshi's controls.cfg does not bind
-- (V, ~ and the side mouse buttons are taken by the game), plus Alt
local HOTKEYS = { N = 0x4E, G = 0x47, X = 0x58, Z = 0x5A, U = 0x55, P = 0x50, CapsLock = 0x14,
                  Alt = 0x12 }   -- Alt on request, although the game also highlights with it
local MARKS = {
    dying = { 0.58, 0.06, 0.06 },   -- knocked out: distance to death
    trail = { 1.00, 0.94, 0.72 },   -- health just lost
    blood = { 0.78, 0.07, 0.10 },   -- blood bar
    unique = { 0.82, 0.55, 1.00 },  -- names of unique characters
}
-- name colours are the bar colours lightened halfway to white, so one colour setting drives both
local function deriveNameColours()
    for _, c in pairs(COLOURS) do
        c.name = { c.bar[1] + (1 - c.bar[1]) * 0.5, c.bar[2] + (1 - c.bar[2]) * 0.5, c.bar[3] + (1 - c.bar[3]) * 0.5 }
    end
end
local KO_NAME = { 0.72, 0.72, 0.72 }
local BOUNTY_TEXT = { 1.00, 0.80, 0.28 }

-- name fonts by plate size: Kenshi's fonts have a fixed pixel height, so smaller plates switch font
local FONTS = {
    { name = "Kenshi_FloaterFont_Small", px = 17, from = 0.82 },
    { name = "Kenshi_StandardFont_MediumSmall", px = 15, from = 0.64 },
    { name = "Kenshi_StandardFont_Small", px = 12, from = 0 },
}

local TEXTURE = "Nameplates_atlas.png"
-- Kenshi's own transparent text skin (MyGUI's "TextBox" skin does not exist in the game)
local TEXT_SKIN = "Kenshi_TextBoxEmptySkin"
local REG = {
    frame = { x = 0, y = 0, w = 108, h = 13 },
    fill = { x = 0, y = 16, w = 104, h = 9 },
    bframe = { x = 0, y = 28, w = 108, h = 6 },
    bfill = { x = 0, y = 36, w = 104, h = 4 },
    spark = { x = 112, y = 16, w = 8, h = 9 },
    bounty = { x = 0, y = 48, w = 32, h = 32 },
    trader = { x = 32, y = 48, w = 32, h = 32 },
}

-- ===================================================================================
-- Small helpers
-- ===================================================================================
local floor, max, min, abs, sqrt, exp = math.floor, math.max, math.min, math.abs, math.sqrt, math.exp
local warned = {}
local function warnOnce(key, msg)
    if not warned[key] then
        warned[key] = true
        log(TAG .. msg)
    end
end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - exp(-rate * dt)) end

local function keyOf(c)
    local ok, k = pcall(function() return tostring(c.handle:toString()) end)
    if ok and k then return k end
    return nil
end

-- A character can be unloaded at any moment, so only a copy of its handle is kept
-- and resolved again when needed; the engine returns nothing for a handle whose character is gone.
local function handleRef(c)
    local ok, ref = pcall(function()
        local list = lektor.new("hand")
        list:push(c.handle)
        return list
    end)
    if ok then return ref end
    warnOnce("handle", "could not copy a character handle: " .. tostring(ref))
    return nil
end

local function resolve(ref)
    if ref == nil then return nil end
    local ok, c = pcall(function() return ref[1]:getCharacter() end)
    if ok then return c end
    return nil
end

local function playerInterface()
    local ok, pi = pcall(function() return (getPlayerInterface and getPlayerInterface()) or getGameWorld().player end)
    if ok then return pi end
    return nil
end

-- ===================================================================================
-- Screen and camera projection (same method as Posh Damage Numbers)
-- ===================================================================================
local W, H, resScale = 1920, 1080, 1.0

local function updateViewSize()
    local ok, a, b = pcall(function() return MyGUI.getViewSize() end)
    if not (ok and type(a) == "number") then
        ok, a, b = pcall(function() return MyGUI.RenderManager.getInstance():getViewSize() end)
        if ok and type(a) ~= "number" and a then a, b = a.width, a.height end
    end
    if ok and type(a) == "number" and a > 0 and b and b > 0 then
        W, H = a, b
        resScale = H / 1080
    end
end

local function cameraClass()
    local pi = playerInterface()
    if pi == nil then return nil end
    local ok, cam = pcall(function()
        local okGet, c = pcall(function() return pi:getCamera() end)
        if okGet and c then return c end
        return pi.camera
    end)
    if ok then return cam end
    return nil
end

-- Exact projection through Ogre's own camera matrices (LuaJIT ffi). Three ways of projecting are kept and
-- checked against the game's own visibility test; the one that agrees with the game is used:
--   "rp"   rotation from Ogre's view matrix + camera position from the game + Ogre's projection;
--   "full" Ogre's full view matrix + Ogre's projection;
--   "fb"   no ffi: camera position looking at the camera's centre point, field of view from Ogre if known.
local ffiProj = nil
do
    local okFfi, ffi = pcall(require, "ffi")
    if not okFfi or not ffi then
        ffi = rawget(_G, "ffi") or (package and package.loaded and package.loaded.ffi)
    end
    if ffi then
        local okDef = pcall(ffi.cdef, [[
            typedef struct { float m[16]; } NP_Matrix4;
            const NP_Matrix4* NP_getViewMatrix(const void* cam) __asm__("?getViewMatrix@Camera@Ogre@@UEBAAEBVMatrix4@2@XZ");
            const NP_Matrix4* NP_getProjMatrix(const void* cam) __asm__("?getProjectionMatrix@Frustum@Ogre@@UEBAAEBVMatrix4@2@XZ");
        ]])
        if not okDef then
            -- a reload of this script: the declarations already exist, keep going
            okDef = pcall(function() return ffi.typeof("NP_Matrix4") end)
        end
        pcall(ffi.cdef, [[
            void* GetModuleHandleA(const char* name);
            void* GetProcAddress(void* module, const char* name);
        ]])
        local okLib, ogre = pcall(ffi.load, "OgreMain_x64")
        if okDef and okLib then
            local okInfo, vtbl = pcall(function()
                local mod = ffi.C.GetModuleHandleA("OgreMain_x64.dll")
                if mod == nil then error("OgreMain_x64.dll is not loaded") end
                local sym = ffi.C.GetProcAddress(mod, "??_7Camera@Ogre@@6BMovableObject@1@@")
                if sym == nil then error("Ogre::Camera vtable symbol not found") end
                return tonumber(ffi.cast("uintptr_t", sym))
            end)
            if okInfo then
                ffiProj = { ffi = ffi, ogre = ogre, cameraVtable = vtbl, checkedPtr = nil }
            else
                warnOnce("ffi-module", "Ogre camera class not identified, using fallback projection: " .. tostring(vtbl))
            end
        else
            warnOnce("ffi-setup", "ffi setup failed, using fallback projection")
        end
    else
        warnOnce("ffi-missing", "LuaJIT ffi not available, using fallback projection")
    end
end

-- The keyboard through the Windows API (user32 is loaded by the game): a key counts only while the game
-- window has the focus, so Alt+Tab to another program does not show plates. Tests put NP_TEST_KEYS instead.
local KEYS = rawget(_G, "NP_TEST_KEYS")
if KEYS == nil then
    local okFfi, ffi = pcall(require, "ffi")
    if okFfi and ffi then
        pcall(ffi.cdef, "short GetAsyncKeyState(int vKey);")
        pcall(ffi.cdef, "void* GetForegroundWindow(void);")
        pcall(ffi.cdef, "unsigned long GetWindowThreadProcessId(void* hWnd, unsigned long* processId);")
        pcall(ffi.cdef, "unsigned long GetCurrentProcessId(void);")
        local okC = pcall(function()
            return ffi.C.GetAsyncKeyState, ffi.C.GetForegroundWindow, ffi.C.GetWindowThreadProcessId, ffi.C.GetCurrentProcessId
        end)
        if okC then
            local pid = ffi.new("unsigned long[1]")
            KEYS = {
                down = function(vk) return ffi.C.GetAsyncKeyState(vk) < 0 end,
                focused = function()
                    local w = ffi.C.GetForegroundWindow()
                    if w == nil then return false end
                    ffi.C.GetWindowThreadProcessId(w, pid)
                    return pid[0] == ffi.C.GetCurrentProcessId()
                end,
            }
        end
    end
end

local MRP, MFULL = {}, {}
local exactUsable = ffiProj ~= nil
local projMode = "none"
local preferred = exactUsable and "rp" or "fb"
local camPos = { x = 0, y = 0, z = 0 }
local fb = { fx = 0, fy = 0, fz = 1, rx = 1, ry = 0, rz = 0, ux = 0, uy = 1, uz = 0, t = 0.414, aspect = nil }
local fbReady = false
local ogreFov = nil

local function isCameraPointer(ptr)
    if ffiProj.checkedPtr == ptr then return true end
    local ok, same = pcall(function()
        return tonumber(ffiProj.ffi.cast("uintptr_t*", ptr)[0]) == ffiProj.cameraVtable
    end)
    if ok and same then
        ffiProj.checkedPtr = ptr
        return true
    end
    return false
end

local function matricesLookRight(v, p)
    if abs(v[12]) > 1e-3 or abs(v[13]) > 1e-3 or abs(v[14]) > 1e-3 or abs(v[15] - 1) > 1e-3 then return false end
    for r = 0, 2 do
        local l = v[r * 4] ^ 2 + v[r * 4 + 1] ^ 2 + v[r * 4 + 2] ^ 2
        if abs(l - 1) > 1e-2 then return false end
    end
    if abs(p[12]) > 1e-3 or abs(p[13]) > 1e-3 or abs(p[14] + 1) > 1e-3 or abs(p[15]) > 1e-3 then return false end
    return p[0] > 0 and p[5] > 0
end

local function disableExact(reason)
    if exactUsable then
        exactUsable = false
        preferred = "fb"
        log(TAG .. "exact projection switched off: " .. reason)
    end
end

local function norm3(x, y, z)
    local l = sqrt(x * x + y * y + z * z)
    if l < 1e-6 then return nil end
    return x / l, y / l, z / l
end

local function updateFallback(cc)
    local ok = pcall(function()
        local pos = cc:getCameraPos()
        local fx, fy, fz = nil, nil, nil
        local okC, centre = pcall(function() return cc:getCenter() end)
        if okC and centre then fx, fy, fz = norm3(centre.x - pos.x, centre.y - pos.y, centre.z - pos.z) end
        if fx == nil then
            local f = cc:getFacingDirection()
            fx, fy, fz = norm3(f.x, f.y, f.z)
        end
        local rx, ry, rz = -fz, 0, fx
        local rl = sqrt(rx * rx + rz * rz)
        if rl < 1e-4 then rx, rz, rl = 1, 0, 1 end
        rx, rz = rx / rl, rz / rl
        local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
        camPos.x, camPos.y, camPos.z = pos.x, pos.y, pos.z
        fb.fx, fb.fy, fb.fz, fb.rx, fb.ry, fb.rz, fb.ux, fb.uy, fb.uz = fx, fy, fz, rx, ry, rz, ux, uy, uz
        if ogreFov then
            fb.t, fb.aspect = ogreFov.t, ogreFov.aspect
        else
            fb.t, fb.aspect = math.tan(math.rad(CONFIG.fallbackFovDegrees) / 2), nil
        end
    end)
    fbReady = ok
    return ok
end

local function multiply(out, p, r00, r01, r02, t0, r10, r11, r12, t1, r20, r21, r22, t2)
    local v = { r00, r01, r02, t0, r10, r11, r12, t1, r20, r21, r22, t2, 0, 0, 0, 1 }
    for r = 0, 3 do
        for c = 0, 3 do
            out[r * 4 + c + 1] = p[r * 4] * v[c + 1] + p[r * 4 + 1] * v[4 + c + 1] + p[r * 4 + 2] * v[8 + c + 1] + p[r * 4 + 3] * v[12 + c + 1]
        end
    end
end

local currentCamera = nil
local function updateCamera()
    local cc = cameraClass()
    currentCamera = cc
    if cc == nil then projMode = "none" return false end
    local fbOk = updateFallback(cc)
    local exactOk = false
    if exactUsable then
        local ok, err = pcall(function()
            local ptr = ffiProj.ffi.cast("const void*", cc.camera)
            if ptr == nil or not isCameraPointer(ptr) then error("the camera field is not an Ogre::Camera") end
            local v = ffiProj.ogre.NP_getViewMatrix(ptr).m
            local p = ffiProj.ogre.NP_getProjMatrix(ptr).m
            if not matricesLookRight(v, p) then error("camera matrices have an unexpected shape") end
            ogreFov = { t = 1 / p[5], aspect = p[5] / p[0] }
            multiply(MFULL, p, v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11])
            local cx, cy, cz = camPos.x, camPos.y, camPos.z
            multiply(MRP, p,
                v[0], v[1], v[2], -(v[0] * cx + v[1] * cy + v[2] * cz),
                v[4], v[5], v[6], -(v[4] * cx + v[5] * cy + v[6] * cz),
                v[8], v[9], v[10], -(v[8] * cx + v[9] * cy + v[10] * cz))
        end)
        if ok then exactOk = true else disableExact(tostring(err)) end
    end
    if preferred ~= "fb" and exactOk then
        projMode = preferred
    elseif fbOk then
        projMode = "fb"
    else
        projMode = "none"
    end
    if projMode == "none" then warnOnce("camera", "camera data unavailable") end
    return projMode ~= "none"
end

local function projectMatrix(M, x, y, z)
    local cw = M[13] * x + M[14] * y + M[15] * z + M[16]
    if cw <= 1e-3 then return nil end
    local cx = M[1] * x + M[2] * y + M[3] * z + M[4]
    local cy = M[5] * x + M[6] * y + M[7] * z + M[8]
    return (cx / cw * 0.5 + 0.5) * W, (0.5 - cy / cw * 0.5) * H
end

local function projectFallback(x, y, z)
    if not fbReady then return nil end
    local dx, dy, dz = x - camPos.x, y - camPos.y, z - camPos.z
    local zc = dx * fb.fx + dy * fb.fy + dz * fb.fz
    if zc <= 1e-2 then return nil end
    local xc = dx * fb.rx + dy * fb.ry + dz * fb.rz
    local yc = dx * fb.ux + dy * fb.uy + dz * fb.uz
    local aspect = fb.aspect or W / H
    return W * 0.5 + (xc / zc) / (fb.t * aspect) * W * 0.5, H * 0.5 - (yc / zc) / fb.t * H * 0.5
end

local function projectWith(mode, x, y, z)
    if mode == "rp" then return projectMatrix(MRP, x, y, z) end
    if mode == "full" then return projectMatrix(MFULL, x, y, z) end
    if mode == "fb" then return projectFallback(x, y, z) end
    return nil
end

local function project(x, y, z) return projectWith(projMode, x, y, z) end

local function onScreen(sx, sy, margin)
    return sx ~= nil and sx > -margin and sx < W + margin and sy > -margin and sy < H + margin
end

-- When the projection in use keeps missing a character the game sees, switch to one that agrees.
local misses = 0
local function crossCheck(pos)
    if projMode == "none" or currentCamera == nil then return end
    local okV, gameSees = pcall(function() return currentCamera:isVisible(pos) end)
    if not okV or not gameSees then return end
    local sees = {}
    for _, mode in ipairs({ "rp", "full", "fb" }) do
        local available = mode == "fb" or exactUsable
        local sx, sy = nil, nil
        if available then sx, sy = projectWith(mode, pos.x, pos.y, pos.z) end
        sees[mode] = available and onScreen(sx, sy, 0)
    end
    if sees[projMode] then misses = 0 return end
    misses = misses + 1
    if misses < 3 then return end
    for _, mode in ipairs({ "rp", "full", "fb" }) do
        if sees[mode] then
            log(TAG .. "projection switched from " .. projMode .. " to " .. mode .. " (it agrees with the game)")
            preferred, projMode, misses = mode, mode, 0
            return
        end
    end
end

-- ===================================================================================
-- Character height: standing height from the head bone, or from the appearance for bodies without one
-- ===================================================================================
-- Character::getBoneWorldPosition and Character::getAppearance use Character::animation (+0x448) with no null
-- check, and the game crashes on a character without one (pcall cannot catch that). KenshiLua gives the field
-- as a light userdata, so a null one is not nil: its address is compared through ffi.
local ffiForChecks = nil
do
    local ok, f = pcall(require, "ffi")
    if ok then ffiForChecks = f end
end
local function hasAnimation(c)
    local a = c.animation
    if a == nil or ffiForChecks == nil then return false end
    return ffiForChecks.cast("uintptr_t", a) ~= 0
end

local HEAD_BONES = { "Bip01 HeadNub", "Bip01 Head" }
local DEFAULT_HEIGHT = 18
local heightRatio = nil      -- head-bone height / appearance height, learned from humans

local function appearanceHeight(c)
    if not hasAnimation(c) then return nil end
    local ok, h = pcall(function() return c:getAppearance():getCharacterHeight() end)
    if ok and type(h) == "number" and h > 0 then return h end
    return nil
end

-- updates p.standH (standing height above the feet) from the current pose
local function updateHeight(p, c, feet)
    if p.bone ~= false and hasAnimation(c) then
        for _, name in ipairs(p.bone and { p.bone } or HEAD_BONES) do
            local ok, head = pcall(function() return c:getBoneWorldPosition(name) end)
            if ok and head and head.y and abs(head.y - feet.y) > 1e-3 then
                p.bone = name
                local hh = head.y - feet.y
                -- lying or crouching samples are lower than the standing height: only grow, or settle slowly
                if p.standH == nil or hh > p.standH then
                    p.standH = hh
                elseif hh > p.standH * 0.85 then
                    p.standH = lerp(p.standH, hh, 0.2)
                end
                local ah = appearanceHeight(c)
                if ah and hh > ah * 0.4 then heightRatio = heightRatio and lerp(heightRatio, hh / ah, 0.05) or hh / ah end
                return
            end
        end
        p.bone = false
    end
    if p.standH == nil then
        local ah = appearanceHeight(c)
        if ah and heightRatio then p.standH = ah * heightRatio else p.standH = DEFAULT_HEIGHT end
    end
end

-- ===================================================================================
-- Health reading
-- ===================================================================================
-- returns: koFrac (0..1, 0 = knocked out), deathFrac (0..1, 0 = dead), unconscious, dead, bloodFrac or nil
-- The game's health of a part is flesh minus stun: a hit takes cut, pierce and part of the blunt damage from
-- flesh and puts the rest of the blunt damage (and any extra stun) into stun, which wears off later
-- (HealthPartStatus::applyDamage). Death comes only from flesh.
local function readHealth(c)
    local med = c.medical
    if med == nil then med = c:getMedical() end
    local koFrac, deathFrac, anyFrac = 1, 1, 1
    local vital = false
    for _, part in ipairs(med.anatomy) do
        local mh = part:maxHealth()
        if mh and mh > 0 then
            local f = (part.flesh - (part.fleshStun or 0)) / mh
            anyFrac = min(anyFrac, f)
            if part.collapses then
                vital = true
                koFrac = min(koFrac, f)
            end
            if part.fatal then deathFrac = min(deathFrac, (part.flesh + mh) / mh) end
        end
    end
    if not vital then koFrac = anyFrac end
    local unconscious = med.unconcious == true
    local dead = med.dead == true
    local blood = nil
    local okB, maxBlood = pcall(function() return med:getMaxBlood() end)
    if okB and type(maxBlood) == "number" and maxBlood > 0 then blood = clamp(med.blood / maxBlood, 0, 1) end
    return clamp(koFrac, 0, 1), clamp(deathFrac, 0, 1), unconscious, dead, blood
end

-- ===================================================================================
-- Faction reaction
-- ===================================================================================
-- Character::isATrader() is "return platoon->getIsTrader()", and getIsTrader reads platoon->me->squadTemplate,
-- all without null checks: for a character with no squad (or a squad with no Platoon or template) the game
-- crashes, and pcall cannot catch that (crash 2026-10-18 20:29). Walk the same chain here first.
local function isTrader(c)
    local ap = c.platoon
    if ap == nil then return false end
    local p = ap.me
    if p == nil or p.squadTemplate == nil then return false end
    return c:isATrader() == true
end

local function reactionOf(c, pi, pf)
    local okP, isP = pcall(function() return c:isPlayerCharacter() end)
    if okP and isP then return "squad" end
    local okE, enemy = pcall(function() return pi:isEnemy(c) end)
    if okE and enemy then return "hostile" end
    if pf then
        local okF, f = pcall(function() return c:getFaction() end)
        if okF and f then
            local okA, ally = pcall(function() return pf.relations:isAlly(f) end)
            if okA and ally then return "friendly" end
            local okR, rel = pcall(function() return pf.relations:getFactionRelation(f) end)
            if okR and type(rel) == "number" then
                if rel <= CONFIG.unfriendlyBelow then return "unfriendly" end
                if rel >= CONFIG.friendlyAbove then return "friendly" end
            end
        end
    end
    return "neutral"
end

-- the knocked-out mark after the name, in the game language (lang/<code>.txt, script.ko_suffix)
local KO_SUFFIX = " " .. SETTINGS.text("ko_suffix")

-- ===================================================================================
-- Widgets: one group per plate, pooled
-- ===================================================================================
local plateSerial = 0
local freeGroups = {}
local widgetsOk = true

local colourCache = {}
local function colourOf(r, g, b)
    local qr, qg, qb = floor(r * 63 + 0.5), floor(g * 63 + 0.5), floor(b * 63 + 0.5)
    local key = qr * 4096 + qg * 64 + qb
    local col = colourCache[key]
    if col == nil then
        col = MyGUI.Colour.new(qr / 63, qg / 63, qb / 63, 1)
        colourCache[key] = col
    end
    return col, key
end

local function newImage(region, name)
    local w = MyGUI.createImageBox("ImageBox", 0, 0, 1, 1, name, CONFIG.layer)
    w:setImageTexture(TEXTURE)
    w:setImageTile(region.w, region.h)
    w:setImageCoord(region.x, region.y, region.w, region.h)
    w:setImageIndex(0)
    pcall(function() w:setNeedMouseFocus(false) end)
    pcall(function() w:setInheritsPick(false) end)
    w:setVisible(false)
    return w
end

local function newText(name)
    local t = MyGUI.createTextBox(TEXT_SKIN, 0, 0, 1, 1, name, CONFIG.layer)
    t:setFontName(FONTS[1].name)
    t:setTextAlign(MyGUI.Align.Center)
    pcall(function() t.textShadow = true end)
    pcall(function() t.textShadowColour = MyGUI.Colour.new(0, 0, 0, 1) end)
    pcall(function() t:setNeedMouseFocus(false) end)
    pcall(function() t:setInheritsPick(false) end)
    t:setVisible(false)
    return t
end

local function newGroup()
    plateSerial = plateSerial + 1
    local id = "Nameplates_" .. plateSerial .. "_"
    -- creation order is drawing order inside the layer: frame, trail, fill, spark, blood bar, icons, texts
    local g = {
        frame = newImage(REG.frame, id .. "frame"),
        trail = newImage(REG.fill, id .. "trail"),
        fill = newImage(REG.fill, id .. "fill"),
        spark = newImage(REG.spark, id .. "spark"),
        bframe = newImage(REG.bframe, id .. "bframe"),
        bfill = newImage(REG.bfill, id .. "bfill"),
        bicon = newImage(REG.bounty, id .. "bicon"),
        ticon = newImage(REG.trader, id .. "ticon"),
        colourKeys = {},
    }
    g.name = newText(id .. "name")
    g.amount = newText(id .. "amount")
    g.amount:setTextColour((colourOf(BOUNTY_TEXT[1], BOUNTY_TEXT[2], BOUNTY_TEXT[3])))
    g.fontLevel = 1
    return g
end

local function takeGroup()
    local g = table.remove(freeGroups)
    if g then return g end
    local ok, ng = pcall(newGroup)
    if ok and ng then return ng end
    widgetsOk = false
    warnOnce("widgets", "could not create plate widgets: " .. tostring(ng))
    return nil
end

local GROUP_PARTS = { "frame", "trail", "fill", "spark", "bframe", "bfill", "bicon", "ticon", "name", "amount" }
local function hideGroup(g)
    for _, k in ipairs(GROUP_PARTS) do
        local w = g[k]
        if w then pcall(function() w:setVisible(false) end) end
    end
end

local function releaseGroup(g)
    hideGroup(g)
    g.caption, g.textW = nil, nil
    g.amountCaption, g.amountW = nil, nil
    freeGroups[#freeGroups + 1] = g
end

local function setTint(g, part, r, gr, b)
    local col, key = colourOf(r, gr, b)
    if g.colourKeys[part] ~= key then
        g.colourKeys[part] = key
        if part == "name" then g.name:setTextColour(col) else g[part]:setColour(col) end
    end
end

local function place(w, x, y, ww, hh, alpha)
    w:setCoord(floor(x + 0.5), floor(y + 0.5), max(1, floor(ww + 0.5)), max(1, floor(hh + 0.5)))
    w:setAlpha(alpha)
    w:setVisible(true)
end

-- ===================================================================================
-- Plates
-- ===================================================================================
local plates = {}        -- key -> plate
local clock = 0
local hitAt = {}         -- key -> time of the last melee hit (event)

local function newPlate(c, key)
    local ref = handleRef(c)
    if ref == nil then return nil end
    return {
        key = key, ref = ref, alpha = 0, wanted = true, group = nil,
        ko = 1, death = 1, unconscious = false, blood = nil,
        shownFrac = nil, trailFrac = nil, trailHold = 0,
        lastHurt = -1e9, healthTimer = 0, bone = nil, standH = nil, keepUntil = -1e9, scale = nil,
        sx = nil, sy = nil, bodyPx = nil, reaction = "neutral", name = nil,
    }
end

-- reads health into the plate and notes wounds; returns false when the character is dead
local function refreshHealth(p, c)
    local ok, ko, death, unconscious, dead, blood = pcall(readHealth, c)
    if not ok then warnOnce("health", "health reading failed: " .. tostring(ko)) return true end
    if dead then return false end
    local okD, isDead = pcall(function() return c:isDead() end)
    if okD and isDead then return false end
    if ko < p.ko - 1e-3 or death < p.death - 1e-3 or (blood and p.blood and blood < p.blood - 0.01) or (unconscious and not p.unconscious) then
        p.lastHurt = clock
    end
    p.ko, p.death, p.unconscious, p.blood = ko, death, unconscious, blood
    return true
end

local UNITS_PER_METRE = 10     -- Kenshi's world unit is a decimetre (a human is about 18 units tall)
local PRIORITY = { hostile = 1, unfriendly = 2, squad = 3, friendly = 4, neutral = 4 }

local squadPos = {}
local function collectSquad(pi)
    for i = #squadPos, 1, -1 do squadPos[i] = nil end
    local ok, list = pcall(function() return pi.playerCharacters end)
    if not ok or list == nil then return end
    for _, c in ipairs(list) do
        local okP, pos = pcall(function() return c:getPosition() end)
        if okP and pos then squadPos[#squadPos + 1] = { x = pos.x, z = pos.z } end
    end
end

-- metres on the ground from the nearest of your characters (huge when you have none loaded)
local function squadDistance(pos)
    local best = math.huge
    for _, q in ipairs(squadPos) do
        local dx, dz = pos.x - q.x, pos.z - q.z
        local d = dx * dx + dz * dz
        if d < best then best = d end
    end
    return sqrt(best) / UNITS_PER_METRE
end

local function selectedKey(pi)
    local ok, k = pcall(function() return tostring(pi.selectedObject:toString()) end)
    if ok then return k end
    return nil
end

-- inside a building whose interior you are not looking at (roof on)
local function hiddenIndoors(c, pi)
    if not CONFIG.hideIndoors then return false end
    local ok, h = pcall(function() return c:isIndoors() end)
    if not ok or h == nil then return false end
    local okV, inside = pcall(function() return (not h:isNull()) and h:isValid() end)
    if not okV or not inside then return false end
    local okB, b = pcall(function() return h:getBuilding() end)
    if okB and b then
        local okI, open = pcall(function() return pi:getInteriorsVisible(b) end)
        if okI and open then return false end
    end
    return true
end

-- fighting = hit or hurt recently. Character::isInCombatMode is not asked: it reads the melee and ranged
-- combat objects without null checks and would crash the game on a character missing one.
local function fighting(c, key, p)
    if hitAt[key] and clock - hitAt[key] < CONFIG.fightSeconds then return true end
    return p ~= nil and clock - p.lastHurt < CONFIG.fightSeconds
end

-- choose who gets a plate: on screen, alive, needed by the settings (or still kept), most important first
local scanList = {}
local crossTimer = 0
local scanId = 0
local function rescan()
    local world = getGameWorld and getGameWorld()
    if world == nil then return end
    local okSet, set = pcall(function() return world:getCharacterUpdateList() end)
    if not okSet or set == nil then warnOnce("scan", "character list unavailable") return end
    local pi = playerInterface()
    if pi == nil then return end
    local okPf, pf = pcall(function() return pi:getFaction() end)
    if not okPf then pf = nil end
    collectSquad(pi)
    local selKey = selectedKey(pi)

    for i = #scanList, 1, -1 do scanList[i] = nil end
    local nearest = nil
    for c in pairs(set) do
        local okP, pos = pcall(function() return c:getPosition() end)
        if okP and pos then
            local seen = nil
            if currentCamera then
                local okV, v = pcall(function() return currentCamera:isVisible(pos) end)
                if okV then seen = v end
            end
            if seen == nil then
                local x, y = project(pos.x, pos.y, pos.z)
                seen = onScreen(x, y, 0.1 * W)
            end
            local key = (seen and not hiddenIndoors(c, pi)) and keyOf(c) or nil
            -- a corpse never gets a plate: skip it before its faction, bounty and health are read, which on a
            -- battlefield full of bodies is most of the work of every scan (a plate it had fades out)
            if key then
                local okD, dead = pcall(function() return c:isDead() end)
                if okD and dead == true then key = nil end
            end
            if key then
                if nearest == nil then nearest = pos end
                local p = plates[key]
                local reaction = reactionOf(c, pi, pf)
                local mode = CONFIG.show[reaction] or "never"
                local selected = key == selKey
                local dist = squadDistance(pos)
                local want = selected or mode == "always"
                if not want and (mode == "near" or mode == "fighting") then
                    -- a plate already shown leaves the range a bit later than a new one enters it
                    local range = (p and p.wanted) and CONFIG.squadRange * 1.15 or CONFIG.squadRange
                    want = (mode == "near" and dist <= range) or fighting(c, key, p)
                end
                if want or (p and p.keepUntil > clock) then
                    scanList[#scanList + 1] = { c = c, key = key, pos = pos, reaction = reaction, dist = dist,
                        selected = selected, want = want, prio = PRIORITY[reaction] or 5 }
                end
            end
        end
    end
    table.sort(scanList, function(a, b)
        if a.selected ~= b.selected then return a.selected end
        if a.want ~= b.want then return a.want end
        if a.prio ~= b.prio then return a.prio < b.prio end
        return a.dist < b.dist
    end)

    crossTimer = crossTimer - CONFIG.scanInterval
    if crossTimer <= 0 and nearest then
        crossTimer = 2
        crossCheck(nearest)
    end

    scanId = scanId + 1
    for _, p in pairs(plates) do p.wanted = false end
    local taken = 0
    for _, e in ipairs(scanList) do
        if taken >= CONFIG.maxPlates then break end
        local p = plates[e.key]
        if p == nil then
            p = newPlate(e.c, e.key)
            if p then plates[e.key] = p end
        end
        if p then
            p.scanId = scanId
            p.reaction = e.reaction
            p.dist = e.dist
            if CONFIG.showBounty then
                local okB, b = pcall(function() return e.c.crimes:getTotalBounty() end)
                p.bounty = okB and type(b) == "number" and b or 0
            end
            if CONFIG.showTrader then
                local okT, t = pcall(isTrader, e.c)
                p.trader = okT and t == true
            end
            if CONFIG.showUnique then
                -- Character::isUnique reads the "unique" flag of the character's own data (always present)
                local okU, u = pcall(function() return e.c:isUnique() end)
                p.unique = okU and u == true
            end
            local alive = refreshHealth(p, e.c)
            updateHeight(p, e.c, e.pos)
            -- a downed stranger takes no place among maxPlates, so in a big battle the plates go to those standing
            local hidden = CONFIG.hideDowned and p.unconscious and e.reaction ~= "squad" and not e.selected
            if alive and not hidden then
                local okN, n = pcall(function() return e.c:getName() end)
                if okN and type(n) == "string" then p.name = n end
                if e.want then p.keepUntil = clock + CONFIG.keepSeconds end
                p.wanted = true
                taken = taken + 1
            end
        end
    end
end

-- per-frame state of one plate (no widgets): health, screen position, fade; returns false to drop the plate
local function updatePlate(p, dt)
    local c = resolve(p.ref)
    local feet = nil
    if c then
        local okF, f = pcall(function() return c:getPosition() end)
        if okF then feet = f end
    end
    if feet == nil then p.wanted = false end

    -- health at its own rate
    if c and p.wanted then
        p.healthTimer = p.healthTimer - dt
        if p.healthTimer <= 0 then
            p.healthTimer = CONFIG.healthInterval
            if not refreshHealth(p, c) then p.wanted = false end
        end
    end

    -- screen position: above the standing height, smoothed so plates glide instead of shaking
    local bodyAlpha = 0
    local scaleTarget = p.scale or 1
    if feet and p.standH then
        local top = p.standH * 1.1
        local sx, sy = project(feet.x, feet.y + top, feet.z)
        local _, footY = project(feet.x, feet.y, feet.z)
        if sx and footY then
            local bodyPx = abs(footY - sy) / 1.1
            if p.sx == nil then
                p.sx, p.sy = sx, sy
            else
                p.sx, p.sy = approach(p.sx, sx, 22, dt), approach(p.sy, sy, 22, dt)
            end
            p.bodyPx = bodyPx
            local lo = CONFIG.minBodyPx * resScale
            bodyAlpha = clamp((bodyPx - lo) / (3 * resScale), 0, 1)
            scaleTarget = clamp(bodyPx / (CONFIG.fullSizeBodyPx * resScale), CONFIG.minScale, 1)
        else
            p.wanted = false
        end
    end

    p.scale = p.scale and approach(p.scale, scaleTarget, 6, dt) or scaleTarget
    local target = p.wanted and bodyAlpha or 0
    p.alpha = approach(p.alpha, target, p.wanted and 10 or 14, dt)
    if not p.wanted and p.alpha < 0.02 then
        -- faded out: give the widgets back, keep tracking while the last scan still sees the character
        if p.group then releaseGroup(p.group) p.group = nil end
        p.alpha = 0
        return c ~= nil and p.scanId == scanId
    end

    -- bar values: health until knock-out, or distance from death when knocked out
    local frac = p.unconscious and p.death or p.ko
    if p.shownFrac == nil then p.shownFrac, p.trailFrac = frac, frac end
    if frac < p.shownFrac - 1e-3 then
        if p.trailFrac < p.shownFrac then p.trailFrac = p.shownFrac end
        p.trailHold = 0.45
    end
    p.shownFrac = approach(p.shownFrac, frac, 16, dt)
    if p.trailHold > 0 then
        p.trailHold = p.trailHold - dt
    else
        p.trailFrac = approach(p.trailFrac, p.shownFrac, 4.5, dt)
    end
    if p.trailFrac < p.shownFrac then p.trailFrac = p.shownFrac end
    return true
end

-- size of a plate on screen: width (bar or name, whichever is wider) and height (name + bar + blood bar)
-- 12000 -> "12 000"
local function formatAmount(n)
    local digits = tostring(floor(n))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (grouped:gsub("^ ", ""))
end

-- font for a plate size, with a little hysteresis so the font does not flip back and forth
local function fontLevelFor(scale, current)
    for level, f in ipairs(FONTS) do
        local margin = (current and level >= current) and -0.03 or 0.03
        if scale >= f.from + (f.from > 0 and margin or 0) then return level end
    end
    return #FONTS
end

local function plateBox(p)
    local s = resScale * (p.scale or 1)
    local showBlood = CONFIG.showBlood and p.blood ~= nil and p.blood < 0.995
    local level = p.group and p.group.fontLevel or fontLevelFor(p.scale or 1, nil)
    local nameH = CONFIG.showNames and (FONTS[level].px + 1) or 0
    local h = REG.frame.h * s + (showBlood and (REG.bframe.h + 1) * s or 0) + nameH
    local w = max(REG.frame.w * s, p.textW or 0) + 4 * s
    return w, h, showBlood
end

-- Crowds: like WoW's stacking nameplates. Plates are placed one by one, hostile first, then by distance;
-- a plate that would cover an already placed one moves up above it. Plates pushed higher than
-- CONFIG.stackMaxRise plate heights fade out. The offset is smoothed, so plates slide instead of jumping.
local PRIORITY = { hostile = 1, unfriendly = 2, squad = 3, friendly = 4, neutral = 4 }
local placed = {}
local function stackOrder(a, b)
    if a.wanted ~= b.wanted then return a.wanted end
    local pa, pb = PRIORITY[a.reaction] or 5, PRIORITY[b.reaction] or 5
    if pa ~= pb then return pa < pb end
    if a.dist ~= b.dist then return (a.dist or 0) < (b.dist or 0) end
    return a.key < b.key
end

local function layoutStack(list, dt)
    table.sort(list, stackOrder)
    for i = #placed, 1, -1 do placed[i] = nil end
    local gap = 2 * resScale
    for _, p in ipairs(list) do
        local w, h = plateBox(p)
        local x0, x1 = p.sx - w * 0.5, p.sx + w * 0.5
        local bottom = p.sy
        local moved, passes = true, 0
        while moved and passes <= #placed do
            moved, passes = false, passes + 1
            for _, q in ipairs(placed) do
                if x0 < q.x1 and q.x0 < x1 and bottom - h < q.bottom and q.top < bottom then
                    bottom = q.top - gap
                    moved = true
                end
            end
        end
        local rise = p.sy - bottom
        p.crowded = CONFIG.stacking and rise > CONFIG.stackMaxRise * h or false
        if not CONFIG.stacking then rise = 0 end
        if p.wanted and not p.crowded then
            placed[#placed + 1] = { x0 = x0, x1 = x1, top = bottom - h, bottom = bottom }
        end
        if p.stackY == nil then
            p.stackY = rise
        elseif not p.crowded then
            p.stackY = approach(p.stackY, rise, 12, dt)
        end
        p.crowdAlpha = approach(p.crowdAlpha or 1, p.crowded and 0 or 1, 10, dt)
    end
end

-- widgets of one plate at its stacked position
local function drawPlate(p)
    if p.group == nil then
        if not widgetsOk then return false end
        p.group = takeGroup()
        if p.group == nil then return false end
    end
    local g = p.group
    local a = p.alpha * (p.crowdAlpha or 1)
    if a < 0.01 then hideGroup(g) return true end

    local s = resScale * (p.scale or 1)
    local _, _, showBlood = plateBox(p)
    local frameW, frameH = REG.frame.w * s, REG.frame.h * s
    local barW, barH = REG.fill.w * s, REG.fill.h * s
    local x0 = p.sx - frameW * 0.5
    local bottom = p.sy - (p.stackY or 0)
    local bloodBlock = showBlood and (REG.bframe.h + 1) * s or 0
    local frameY = bottom - frameH - bloodBlock
    local barX, barY = x0 + 2 * s, frameY + 2 * s

    -- colours
    local col = COLOURS[p.reaction] or COLOURS.neutral
    local r, gg, b = col.bar[1], col.bar[2], col.bar[3]
    if p.unconscious then r, gg, b = MARKS.dying[1], MARKS.dying[2], MARKS.dying[3] end
    if not p.unconscious and p.shownFrac < 0.25 then
        local pulse = 0.5 + 0.5 * math.sin(clock * 9)
        local k = (0.25 - p.shownFrac) / 0.25 * 0.35 * pulse
        r, gg, b = lerp(r, 1, k), lerp(gg, 1, k), lerp(b, 1, k)
    end
    setTint(g, "fill", r, gg, b)
    setTint(g, "trail", MARKS.trail[1], MARKS.trail[2], MARKS.trail[3])
    setTint(g, "bfill", MARKS.blood[1], MARKS.blood[2], MARKS.blood[3])

    place(g.frame, x0, frameY, frameW, frameH, a * 0.95)
    if p.trailFrac > p.shownFrac + 0.003 and not p.unconscious then
        place(g.trail, barX, barY, barW * p.trailFrac, barH, a * 0.85)
    else
        g.trail:setVisible(false)
    end
    if p.shownFrac > 0.002 then
        place(g.fill, barX, barY, barW * p.shownFrac, barH, a)
    else
        g.fill:setVisible(false)
    end
    if p.shownFrac > 0.02 and p.shownFrac < 0.995 then
        place(g.spark, barX + barW * p.shownFrac - REG.spark.w * s * 0.5, barY, REG.spark.w * s, barH, a * 0.55)
    else
        g.spark:setVisible(false)
    end
    if showBlood then
        local by = bottom - REG.bframe.h * s
        place(g.bframe, x0, by, frameW, REG.bframe.h * s, a * 0.9)
        place(g.bfill, x0 + 2 * s, by + 1 * s, REG.bfill.w * s * p.blood, REG.bfill.h * s, a)
    else
        g.bframe:setVisible(false)
        g.bfill:setVisible(false)
    end

    if not CONFIG.showNames then
        g.name:setVisible(false)
        g.amount:setVisible(false)
        g.bicon:setVisible(false)
        g.ticon:setVisible(false)
        p.textW = nil
    else
        local caption = (p.name or "") .. (p.unconscious and KO_SUFFIX or "")
        local level = fontLevelFor(p.scale or 1, g.fontLevel)
        if level ~= g.fontLevel then
            g.fontLevel = level
            g.name:setFontName(FONTS[level].name)
            g.amount:setFontName(FONTS[level].name)
            g.caption, g.amountCaption = nil, nil  -- measure the texts again in the new font
        end
        if g.caption ~= caption then
            g.caption = caption
            g.name:setCaption(caption)
            local okT, tw = pcall(function() return g.name:getTextSize() end)
            g.textW = okT and type(tw) == "number" and tw or nil
        end
        local amountText = (CONFIG.showBounty and p.bounty and p.bounty > 0) and formatAmount(p.bounty) or nil
        if g.amountCaption ~= amountText then
            g.amountCaption = amountText
            g.amount:setCaption(amountText or "")
            local okA, aw = pcall(function() return g.amount:getTextSize() end)
            g.amountW = okA and type(aw) == "number" and aw or nil
        end
        local unique = CONFIG.showUnique and p.unique and p.reaction ~= "squad"
        local nc = p.unconscious and KO_NAME or (unique and MARKS.unique) or col.name
        setTint(g, "name", nc[1], nc[2], nc[3])

        -- one centred line: [skull] [coins] name amount
        local fpx = FONTS[g.fontLevel].px
        local th = fpx + 3
        local nameY = frameY - th + 1
        local iconPx, gap = fpx + 1, 3
        local icons = {}
        if CONFIG.showBounty and p.bounty and p.bounty > 0 then icons[#icons + 1] = g.bicon else g.bicon:setVisible(false) end
        if CONFIG.showTrader and p.trader then icons[#icons + 1] = g.ticon else g.ticon:setVisible(false) end
        local nameW = g.textW or #caption * fpx * 0.5
        local amountW = amountText and (g.amountW or #amountText * fpx * 0.5) or 0
        local total = #icons * (iconPx + gap) + nameW + (amountText and 2 * gap + amountW or 0)
        local x = p.sx - total * 0.5
        for _, w in ipairs(icons) do
            place(w, x, nameY + (th - iconPx) * 0.5, iconPx, iconPx, a)
            x = x + iconPx + gap
        end
        place(g.name, x - 2, nameY, nameW + 4, th, a)
        x = x + nameW + 2 * gap
        if amountText then
            place(g.amount, x - 2, nameY, amountW + 4, th, a)
        else
            g.amount:setVisible(false)
        end
        p.textW = total
    end
    return true
end

local active = {}
local function animateAll(dt)
    for i = #active, 1, -1 do active[i] = nil end
    for key, p in pairs(plates) do
        local ok, keep = pcall(updatePlate, p, dt)
        if not ok then warnOnce("animate", "plate error: " .. tostring(keep)) end
        if not ok or not keep then
            if p.group then releaseGroup(p.group) p.group = nil end
            plates[key] = nil
        elseif p.alpha >= 0.01 and p.sx ~= nil and onScreen(p.sx, p.sy, 150) then
            active[#active + 1] = p
        elseif p.group then
            hideGroup(p.group)
        end
    end
    local okS, errS = pcall(layoutStack, active, dt)
    if not okS then warnOnce("stack", "stacking error: " .. tostring(errS)) end
    for _, p in ipairs(active) do
        local ok, keep = pcall(drawPlate, p)
        if not ok then warnOnce("draw", "plate drawing error: " .. tostring(keep)) end
        if not ok or not keep then
            if p.group then releaseGroup(p.group) p.group = nil end
            plates[p.key] = nil
        end
    end
end

-- ===================================================================================
-- Events and frame loop
-- ===================================================================================
local function safeOn(event, fn)
    local ok, err = pcall(function() Events.on(event, fn) end)
    if not ok then warnOnce("event " .. event, "could not subscribe to " .. event .. ": " .. tostring(err)) end
end

-- both sides of a melee hit are fighting: the one hit and the one who swung
safeOn("Character::_NV_hitByMeleeAttack", function(self, cutDir, damage, attacker)
    local key = keyOf(self)
    if key then hitAt[key] = clock end
    if attacker ~= nil then
        local okA, ak = pcall(keyOf, attacker)
        if okA and ak then hitAt[ak] = clock end
    end
end)

local scanTimer, sizeTimer = 0, 0
local keyWasDown, keyToggled, hiddenByKey = false, false, false

-- whether the hotkey setting lets plates show now
local function hotkeyAllows()
    if CONFIG.hotkeyMode ~= "hold" and CONFIG.hotkeyMode ~= "toggle" then return true end
    if KEYS == nil then
        warnOnce("keys", "the keyboard cannot be read (no ffi): plates show without the key")
        return true
    end
    local vk = HOTKEYS[CONFIG.hotkey]
    if vk == nil then
        warnOnce("hotkey " .. tostring(CONFIG.hotkey), "unknown hotkey " .. tostring(CONFIG.hotkey) .. ": plates show without it")
        return true
    end
    local down = KEYS.focused() and KEYS.down(vk)
    local pressed = down and not keyWasDown
    keyWasDown = down
    if CONFIG.hotkeyMode == "hold" then return down end
    if pressed then keyToggled = not keyToggled end
    return keyToggled
end
local errors = 0
local announced = false
local lastWall = nil

local function frameTime(arg)
    local now = os.clock()
    local dt
    if lastWall and now > lastWall then dt = now - lastWall end
    lastWall = now
    if dt == nil then dt = tonumber(arg) or 0.016 end
    return clamp(dt, 0, 0.1)
end

local function frame(time)
    local dt = frameTime(time)
    clock = clock + dt
    sizeTimer = sizeTimer - dt
    if sizeTimer <= 0 then updateViewSize() sizeTimer = 2 end
    if not updateCamera() then
        for key, p in pairs(plates) do
            if p.group then releaseGroup(p.group) end
            plates[key] = nil
        end
        return
    end
    if not announced then
        announced = true
        log(TAG .. string.format("running: projection=%s screen=%dx%d", projMode, W, H))
        if ogreFov then
            -- a human is about 18 game units (decimetres) to the head; plate size limits are in 1080p pixels
            local t = ogreFov.t
            local full = 540 * 18 / (CONFIG.fullSizeBodyPx * t) / 10
            local tiny = 540 * 18 / (CONFIG.minBodyPx * t) / 10
            log(TAG .. string.format("camera field of view %.1f degrees: plates are full size up to %.0f m from the camera, shrink beyond, vanish past %.0f m",
                math.deg(2 * math.atan(t)), full, tiny))
        end
    end
    scanTimer = scanTimer - dt
    if scanTimer <= 0 then
        rescan()
        scanTimer = CONFIG.scanInterval
        for key, t in pairs(hitAt) do
            if clock - t > CONFIG.fightSeconds then hitAt[key] = nil end
        end
    end
    animateAll(dt)
end

-- Settings (ini written by ModConfigMenu): read once now, then follow changes.
local SETTING_ROOTS = { CONFIG = CONFIG, COLOURS = COLOURS, MARKS = MARKS }
local function dropAllPlates()
    for key, p in pairs(plates) do
        if p.group then releaseGroup(p.group) end
        plates[key] = nil
    end
end

local function applySettingChanges(changed)
    deriveNameColours()
    for _, k in ipairs(changed) do
        if k == "Enabled" and not CONFIG.enabled then dropAllPlates() end
    end
    if #changed > 0 then log(TAG .. "settings changed: " .. table.concat(changed, ", ")) end
end

do
    local ok, changed, found = pcall(SETTINGS.apply, SETTING_ROOTS)
    deriveNameColours()
    if not ok then
        warnOnce("settings", "settings could not be read: " .. tostring(changed))
    else
        log(TAG .. "settings from " .. SETTINGS.iniPath() .. (found and "" or " (not written yet: defaults)")
            .. (SETTINGS.pluginLoaded() and "" or ", MCM plugin not loaded"))
    end
end

local lastPollWall = nil
local function pollSettings()
    local now = os.clock()
    local dt = lastPollWall and now - lastPollWall or 0
    lastPollWall = now
    local ok, changed = pcall(SETTINGS.poll, dt, SETTING_ROOTS)
    if not ok then warnOnce("settings-poll", "settings poll failed: " .. tostring(changed)) return end
    if changed then applySettingChanges(changed) end
end

safeOn("MyGUI::Gui::eventFrameStart", function(time)
    pollSettings()
    if not CONFIG.enabled then return end
    local okKey, wanted = pcall(hotkeyAllows)
    if not okKey then
        warnOnce("hotkey-error", "hotkey error: " .. tostring(wanted))
    elseif not wanted then
        if not hiddenByKey then dropAllPlates() hiddenByKey = true end
        return
    elseif hiddenByKey then
        hiddenByKey = false
        scanTimer = 0   -- plates come back at once (they fade in)
    end
    local ok, err = pcall(frame, time)
    if not ok then
        errors = errors + 1
        warnOnce("frame" .. tostring(err), "frame error: " .. tostring(err))
        if errors > 200 then
            CONFIG.enabled = false
            log(TAG .. "too many errors, nameplates switched off for this session")
        end
    end
end)

-- ===================================================================================
-- Console commands (KenshiLua console): Nameplates.status() / toggle() / show("neutral", "fighting")
-- ===================================================================================
local api = {}
function api.status()
    local n, visible = 0, 0
    for _, p in pairs(plates) do
        n = n + 1
        if p.group and p.alpha > 0.05 then visible = visible + 1 end
    end
    return string.format("projection=%s screen=%dx%d plates=%d visible=%d pooled=%d enabled=%s",
        projMode, W, H, n, visible, #freeGroups, tostring(CONFIG.enabled))
end
function api.toggle()
    CONFIG.enabled = not CONFIG.enabled
    if not CONFIG.enabled then dropAllPlates() end
    return "nameplates " .. (CONFIG.enabled and "on" or "off")
end
function api.show(kind, mode)
    if CONFIG.show[kind] == nil then return "kinds: hostile, unfriendly, neutral, friendly, squad" end
    if mode ~= "always" and mode ~= "near" and mode ~= "fighting" and mode ~= "never" then
        return "modes: always, near, fighting, never"
    end
    CONFIG.show[kind] = mode
    return kind .. " plates: " .. mode
end
-- the live settings tables (for checks from the console)
function api.settings() return CONFIG, COLOURS, MARKS end
rawset(_G, "Nameplates", api)

log(TAG .. "loaded (ffi projection " .. (ffiProj and "ready" or "unavailable") .. ")")
