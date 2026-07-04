-- Gunk/settings.lua
-- In-game mod settings panel (Settings -> Mods -> Gunk). Cross-platform by design: works on PCVR AND Quest with
-- no file editing -- values persist through the game's own save system, not an on-disk INI the player would have
-- to find and hand-edit (impractical on a Quest standalone).
--
-- NOTCHED PRESETS, NOT SLIDERS (VR-driven redesign): the LuaModSettings API has no native slider value readout,
-- labels cannot be updated after creation, and a ShowMessageInWorld readout per change was awful in-headset. A
-- Buttons row shows its SELECTED option natively, so the current value is always visible -- each control offers
-- a small set of hand-picked values that are actually feasible for this game. Buttons(label, callbackFnName,
-- defaultIndex, options) with a 0-based index. A Header must precede any control.
--
-- Every callback persists via game.SaveInt under a gunk_cfg_* key -- SAME keys and units as the old sliders, so
-- gunk.lua / gunk_watcher.lua are untouched (percent stored as whole ints, sub-second/sub-metre stored as
-- TENTHS). The default index at build time is the notch NEAREST the SAVED value (so the panel re-opens at what
-- the player actually set, and any old free-slider value snaps to the closest preset). The literal fallbacks
-- MUST match the consumers' LoadInt defaults.
--
-- The ADVR linter rejects the semicolon character anywhere, even in comments.

-- Value tables: index 1..n maps to the option labels passed to Buttons (same order).
DAMAGE_OPTS = {20, 40, 80, 150}         -- percent of (Primary + Secondary)
HOP_OPTS = {100, 130, 180, 250}         -- percent hop height
ATKHOP_OPTS = {100, 130, 180, 250}      -- percent extra pounce while hunting (100 = none)
SPEED_OPTS = {80, 106, 130, 160}        -- percent move speed
HUNT_OPTS = {4, 6, 8, 10}               -- metres
LEASH_OPTS = {8, 12, 16, 20}            -- metres
SPITCD_OPTS = {20, 36, 50, 80}          -- TICKS (tenths of a second): 2 / 3.6 / 5 / 8 seconds
SPITSPEED_OPTS = {30, 50, 80, 120}      -- TENTHS of a m/s: 3 / 5 / 8 / 12 (gunk.lua divides by 10 -- fresh key
                                        -- gunk_cfg_spit_speed_x10, the old whole-m/s key is abandoned)
SPITRANGE_OPTS = {5, 8, 10, 12}         -- metres
SPITSPLASH_OPTS = {8, 12, 16, 20}       -- TENTHS of a metre: 0.8 / 1.2 / 1.6 / 2.0 m
TEASER_OPTS = {1, 2, 3, 5}              -- seconds

function GunkCfgLoad(key, fallback)
    local v = fallback
    pcall(function() v = game.LoadInt(key, fallback) end)
    return v
end

-- 0-based index of the notch nearest the saved value (old free-slider values snap to the closest preset).
function GunkNearestIdx(values, saved)
    local best = 1
    local bestDiff = math.abs(values[1] - saved)
    for i = 2, #values do
        local d = math.abs(values[i] - saved)
        if d < bestDiff then
            bestDiff = d
            best = i
        end
    end
    return best - 1
end

function GunkCfgPick(key, values, buttonIndex)
    local i = math.floor(buttonIndex + 0.5) + 1
    if i < 1 then
        i = 1
    end
    if i > #values then
        i = #values
    end
    pcall(function() game.SaveInt(key, values[i]) end)
end

