-- Gunk/progress_shops/acolyte/gunk_watcher.lua
-- THE swamp detector -- the single script that drops Gunk's relic, on BOTH fresh AND resumed runs.
--
-- WHY a progress-shop script: mod achievements receive world/room callbacks only on a run STARTED fresh from the
-- home base -- on a RESUMED (continue) run they are inert (only onLoad fires, proven via logs). An insight upgrade
-- with registerEventsWhenNotBought = true keeps its events active even when never purchased, and progress-shops
-- are one of the few content types that receive onGlobalTick (items/weapons/challenges/progress_shops -- NOT
-- achievements). onGlobalTick fires every active-run tick regardless of how the run was entered, so this polls
-- the swamp condition and drops the relic no matter what.
--
-- STATE: run-scoped saves (player.StoreSavedRunBool/LoadSavedRunBool -- auto-reset each new run, auto-restored on
-- resume, per the reference doc section 10). gunk_spawned_run = a relic was dropped this run (dedupe guard).
-- gunk_recruited_run = the relic was taken this run (written by gunk.lua onPickup). Because these live in the RUN
-- save, a new run starts clean with zero reset code, and a resumed run remembers both -- which powers the
-- RE-DELIVERY path: on resume a held mod relic is DORMANT (its onPickup does not re-fire, so it neither ticks nor
-- counts as active), so if recruited-this-run is true but the relic is not active shortly after a load, we re-drop
-- it at the player's feet on ANY floor -- grabbing it re-runs RegisterItem() and revives the companion.
--
-- The ADVR linter rejects the semicolon character anywhere (even comments). objects.* / dungeonFloor.* only inside
-- functions.

function GunkWatchLog(message)
    logging.Log("[Gunk-watch] " .. message)
end

function ADVR.onLoad()
    progress.name = "Gunk's Watcher"
    progress.desc = "Keeps watch for a lost slimeling in the Noxious Sewers (New Game Plus by default - changeable in Mod Settings). Always active - buying this does nothing extra."
    progress.predecessor = nil        -- root -- no dependency on any other upgrade to register
    progress.price = 5
    progress.registerEventsWhenBought = true
    progress.registerEventsWhenNotBought = true   -- KEY: active (and ticking) even if the player never buys it
    progress.globalTickDelay = 1.0    -- poll ~1x/sec -- cheap, and fires on resumed runs (unlike world callbacks)
end

function ADVR.ProgressEvents.onBuy()
end

GraceTicks = 0        -- countdown after every observed load routine, so the drop never fires mid-teleport
SinceLoad = 999       -- ticks since the last load routine ended -- re-delivery only in this short window
REDELIVER_WINDOW = 30 -- ~30s after a load in which a recruited-but-inactive relic is re-dropped
StaleCleared = true   -- flips false when a load routine is observed -> triggers the ONE-SHOT stale-flag clear
DropCooldown = 0      -- hard minimum spacing between two drops -- belt-and-braces against ANY flag failure
DROP_COOLDOWN = 60    -- ~60s
PendingTeaser = 0     -- countdown to the drop teaser -- shown DELAYED so the floor-name banner (which the game
TEASER_DELAY = 2      -- superimposes at floor entry, right when the drop fires) clears before the text appears.
                      -- This is the DEFAULT (VR-tuned: 6 -> 4 -> 3 -> 2) -- player-overridable via the settings
                      -- panel's "Teaser Delay" slider (gunk_cfg_teaser_delay, read at each drop)