function onModSettingsInit(settingsObject)
    settingsObject.Header("Gunk - Combat")
    settingsObject.Buttons("Damage", "GunkCfgDamage",
        GunkNearestIdx(DAMAGE_OPTS, GunkCfgLoad("gunk_cfg_damage_pct", 40)), {"20%", "40%", "80%", "150%"})
    settingsObject.Buttons("Hop Height", "GunkCfgJump",
        GunkNearestIdx(HOP_OPTS, GunkCfgLoad("gunk_cfg_jump_pct", 130)), {"100%", "130%", "180%", "250%"})
    settingsObject.Buttons("Attack Hop", "GunkCfgAtkJump",
        GunkNearestIdx(ATKHOP_OPTS, GunkCfgLoad("gunk_cfg_atkjump_pct", 130)), {"100%", "130%", "180%", "250%"})
    settingsObject.Buttons("Move Speed", "GunkCfgSpeed",
        GunkNearestIdx(SPEED_OPTS, GunkCfgLoad("gunk_cfg_speed_pct", 106)), {"80%", "106%", "130%", "160%"})

    settingsObject.Header("Gunk - Behavior")
    settingsObject.Buttons("Hunt Range", "GunkCfgHunt",
        GunkNearestIdx(HUNT_OPTS, GunkCfgLoad("gunk_cfg_hunt_m", 6)), {"4 m", "6 m", "8 m", "10 m"})
    settingsObject.Buttons("Leash", "GunkCfgLeash",
        GunkNearestIdx(LEASH_OPTS, GunkCfgLoad("gunk_cfg_leash_m", 12)), {"8 m", "12 m", "16 m", "20 m"})

    settingsObject.Header("Gunk - Spitter")
    settingsObject.Buttons("Spit Cooldown", "GunkCfgSpitCd",
        GunkNearestIdx(SPITCD_OPTS, GunkCfgLoad("gunk_cfg_spit_cd", 36)), {"2 s", "3.6 s", "5 s", "8 s"})
    settingsObject.Buttons("Spit Speed", "GunkCfgSpitSpeed",
        GunkNearestIdx(SPITSPEED_OPTS, GunkCfgLoad("gunk_cfg_spit_speed_x10", 50)), {"3 m/s", "5 m/s", "8 m/s", "12 m/s"})
    settingsObject.Buttons("Spit Range", "GunkCfgSpitRange",
        GunkNearestIdx(SPITRANGE_OPTS, GunkCfgLoad("gunk_cfg_spit_range", 8)), {"5 m", "8 m", "10 m", "12 m"})
    settingsObject.Buttons("Spit Splash", "GunkCfgSpitSplash",
        GunkNearestIdx(SPITSPLASH_OPTS, GunkCfgLoad("gunk_cfg_spit_splash", 12)), {"0.8 m", "1.2 m", "1.6 m", "2 m"})

    settingsObject.Header("Gunk - Unlock")
    -- gunk_cfg_require_ng stores 1 = "New Game Plus" (index 0), 0 = "Any Run" (index 1).
    local ngIdx = 0
    if GunkCfgLoad("gunk_cfg_require_ng", 1) == 0 then
        ngIdx = 1
    end
    settingsObject.Buttons("Appears At", "GunkCfgRequireNg", ngIdx, {"New Game Plus", "Any Run"})
    -- Spitter form: 0 = the story rule (corrupted at NG++), 1 = always the acid-spitter, 2 = never (stays the
    -- harmless melee buddy). Stored value IS the index. Applies LIVE - gunk.lua overlays it within ~2s.
    settingsObject.Buttons("Spitter Form", "GunkCfgSpitterMode",
        GunkCfgLoad("gunk_cfg_spitter_mode", 0), {"At NG++", "Always", "Never"})
    -- How long after the relic thuds into the muck the teaser text appears (it stays up 7s either way).
    settingsObject.Buttons("Teaser Delay", "GunkCfgTeaserDelay",
        GunkNearestIdx(TEASER_OPTS, GunkCfgLoad("gunk_cfg_teaser_delay", 2)), {"1 s", "2 s", "3 s", "5 s"})
end

function GunkCfgDamage(buttonIndex)
    GunkCfgPick("gunk_cfg_damage_pct", DAMAGE_OPTS, buttonIndex)
end

function GunkCfgJump(buttonIndex)
    GunkCfgPick("gunk_cfg_jump_pct", HOP_OPTS, buttonIndex)
end

function GunkCfgAtkJump(buttonIndex)
    GunkCfgPick("gunk_cfg_atkjump_pct", ATKHOP_OPTS, buttonIndex)
end

function GunkCfgSpeed(buttonIndex)
    GunkCfgPick("gunk_cfg_speed_pct", SPEED_OPTS, buttonIndex)
end

function GunkCfgHunt(buttonIndex)
    GunkCfgPick("gunk_cfg_hunt_m", HUNT_OPTS, buttonIndex)
end

function GunkCfgLeash(buttonIndex)
    GunkCfgPick("gunk_cfg_leash_m", LEASH_OPTS, buttonIndex)
end

function GunkCfgSpitCd(buttonIndex)
    GunkCfgPick("gunk_cfg_spit_cd", SPITCD_OPTS, buttonIndex)
end

function GunkCfgSpitSpeed(buttonIndex)
    GunkCfgPick("gunk_cfg_spit_speed_x10", SPITSPEED_OPTS, buttonIndex)
end

function GunkCfgSpitRange(buttonIndex)
    GunkCfgPick("gunk_cfg_spit_range", SPITRANGE_OPTS, buttonIndex)
end

function GunkCfgSpitSplash(buttonIndex)
    GunkCfgPick("gunk_cfg_spit_splash", SPITSPLASH_OPTS, buttonIndex)
end

function GunkCfgTeaserDelay(buttonIndex)
    GunkCfgPick("gunk_cfg_teaser_delay", TEASER_OPTS, buttonIndex)
end

function GunkCfgRequireNg(buttonIndex)
    pcall(function() game.SaveInt("gunk_cfg_require_ng", buttonIndex == 0 and 1 or 0) end)
end

function GunkCfgSpitterMode(buttonIndex)
    pcall(function() game.SaveInt("gunk_cfg_spitter_mode", math.floor(buttonIndex + 0.5)) end)
end