function ADVR.onGlobalTick()
    -- Load gate FIRST. On a resumed run this tick fires while the game is still loading, BEFORE the dungeon
    -- finishes generating and BEFORE the player is teleported in -- dropping then puts the relic at a garbage
    -- position (the void) with the message flashing on the black load screen. Track EVERY load routine (not just
    -- the first after launch) and hold off a few ticks after each one ends.
    local inLoad = false
    pcall(function() inLoad = game.runSaveManager.isInLoadRoutine end)
    if inLoad then
        GraceTicks = 3
        SinceLoad = 0
        StaleCleared = false
        PendingTeaser = 0
        return
    end
    if GraceTicks > 0 then
        GraceTicks = GraceTicks - 1
        return
    end
    SinceLoad = SinceLoad + 1
    if DropCooldown > 0 then
        DropCooldown = DropCooldown - 1
    end
    -- Cheap, most-selective gates first (this runs 1x/sec forever, on every save).
    local inMenu = false
    pcall(function() inMenu = game.IsInMenu() end)
    if inMenu then
        return   -- menus / between runs -- never drop outside active play
    end
    if player == nil or player.transform == nil then
        return
    end
    local ng = -1
    pcall(function() ng = player.newGamePlusLevel end)
    -- Player-configurable unlock (Settings -> Mods -> Gunk -> "Appears At"): 1 = NG+ only (default, the earned
    -- unlock), 0 = any run. Global save key written by settings.lua's GunkCfgRequireNg.
    local requireNg = 1
    pcall(function() requireNg = game.LoadInt("gunk_cfg_require_ng", 1) end)
    if requireNg == 1 and ng < 1 then
        return   -- NG+ mode: excludes NG0 saves at the cost of two cheap reads per second
    end
    -- Run-scoped state (auto-reset on new run, auto-restored on resume).
    local recruited = false
    pcall(function() recruited = player.LoadSavedRunBool("gunk_recruited_run", false) end)
    local already = false
    pcall(function() already = player.LoadSavedRunBool("gunk_spawned_run", false) end)
    -- Actual relic ownership -- the ground truth. A mod relic only functions after pickup.RegisterItem() runs (in
    -- onPickup), and onPickup does NOT re-fire on a resumed run, so on resume AmountActiveLocal() reads 0 even if
    -- the relic was held at quit.
    local owned = 0
    pcall(function()
        local p = game.itemInterpreter.GetPickupById("gunk")
        if p ~= nil then
            owned = p.AmountActiveLocal()
        end
    end)
    if owned > 0 then
        PendingTeaser = 0   -- grabbed before the teaser fired -- the recruit lore takes over, skip the teaser
        return   -- actually holding the relic -> the relic itself drives the companion
    end
    -- Delayed teaser: fires TEASER_DELAY ticks after the drop, once the location banner has cleared, and stays
    -- up longer (7s) so it can actually be read. Must run BEFORE the already-dropped early-return below.
    if PendingTeaser > 0 then
        PendingTeaser = PendingTeaser - 1
        if PendingTeaser == 0 then
            pcall(function()
                game.ShowMessageInWorld("Something small tumbles into the muck nearby - better go grab it.", 7)
            end)
        end
    end
    -- ONE-SHOT stale clear after each load: whatever this run's save recorded (relic dropped-on-ground or held
    -- at quit) did NOT survive the reload -- ground pickups are not restored and held mod relics come back
    -- dormant -- so clear the dedupe flag once, letting the drop below re-deliver. STRICTLY once per load: a
    -- continuous in-window clear also wipes the record of the drop we make right after the load, owned stays 0
    -- while the relic sits on the ground, and a fresh relic drops EVERY TICK (the "relics kept spawning" bug).
    if not StaleCleared then
        StaleCleared = true
        if already then
            pcall(function() player.StoreSavedRunBool("gunk_spawned_run", false) end)
            already = false
        end
    end
    if already then
        return   -- a relic is already on the ground this run, waiting to be grabbed
    end
    -- Eligibility: the RESCUE (first meeting -- Noxious Sewers at NG+), or RE-DELIVERY right after a load of a
    -- run where he was already recruited (any floor -- he is this run's companion, give him back).
    local inSewers = false
    pcall(function()
        local wg = game.currentWorldGenerator
        if wg ~= nil and wg.worldGeneratorFloor == dungeonFloor.NOXIOUS_SEWERS then
            inSewers = true
        end
    end)
    local redeliver = recruited and SinceLoad < REDELIVER_WINDOW
    if not inSewers and not redeliver then
        return
    end
    -- BELT-AND-BRACES: even if every save flag silently failed, never two drops within DROP_COOLDOWN. This can
    -- only ever delay a legitimate drop, never block one.
    if DropCooldown > 0 then
        return
    end
    -- Only the master client spawns the shared relic AND owns the guard/teaser -- a non-master must not burn its
    -- local flag or show the message for a drop that never happened on its side (each client runs this script in
    -- isolation with per-client saves).
    local isMaster = true
    pcall(function() isMaster = game.IsMasterClient() end)
    if not isMaster then
        return
    end
    -- Guard BEFORE the drop (DropItem can throw uncatchably -- flag-first prevents a re-fire flood), then drop via
    -- the generic relic-pickup prefab parameterized with the relic id -- a bare "gunk" id is not a spawnable prefab.
    DropCooldown = DROP_COOLDOWN
    pcall(function() player.StoreSavedRunBool("gunk_spawned_run", true) end)
    local pos = player.transform.position + player.transform.forward * 1.0
    pcall(function() game.DropItem(objects.ITEM_UPGRADE_ALL .. ":gunk", pos) end)
    GunkWatchLog("dropped relic (ng=" .. tostring(ng) .. " sewers=" .. tostring(inSewers) .. " redeliver=" .. tostring(redeliver) .. ")")
    local td = TEASER_DELAY
    pcall(function() td = game.LoadInt("gunk_cfg_teaser_delay", TEASER_DELAY) end)
    if td < 1 then
        td = 1   -- 0 would arm a countdown that never fires (the show happens on the 1 -> 0 transition)
    end
    PendingTeaser = td
end
