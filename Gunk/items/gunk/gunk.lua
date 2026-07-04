-- Gunk/items/gunk/gunk.lua
-- Gunk the sewer slimeling -- the single companion relic. He is rescued in the Noxious Sewers (dropped by
-- progress_shops/acolyte/gunk_watcher.lua) and taken to recruit. He hops at your side, redirects his hop onto hostiles within
-- HUNT_RANGE and damages them by BODY CONTACT for (Primary + Secondary) * DAMAGE_MULT, and is an INVINCIBLE
-- companion -- RegisterInvincibility + canBeTargetedByWisps=false, because the game exposes NO faction API, so a
-- mortal enemy-body would be killed/attacked by the player's own relics + wisps. No coins, no tiers. At NG++ the
-- Spitter form is layered on (Phase 2).
--
-- HARD-WON LESSONS (do not regress):
--   * The ADVR linter rejects the semicolon character anywhere (even comments). deploy.ps1 blocks it.
--   * Never touch objects.* / damageType.* / sounds.* / hitFlashType.* / playerValues.* at TOP LEVEL (nil at
--     load) -- only inside functions. Raw-string spawn ids are load-safe.
--   * SpawnObjectNetwork with an UNKNOWN id throws a .NET host exception pcall CANNOT catch -- only known-good ids.
--   * Generic components from GetComponentInChildren expose FIELDS but THROW on properties/methods -- use the
--     TYPED accessor (GetComponent_AIJumpToEnemy_) for networkedCustomTarget etc.
--   * Never reparent the network slime -- it despawns. Follow/teleport via transform.position.
--   * onGlobalTick fires only while the relic is HELD -- holding it IS being recruited.
--   * pickup.sprite IS settable at runtime, but only to a Sprite object you already hold (burlap_blindfold.lua
--     nils/restores the SAME captured sprite). There is no documented Lua API to load a second PNG asset off
--     disk at runtime, so a melee->Spitter icon swap is NOT possible without a Unity asset bundle. Per the plan's
--     own fallback: one static icon (gunk.png) for both forms. gunk_corrupted.png ships as a future-use asset only.
--   * MULTIPLAYER, NOT FULLY GATED (deliberate, revisit if MP is ever prioritized): onPickup (authority-only, per
--     the reference doc's own canonical relic example) is the sole writer of gunk_recruited_run, and
--     onPickupProxies never touches it, so IsRecruited() should stay false on every client except the one who
--     actually recruited -- but nothing in this file explicitly checks game.IsMasterClient() before SpawnBody's
--     SpawnObjectNetwork or the three DoHit call sites. Whether the RECRUITING player's own client (if not the
--     session's master client) has enough authority to safely drive those calls is a Photon Fusion
--     input/state-authority question this doc set doesn't answer -- gating everything behind IsMasterClient()
--     would be WRONG if a non-host player is the one who recruited Gunk (their companion would never act). Left
--     as-is (relies on the onPickup/onPickupProxies split) until verified live in a co-op session.

BODY_ID = "enemy_ns_slime_tiny"           -- melee form: the Noxious Smol Slime (baby-Gunk look)
SPITTER_BODY_ID = "enemy_ns_slime_tiny"   -- spitter form: SAME smol body (the rotten Noxious Slime BODY was
                                          -- rejected as too big -- Gunk must stay smol). The corruption is shown
                                          -- as a rot-brown tint on his skin (ApplyCorruptionSkin -- material
                                          -- borrowing proved a no-op, all noxious slimes share one palette mat)

-- ===================== cached state =====================
Body = nil
BodyEnemy = nil
BodyAI = nil
BodyAIT = nil
TickCount = 0
NextSpawnTick = 0
NextBiteTick = 0
PlayerNetObj = nil
-- Who is the AI target: "enemy" (hunting), "player" (following, write confirmed), nil (not yet written -- retry).
-- One 3-state variable, so a hunt-state edit can never leave the two halves contradictory.
GunkTarget = nil
BaseJumpStrength = nil
BaseMoveSpeed = nil
BaseTimeBetweenJumps = nil
NextSpitTick = 0
SpitterEngaged = false      -- spitter currently has prey in range -- drives the calm artillery stance
SpitWindup = 0              -- ticks left in the pre-lob windup (launch fires when it reaches 0)
PostLob = 0                 -- ticks left in the post-lob recovery
Puddles = {}                -- active impact puddles {go, dieTick, lastHitTick} -- capped at PUDDLE_MAX
Spit = nil                  -- the one in-flight spit projectile {go, from, to, target, t} (flight << SPIT_CD)
BodyIsSpitter = nil         -- which form the CURRENT body was spawned as (nil = no body) -- drives the live
                            -- respawn into the corrupted body when the form changes mid-run
LastAnnouncedForm = nil     -- the last form a text line announced (nil = nothing announced this session).
                            -- onPickup's recruit lore sets it -- everything else goes through AnnounceForm()
-- Per-tick caches of the run-scoped saves (they never change outside this script's own writers, so caching them
-- avoids ~30 save-store marshals/sec on the 10 Hz tick). nil = not read yet (lazy init from the run save).
RecruitedCache = nil
FormCache = nil
-- Player's Spitter-form setting (0 = at NG++ per the story, 1 = always, 2 = never). Overlays the recruit-time
-- form lock LIVE -- refreshed by LoadGunkConfig on the 2s config cadence, so flipping the buttons in-headset
-- switches his form mid-run.
SpitterModeCache = 0
CFG_REFRESH_TICKS = 20      -- reload player settings + re-apply AI tuning every ~2s (live in-headset tuning)

-- ===================== tunables =====================
-- NOTE: DAMAGE_MULT / HUNT_RANGE / LEASH_DIST / SPEED_MODIFIER / JUMP_HEIGHT_MULT / ATTACK_JUMP_HEIGHT_MULT and
-- the spitter knobs SPIT_CD_TICKS / SPIT_SPEED / SPIT_RANGE / SPIT_SPLASH_RADIUS are player-overridable via the
-- in-game settings panel (Settings -> Mods -> Gunk, built by settings.lua). LoadGunkConfig() below overwrites
-- them from the saved gunk_cfg_* keys each refresh. The literals here are the FALLBACK defaults and MUST match
-- settings.lua's slider defaults, so the mod behaves identically if the player never opens the panel.
DAMAGE_MULT = 0.4            -- Gunk deals (Primary + Secondary) * this per hit. KEY tuning knob -- the stats are
                            -- small (~1-5), so a fraction of Primary alone collapsed to <1 ("only 1 dmg"). Shipped
                            -- relics use the SUM * 0.5..2 (gluttons_mark *1.5). Dial this for the right feel.
HUNT_RANGE = 6.0             -- redirect his hop onto the nearest hostile within this radius
MELEE_CONTACT = 0.7          -- body-contact reach
MELEE_BITE_CD = 8            -- ticks between contact-damage applications
LEASH_DIST = 12.0           -- past this from the player he despawns, respawns after RESPAWN_DELAY_TICKS
                            -- (was 10 -- VR feedback asked for 20% more leash)
RESPAWN_DELAY_TICKS = 50      -- ~5s at 0.1s/tick
RESPAWN_OFFSET = 1.5         -- every teleport/respawn places him this many metres from the player
SPEED_MODIFIER = 1.06        -- ~6% faster move (was 0.92 -- user asked +15%: 0.92 * 1.15 = 1.06)
JUMP_TIME_MULT = 1.08        -- ~8% longer between hops
JUMP_HEIGHT_MULT = 1.3       -- +30% base hop height -- applied to AIJumpToEnemy.jumpStrength
ATTACK_JUMP_HEIGHT_MULT = 1.3  -- when HUNTING an enemy, hop this much HIGHER again (stacks on JUMP_HEIGHT_MULT --
                            -- so an attack leap is ~1.69x base) so his pounce reads bigger than his idle follow-hop
GUNK_INVINCIBLE_ID = "gunk_companion"   -- RegisterInvincibility id -- invincible companion (no faction API exists)
-- Spitter form (NG++ only)
SPIT_RANGE = 8.0            -- spitter spits acid at the nearest VISIBLE hostile within this radius (LOS-filtered
                            -- via GetEnemiesInRadius onlyVisible=true -- no more spitting at prey through walls)
SPIT_CD_TICKS = 36          -- ticks between spits (~3.6s -- halved attack rate per VR feedback)
SPIT_SPLASH_RADIUS = 1.2    -- impact damage radius AT THE ACTUAL LANDING POINT -- a dodged glob honestly misses
SPIT_SPEED = 5.0            -- glob speed in m/s (the halve-to-2.5 experiment was reverted per VR verdict --
                            -- this is the tested-good value). Stored in TENTHS under gunk_cfg_spit_speed_x10
                            -- (fresh key -- the old whole-m/s key would misread as tenths)
SPIT_T_MIN = 0.35           -- flight-time clamp in seconds -- the cap MUST stay < SPIT_CD_TICKS * 0.1 (the
SPIT_T_MAX = 1.2            -- LoadGunkConfig cross-clamp enforces it)
SPIT_SCALE = 1.5            -- glob visual scale (+50% -- transform.localScale sticks on a non-enemy prop, it is
                            -- only networked ENEMIES whose native anim reverts scale writes, per the reference)
SPIT_ARC = 1.0              -- lob apex metres above the straight line -- the arc every flight follows
-- Artillery stance: while the Spitter has prey in spit range he CALMS DOWN instead of bouncing like melee Gunk
-- mid-attack (VR feedback) -- slower, lower, less frequent hops while he is lobbing.
SPITTER_ENGAGE_SPEED = 0.6    -- move-speed multiplier while engaged
SPITTER_ENGAGE_JUMPTIME = 1.5 -- longer pause between hops while engaged
SPITTER_ENGAGE_HOP = 0.8      -- lower hops while engaged
-- Lob window (final VR pass): 0.5s BEFORE the launch (windup) through 0.5s AFTER it (recovery), his movement
-- and hops drop ANOTHER 50% on top of the stance -- he visibly gathers himself, lobs, then recovers.
LOB_WINDOW_TICKS = 5          -- 0.5s each side of the launch
SPITTER_LOB_SPEED = 0.5       -- extra move-speed multiplier inside the lob window (0.6 * 0.5 = 0.3 total)
SPITTER_LOB_HOP = 0.5         -- extra hop multiplier inside the lob window (0.8 * 0.5 = 0.4 total)
-- Acid puddles are left by SPIT IMPACTS (not by his movement -- no wander-trail), so the ground hazard sits
-- exactly where he is fighting. Hard-capped and short-lived, cleaned on every room change.
PUDDLE_MAX = 4              -- max active impact puddles
PUDDLE_LIFETIME_TICKS = 30  -- ~3s per puddle
PUDDLE_RADIUS = 1.0         -- puddle damage radius
PUDDLE_TICK_TICKS = 5       -- ticks between a puddle's damage applications

function GunkLog(message)
    logging.Log("[Gunk] " .. message)
end

-- Read player-tunable settings (Settings -> Mods -> Gunk) into the live tunables. Defaults MATCH settings.lua's
-- slider defaults, so behaviour is identical whether or not the player ever opens the panel. Coordinated with
-- settings.lua only through these save keys (the two scripts are isolated Lua envs). Percent knobs are stored as
-- whole integers and divided by 100 here.
function LoadGunkConfig()
    pcall(function() DAMAGE_MULT = game.LoadInt("gunk_cfg_damage_pct", 40) / 100 end)
    pcall(function() JUMP_HEIGHT_MULT = game.LoadInt("gunk_cfg_jump_pct", 130) / 100 end)
    pcall(function() ATTACK_JUMP_HEIGHT_MULT = game.LoadInt("gunk_cfg_atkjump_pct", 130) / 100 end)
    pcall(function() SPEED_MODIFIER = game.LoadInt("gunk_cfg_speed_pct", 106) / 100 end)
    pcall(function() HUNT_RANGE = game.LoadInt("gunk_cfg_hunt_m", 6) end)
    pcall(function() LEASH_DIST = game.LoadInt("gunk_cfg_leash_m", 12) end)
    pcall(function() SpitterModeCache = game.LoadInt("gunk_cfg_spitter_mode", 0) end)
    -- Spitter knobs (Settings -> Mods -> Gunk -> "Gunk - Spitter"). Cooldown/splash sliders store TENTHS.
    pcall(function() SPIT_CD_TICKS = game.LoadInt("gunk_cfg_spit_cd", 36) end)
    pcall(function() SPIT_SPEED = game.LoadInt("gunk_cfg_spit_speed_x10", 50) / 10 end)
    pcall(function() SPIT_RANGE = game.LoadInt("gunk_cfg_spit_range", 8) end)
    pcall(function() SPIT_SPLASH_RADIUS = game.LoadInt("gunk_cfg_spit_splash", 12) / 10 end)
    -- CROSS-CLAMP: the sliders allow Hunt Range (up to 12) > Leash (down to 5), which would let a chase breach
    -- the leash mid-charge -> despawn -> respawn -> re-acquire -> permanent despawn loop (companion absent from
    -- every fight with no error). The leash must always exceed the hunt range.
    if LEASH_DIST < HUNT_RANGE + 2 then
        LEASH_DIST = HUNT_RANGE + 2
    end
    -- CROSS-CLAMP: the cooldown must exceed the longest possible flight (SPIT_T_MAX), or every launch would
    -- delete the previous glob mid-air (single-slot Spit). And SPIT_SPEED divides -- never let it reach 0.
    if SPIT_CD_TICKS < SPIT_T_MAX * 10 + 2 then
        SPIT_CD_TICKS = SPIT_T_MAX * 10 + 2
    end
    if SPIT_SPEED < 0.5 then
        SPIT_SPEED = 0.5
    end
end

-- Set jumpStrength for the CURRENT state: base * JUMP_HEIGHT_MULT normally, and an extra * ATTACK_JUMP_HEIGHT_MULT
-- while hunting an enemy (a higher pounce). Idempotent (always from BaseJumpStrength). Called on every hunt-state
-- transition (SetHuntTarget / ClearHuntTarget) for an immediate response, and on the throttled config refresh.
function ApplyJumpHeight()
    if BodyAI == nil or BaseJumpStrength == nil then
        return
    end
    local mult = JUMP_HEIGHT_MULT
    if GunkTarget == "enemy" then
        mult = mult * ATTACK_JUMP_HEIGHT_MULT
    end
    if SpitterEngaged then
        mult = mult * SPITTER_ENGAGE_HOP
    end
    if InLobWindow() then
        mult = mult * SPITTER_LOB_HOP
    end
    pcall(function() BodyAI.jumpStrength = BaseJumpStrength * mult end)
end

function InLobWindow()
    return SpitWindup > 0 or PostLob > 0
end

-- Re-apply the movement tunables to the LIVE AI from the (possibly just-reloaded) config. Uses the captured base
-- values so it is idempotent -- safe to call every refresh without the multipliers compounding. This is what
-- makes hop-height / speed sliders take effect in-headset without a redeploy or floor change.
function ReapplyAITuning()
    if BodyAI == nil then
        return
    end
    ApplyJumpHeight()
    if BaseTimeBetweenJumps ~= nil then
        local jt = JUMP_TIME_MULT
        if SpitterEngaged then
            jt = jt * SPITTER_ENGAGE_JUMPTIME
        end
        pcall(function() BodyAI.timeBetweenJumps = BaseTimeBetweenJumps * jt end)
    end
    if BaseMoveSpeed ~= nil then
        local sp = SPEED_MODIFIER
        if SpitterEngaged then
            sp = sp * SPITTER_ENGAGE_SPEED
        end
        if InLobWindow() then
            sp = sp * SPITTER_LOB_SPEED
        end
        pcall(function() BodyAI.moveSpeed = BaseMoveSpeed * sp end)
    end
end

-- ----------------- recruit / form state (RUN-SCOPED saves, cached) -----------------
-- player.StoreSavedRunBool/Int live in the RUN save: auto-reset on every new run, auto-restored on resume (doc
-- section 10). That kills the whole class of stale-flag bugs by construction -- an abandoned run's recruit/form
-- can never leak into the next run, and no home-base/launch reset code is needed. The values only change through
-- this script's own writers (onPickup / ResetGunkRun), so they are cached in plain Lua vars for the 10 Hz tick.
function IsRecruited()
    if RecruitedCache == nil then
        local v = false
        pcall(function() v = player.LoadSavedRunBool("gunk_recruited_run", false) end)
        RecruitedCache = v
    end
    return RecruitedCache
end

function IsSpitter()
    -- Player setting overlays the story rule: 1 = always spitter, 2 = never. 0 falls through to the run's
    -- recruit-time form lock (corrupted if recruited at NG++).
    if SpitterModeCache == 1 then
        return true
    end
    if SpitterModeCache == 2 then
        return false
    end
    if FormCache == nil then
        local v = 0
        pcall(function() v = player.LoadSavedRunInt("gunk_form_run", 0) end)
        FormCache = v
    end
    return FormCache == 1
end

function GunkSpeak(message, duration)
    local d = duration or 4
    pcall(function() game.ShowMessageInWorld(message, d) end)
    pcall(function()
        -- onPickup (the only caller) always fires before Body exists -- fall back to the player's position so
        -- the recruit/corruption lines are never silently mute.
        local pos = nil
        if Body ~= nil then
            pos = Body.transform.position
        elseif player ~= nil and player.transform ~= nil then
            pos = player.transform.position
        end
        if pos ~= nil then
            audio.PlaySoundLocal(sounds.ENEMY_LD_SLIME_CRYSTAL_TELEPORT, pos)
        end
    end)
end

function SafeDelete(obj)
    if obj ~= nil then
        pcall(function() game.Delete(obj) end)
    end
end

function DeleteGunk()
    ClearPuddles()
    SafeDelete(Body)
    Body = nil
    BodyEnemy = nil
    BodyAI = nil
    BodyAIT = nil
    GunkTarget = nil
    SpitterEngaged = false
    SpitWindup = 0
    PostLob = 0
end

-- 1.5 m behind the player, on the player's plane -- used for every spawn/respawn/teleport.
function RespawnPos()
    return player.transform.position - player.transform.forward * RESPAWN_OFFSET
end

function SpawnBody()
    SafeDelete(Body)
    Body = nil
    BodyEnemy = nil
    BodyAI = nil
    BodyAIT = nil
    BodyIsSpitter = nil
    -- Form-aware body: both forms now spawn the SAME smol prefab (the big rotten body was rejected), but the
    -- form still drives BodyIsSpitter so TameBody knows whether to apply the corruption skin -- and a live form
    -- flip still respawns (fresh, un-tinted materials to tint or leave clean).
    local wantSpitter = IsSpitter()
    local id = BODY_ID
    if wantSpitter then
        id = SPITTER_BODY_ID
    end
    local ok, spawned = pcall(function()
        return game.SpawnObjectNetwork(id, RespawnPos())
    end)
    if not ok or spawned == nil then
        GunkLog("body spawn failed id=" .. id)
        return
    end
    Body = spawned
    BodyIsSpitter = wantSpitter
    pcall(function() GunkLog("body spawned id=" .. id .. " name=" .. tostring(Body.name)) end)
end

function SpawnGunk(reason)
    if player == nil or player.transform == nil then
        GunkLog("spawn skipped, player not ready (" .. reason .. ")")
        return
    end
    NextSpawnTick = 0
    pcall(function() PlayerNetObj = player.networkObject end)
    DeleteGunk()
    SpawnBody()
end

function TameBody()
    if Body == nil then
        return
    end
    -- Fetch Gunk's OWN EnemyBase directly (identity-safe) instead of guessing via a nearest-in-radius scan --
    -- a radius scan could tame a different nearby hostile (same species as BODY_ID) and leave Gunk's real body
    -- mortal.
    local mine = nil
    pcall(function() mine = Body.GetComponent_EnemyBase_() end)
    if mine == nil then
        return
    end
    -- Invincible companion: no faction API exists, so the player's own AoE/kill relics treat a mortal enemy-body
    -- as a target. RegisterInvincibility is how the game's own companion avoids that. Also stop friendly wisps
    -- targeting him, and keep him harmless to the player.
    pcall(function() mine.RegisterInvincibility(GUNK_INVINCIBLE_ID) end)
    pcall(function() mine.canBeTargetedByWisps = false end)
    pcall(function() mine.touchDamage = 0 end)
    pcall(function() mine.hitFlashType = hitFlashType.NONE end)
    BodyEnemy = mine
    pcall(function() BodyAI = Body.GetComponentInChildren(game.GetType("AIJumpToEnemy")) end)
    if BodyAI ~= nil then
        -- Capture the prefab's BASE movement values once, then apply the config multipliers via ReapplyAITuning
        -- (idempotent). Capturing the base lets the settings sliders re-tune these live without compounding.
        pcall(function() BaseJumpStrength = BodyAI.jumpStrength end)
        pcall(function() BaseTimeBetweenJumps = BodyAI.timeBetweenJumps end)
        pcall(function() BaseMoveSpeed = BodyAI.moveSpeed end)
        ReapplyAITuning()
    end
    -- TYPED accessor for properties/methods (the generic handle throws on them).
    pcall(function() BodyAIT = Body.GetComponent_AIJumpToEnemy_() end)
    pcall(function() PlayerNetObj = player.networkObject end)
    -- Spitter corruption is a SKIN, not a different prefab: tint the freshly-spawned body. A form flip respawns
    -- the body (clean materials), then this re-runs and tints (or doesn't) to match.
    if BodyIsSpitter then
        ApplyCorruptionSkin()
    end
    AnnounceForm()
    GunkLog("tamed ai=" .. tostring(BodyAIT ~= nil))
end

-- Corruption skin: a ROT-BROWN TINT on Gunk's own material instance. This is the ONLY working lever, proven by
-- the VR loop + Player.log evidence:
--   * material BORROWING (live rotten slime or its prefab) is a NO-OP -- the log showed the rotten slime's
--     material is `palette_noxious_sewers`, the SAME shared biome material the tiny slime already wears. All
--     noxious slimes share one palette material -- the rotten one's distinct look lives in its mesh/UV mapping,
--     which nothing material-side can transfer. (The steal/prefab machinery was removed after that finding.)
--   * tinting IS visible (the over-bright first attempt proved it) -- so the corrupted look = a murky rotten
--     BROWN multiply + the faintest warm sheen, not a green glow.
--   * other paths are closed: no PNG re-texture (Sprite exposes no .texture, AssetBundles Windows-only), no
--     natively-small rotten variant in the objects enum, and slime bodies reject scale writes.
-- Renderers are found via the Renderer BASE type (slimes use SkinnedMeshRenderer -- a MeshRenderer search finds
-- nothing). r.material is that renderer's OWN instance copy, so the shared palette asset is never touched.
function PaintRendererAt(rends, i)
    local r = rends[i]
    if r == nil then
        return
    end
    if r.GetComponent_TextMeshPro_() ~= nil then
        return   -- the shipped glittering_orb skip -- never repaint floating text
    end
    local m = r.material
    if m ~= nil then
        -- MULTIPLY tint only -- NO emission. Emission is additive and textureless, so any amount of it washes a
        -- flat uniform sheet over the body's own shading (VR: "uniform color" in both the green AND the brown
        -- rounds). A pure m.color multiply darkens/browns the skin while keeping its native shading intact.
        m.color = colors.Create(0.6, 0.5, 0.33, 1)
    end
end

function ApplyCorruptionSkin()
    if Body == nil then
        return
    end
    local rends = nil
    pcall(function() rends = Body.GetComponentsInChildren(game.GetType("Renderer")) end)
    if rends == nil then
        return
    end
    local painted = 0
    for i = 0, #rends - 1 do
        local ok = pcall(PaintRendererAt, rends, i)
        if ok then
            painted = painted + 1
        end
    end
    GunkLog("corruption skin (rot tint) on " .. tostring(painted) .. " renderer(s)")
end

-- Speak when Gunk's EFFECTIVE form changes outside of a recruit: the Spitter Form setting can flip from the
-- main menu or mid-run, and onPickup (the only other text source) never re-fires -- without this the
-- transformation is silent (VR report: "the text doesn't drop for the spitter when I switch in the main menu
-- settings"). Called from TameBody, i.e. once per freshly-spawned body. Rules: a mid-session flip announces both
-- directions -- a session's FIRST body only announces if he comes back corrupted (a plain melee spawn right
-- after the recruit lore, or on a normal resume, needs no line).
function AnnounceForm()
    local form = IsSpitter()
    if LastAnnouncedForm == nil then
        if form then
            GunkSpeak("The sewer rot floods back into Gunk - his mouth fills with acid.", 6)
        end
    elseif LastAnnouncedForm ~= form then
        if form then
            GunkSpeak("The sewer rot floods back into Gunk - his mouth fills with acid.", 6)
        else
            GunkSpeak("The rot drains out of Gunk - he is his smol self again.", 6)
        end
    end
    LastAnnouncedForm = form
end

function GunkHitDamage()
    local p = 0
    local s = 0
    pcall(function() p = player.PrimaryDamage.GetValueFloat() end)
    pcall(function() s = player.SecondaryDamage.GetValueFloat() end)
    local d = (p + s) * DAMAGE_MULT
    if d < 1 then
        d = 1
    end
    return d
end

-- Shared hostile filter + per-enemy work as NAMED functions called via pcall(fn, args...) -- a named-function
-- pcall allocates NO closure, unlike pcall(function() end) which allocated one PER ENEMY PER TICK (~16+ per
-- combat tick at 10 Hz -- the dominant Lua-side GC pressure of the mod, and GC hitches hurt inside a VR frame
-- budget). The identity clauses (BodyEnemy/Body) stay even though the radius queries pass excludeInvincible=true:
-- they are load-bearing in the window before TameBody has registered his invincibility.
function IsHostile(e)
    return e ~= nil and e ~= BodyEnemy and e.gameObject ~= nil and e.gameObject ~= Body and not e.IsInvincible
end

-- One engine query, engine-side invincibility filter (4th arg -- the shipped pattern: siphoning_charge.lua,
-- deft_gesture.lua). losOnly maps to the 3rd arg (onlyVisible): the SPITTER passes true so he only targets prey
-- in line of sight (no spitting through walls) -- melee and puddle scans leave it false, because walls must not
-- hide prey from a companion (or a puddle) already standing next to it.
function ScanEnemies(radius, cpos, losOnly)
    local enemies = nil
    pcall(function() enemies = game.GetEnemiesInRadius(radius, cpos, losOnly == true, true) end)
    return enemies
end

-- pcall-isolated per-enemy candidate read: a throw on one stale/despawning reference must not silently truncate
-- the scan and hand back a non-nearest partial result.
function NearestAt(enemies, i, cpos)
    local e = enemies[i]
    if IsHostile(e) then
        return e, vector3.Distance(e.gameObject.transform.position, cpos)
    end
    return nil, nil
end

function NearestEnemy(enemies, cpos)
    if enemies == nil then
        return nil
    end
    local target = nil
    -- Accept ANY returned enemy: seeding with range+1 silently rejected big bodies whose collider is inside the
    -- radius but whose transform pivot sits past it (bosses) -- shipped scans seed with 9999 (deft_gesture.lua).
    local best = 999999
    for i = 0, #enemies - 1 do
        local ok, e, d = pcall(NearestAt, enemies, i, cpos)
        if ok and e ~= nil and d < best then
            best = d
            target = e
        end
    end
    return target
end

function SetHuntTarget(enemy)
    if BodyAIT == nil or enemy == nil then
        return
    end
    pcall(function()
        local no = enemy.networkObject
        if no ~= nil then
            BodyAIT.networkedCustomTarget = no
            BodyAIT.networkedHasSeenTarget = true
        end
    end)
    -- Even if this specific redirect failed, the target is no longer confirmed-player -- "enemy" makes
    -- ClearHuntTarget reassert the player once hunting ends.
    if GunkTarget ~= "enemy" then
        GunkTarget = "enemy"
        ApplyJumpHeight()   -- transition into hunting -> higher attack pounce
        -- His little war cry -- once per hunt engagement, so it reads as intent without being spammy.
        pcall(function() audio.PlaySoundLocal(sounds.ENEMY_NS_SLIME_TINY_IDLE, Body.transform.position) end)
        GunkLog("hunt -> enemy within " .. tostring(HUNT_RANGE) .. "m")
    end
end

-- Reasserts the player as Gunk's AI target whenever no prey is being hunted -- not just on the hunt->clear
-- transition, so a quiet tame/respawn with no hostile nearby still gets a target set. GunkTarget only becomes
-- "player" AFTER a successful write, so a failed pcall is retried on a later tick instead of getting stuck.
function ClearHuntTarget()
    if BodyAIT == nil or GunkTarget == "player" then
        return
    end
    local wrote = false
    pcall(function()
        if PlayerNetObj == nil then
            PlayerNetObj = player.networkObject
        end
        if PlayerNetObj ~= nil then
            BodyAIT.networkedCustomTarget = PlayerNetObj
            wrote = true
        end
    end)
    if wrote then
        if GunkTarget == "enemy" then
            GunkLog("hunt -> cleared, back to player")
        end
        GunkTarget = "player"
        ApplyJumpHeight()   -- back to following -> normal hop height
    end
end

-- Body contact: damage every hostile actually touching Gunk. This is his whole melee attack -- he hops like a
-- normal slime and whatever his body bumps takes (Primary + Secondary) * DAMAGE_MULT.
-- pcall-isolated per-enemy hit: a throw on one must not silently skip damage to the rest.
function BiteAt(enemies, i, dmg)
    local e = enemies[i]
    if IsHostile(e) then
        e.DoHit(player.networkObject, dmg, damageType.PLAYER_SECONDARY_NO_KNOCKBACK, e.gameObject.transform.position)
        return true
    end
    return false
end

function BiteNearby(cpos)
    local enemies = ScanEnemies(MELEE_CONTACT + 0.3, cpos)
    if enemies == nil or #enemies == 0 then
        return false
    end
    -- Two player-stat marshals -- only paid once something is actually in contact range (this used to run every
    -- combat tick regardless).
    local dmg = GunkHitDamage()
    local hit = false
    for i = 0, #enemies - 1 do
        local ok, h = pcall(BiteAt, enemies, i, dmg)
        if ok and h then
            hit = true
        end
    end
    if hit then
        -- A wet squish per landed bite volley (throttled by MELEE_BITE_CD) -- melee Gunk gets audible feedback
        -- like the Spitter's spit/impact sounds.
        pcall(function() audio.PlaySoundLocal(sounds.ENEMY_NS_SLIME_TINY_HIT, cpos) end)
    end
    return hit
end

-- ----------------- Spitter form (NG++): ranged acid spit whose impacts leave burning puddles -----------------
-- An acid puddle at a spit-impact point (damage 0 on the FX -- TickPuddles applies the real, ENEMY-ONLY DoHit).
-- Puddles come ONLY from impacts (no movement trail), so the ground hazard sits exactly where he is fighting.
-- Lifetime is SCRIPT-managed via dieTick + game.Delete: DespawnAfter is documented only on LivingBase and appears
-- NOWHERE in shipped gamedata -- on a ParticleDamage it silently no-ops inside pcall and every impact would leak
-- one permanent networked object. (The shipped POISON_TRAIL user, twice_baked_beans.lua, also uses game.Delete.)
function AddPuddleAt(tpos)
    local go = nil
    pcall(function() go = game.SpawnObjectNetwork(objects.EFFECT_POISON_TRAIL, tpos) end)
    if go == nil then
        return
    end
    pcall(function()
        local pd = go.GetComponent_ParticleDamage_()
        if pd ~= nil then
            pd.damage = 0
        end
    end)
    table.insert(Puddles, {go = go, dieTick = TickCount + PUDDLE_LIFETIME_TICKS, lastHitTick = 0})
    if #Puddles > PUDDLE_MAX then
        local old = table.remove(Puddles, 1)
        if old ~= nil then
            SafeDelete(old.go)
        end
    end
end

-- A VISIBLE spit: the game's OWN green slime-spit glob (objects.PROJECTILE_GREEN_SLIMESPIT -- what shooting
-- slimes fire, found in the official object-mapper docs) launched ballistically from Gunk's mouth -- the physics
-- engine flies the parabola (smooth at frame rate), the script only times the arrival, and the damage lands ON
-- IMPACT (not instantly at launch). The projectile is fully DISARMED at spawn -- colliders off, bullet logic
-- off -- so the ONLY damage anywhere is our own enemy-targeted DoHit at impact. Falls back to the old
-- script-lerped poison-FX glob if the projectile ever fails to spawn. One slot -- flight < the spit cooldown.
-- Per-item child-bullet disarm (named, pcall-called per component so one throw cannot abort the sweep). Fields
-- first (always work on generic handles), then .enabled in a nested pcall (a Behaviour property -- worked for
-- the Clarence AI/collider disables, but must not kill the field writes if it ever throws). Disabling matters:
-- a still-ENABLED child BulletBase keeps steering/clamping the rigidbody every frame -- the VR "flies low and
-- fast, lands short" flight was exactly that fighting our launch velocity.
function DisarmBulletAt(bbs, i)
    local b = bbs[i]
    if b ~= nil then
        b.damageMultiplier = 0
        b.destroyOnCollide = false
        b.distanceTillDestroy = 9999
        pcall(function() b.enabled = false end)
    end
end

function DisarmSpitGlob(fx, vel)
    -- Kill EVERY way the prefab could hurt or steer itself. Each step in its own pcall -- a missing component
    -- must not abort the rest.
    pcall(function()
        local bb = fx.GetComponent_BulletBase_()
        if bb ~= nil then
            bb.damageMultiplier = 0
            bb.destroyOnCollide = false      -- must survive brushing level geometry mid-arc
            bb.distanceTillDestroy = 9999    -- never self-expire -- lifetime is script-managed
            bb.enabled = false               -- stop its Update entirely (typed handle -- properties work)
        end
    end)
    pcall(function()
        local bbs = fx.GetComponentsInChildren(game.GetType("BulletBase"))
        if bbs ~= nil then
            for i = 0, #bbs - 1 do
                pcall(DisarmBulletAt, bbs, i)
            end
        end
    end)
    pcall(function()
        local pds = fx.GetComponentsInChildren(game.GetType("ParticleDamage"))
        if pds ~= nil then
            for i = 0, #pds - 1 do
                if pds[i] ~= nil then
                    pds[i].damage = 0
                end
            end
        end
    end)
    -- THE hard guarantee: no colliders, no contact -- with anything. A script-flown prop needs none (the impact
    -- is our own DoHit at arrival). Collider is a Unity type -- .enabled works on generic handles (the Clarence
    -- neutralize pattern).
    pcall(function()
        local cols = fx.GetComponentsInChildren(game.GetType("Collider"))
        if cols ~= nil then
            for i = 0, #cols - 1 do
                if cols[i] ~= nil then
                    cols[i].enabled = false
                end
            end
        end
    end)
    pcall(function()
        fx.transform.localScale = fx.transform.localScale * SPIT_SCALE
    end)
    -- Hand the glob to physics with gravity OFF and an initial velocity -- from here TickSpit STEERS it along
    -- the arc with a per-tick velocity correction (see TickSpit). Returns the rigidbody handle (nil = the FX
    -- fallback glob -> script-lerped positions instead).
    local rbOut = nil
    pcall(function()
        local rb = fx.GetComponentInChildren(game.GetType("Rigidbody"))
        if rb ~= nil then
            rb.isKinematic = false
            rb.useGravity = false
            local wrote = false
            pcall(function()
                rb.velocity = vel
                wrote = true
            end)
            if not wrote then
                pcall(function()
                    rb.linearVelocity = vel
                    wrote = true
                end)
            end
            if wrote then
                rbOut = rb
            end
        end
    end)
    return rbOut
end

function LaunchSpit(target)
    if Body == nil or target == nil then
        return
    end
    local cpos = nil
    pcall(function() cpos = Body.transform.position end)
    local tpos = nil
    pcall(function() tpos = target.gameObject.transform.position end)
    if cpos == nil or tpos == nil then
        return
    end
    ClearSpit()
    local from = cpos + vector3.__new(0, 0.3, 0)
    -- Flight time scales with distance (constant SPIT_SPEED). The initial velocity is just the straight line --
    -- TickSpit's per-tick steering bends it onto the arc from the first tick on.
    local T = vector3.Distance(from, tpos) / SPIT_SPEED
    if T < SPIT_T_MIN then
        T = SPIT_T_MIN
    end
    if T > SPIT_T_MAX then
        T = SPIT_T_MAX
    end
    local vel = (tpos - from) * (1 / T)
    local fx = nil
    pcall(function() fx = game.SpawnObjectNetwork(objects.PROJECTILE_GREEN_SLIMESPIT, from) end)
    if fx == nil then
        pcall(function() fx = game.SpawnObjectNetwork(objects.EFFECT_POISON_TRAIL, from) end)
    end
    if fx ~= nil then
        local rb = DisarmSpitGlob(fx, vel)
        Spit = {go = fx, from = from, to = tpos, t = 0, ticks = math.ceil(T * 10), rb = rb}
    end
    pcall(function() audio.PlaySoundLocal(sounds.ENEMY_LD_SLIME_CRYSTAL_TELEPORT, cpos) end)
end

-- The ideal point on the lob at progress tt (0..1): straight line from->to plus a sine arc peaking at SPIT_ARC.
function SpitPointAt(tt)
    local p = Spit.from + (Spit.to - Spit.from) * tt
    return p + vector3.__new(0, SPIT_ARC * math.sin(math.pi * tt), 0)
end

function TickSpit()
    if Spit == nil then
        return
    end
    Spit.t = Spit.t + 1 / Spit.ticks
    if Spit.t >= 1 then
        -- Impact: the glob is gone, and damage lands WHERE THE GLOB ACTUALLY LANDED (launch aim as fallback) --
        -- everything within the splash radius of that point is hit. No auto-hit on the aimed target: a glob that
        -- visibly missed genuinely misses (VR verdict -- damage-on-miss was off-putting). The puddle still forms
        -- at the impact point, so a near-miss keeps area-denial value.
        local tpos = Spit.to
        pcall(function() tpos = Spit.go.transform.position end)
        SafeDelete(Spit.go)
        Spit = nil
        local enemies = ScanEnemies(SPIT_SPLASH_RADIUS, tpos)
        if enemies ~= nil and #enemies > 0 then
            local dmg = GunkHitDamage()
            for i = 0, #enemies - 1 do
                pcall(BiteAt, enemies, i, dmg)
            end
        end
        AddPuddleAt(tpos)
        pcall(function() audio.PlaySoundLocal(sounds.ENEMY_NS_SLIME_ROTTEN_HIT, tpos) end)
        return
    end
    -- STEERED flight: every tick, point the rigidbody's velocity at the NEXT waypoint on the arc. Physics still
    -- integrates the motion every frame (smooth -- no 10 Hz teleport steps), but the correction re-captures the
    -- glob from anything the prefab does on its own -- a launch-only velocity VR-tested as "flies low and fast,
    -- lands short" (leftover per-frame prefab logic kept reshaping the flight), which also broke the damage,
    -- since damage lands where the glob lands. Steering guarantees arrival at the aim point.
    if Spit.rb ~= nil then
        pcall(function()
            local a = Spit.go.transform.position
            local nxt = SpitPointAt(math.min(Spit.t + 1 / Spit.ticks, 1))
            local v = (nxt - a) * 10
            local wrote = false
            pcall(function()
                Spit.rb.velocity = v
                wrote = true
            end)
            if not wrote then
                Spit.rb.linearVelocity = v
            end
        end)
    else
        -- FX-fallback glob (no rigidbody): script-lerped positions along the same arc.
        pcall(function()
            Spit.go.transform.position = SpitPointAt(Spit.t)
        end)
    end
end

function ClearSpit()
    if Spit ~= nil then
        SafeDelete(Spit.go)
        Spit = nil
    end
end

function TickPuddles()
    local i = 1
    while i <= #Puddles do
        local p = Puddles[i]
        if p == nil or p.go == nil or TickCount >= p.dieTick then
            if p ~= nil then
                SafeDelete(p.go)
            end
            table.remove(Puddles, i)
        else
            if TickCount - p.lastHitTick >= PUDDLE_TICK_TICKS then
                p.lastHitTick = TickCount
                local ppos = nil
                pcall(function() ppos = p.go.transform.position end)
                if ppos ~= nil then
                    local enemies = ScanEnemies(PUDDLE_RADIUS, ppos)
                    if enemies ~= nil and #enemies > 0 then
                        local dmg = GunkHitDamage()
                        for k = 0, #enemies - 1 do
                            pcall(BiteAt, enemies, k, dmg)
                        end
                    end
                end
            end
            i = i + 1
        end
    end
end

function ClearPuddles()
    for i = 1, #Puddles do
        if Puddles[i] ~= nil then
            SafeDelete(Puddles[i].go)
        end
    end
    Puddles = {}
    ClearSpit()
end

function Hunt()
    if Body == nil then
        return
    end
    local cpos = nil
    pcall(function() cpos = Body.transform.position end)
    if cpos == nil then
        return
    end
    if IsSpitter() then
        -- Spitter: stays glued to you and spits acid at the nearest hostile within SPIT_RANGE. ClearHuntTarget
        -- (early-outs once confirmed) matters on a LIVE melee->spitter switch: without it a mid-hunt Gunk would
        -- keep the enemy as his AI target forever, since the spitter branch never redirects it back.
        ClearHuntTarget()
        -- losOnly=true: a ranged attacker must not acquire (and waste spits on) prey behind walls.
        local t = NearestEnemy(ScanEnemies(SPIT_RANGE, cpos, true), cpos)
        -- Artillery stance transitions: prey in range -> calm down (slower, lower, rarer hops), range clear ->
        -- back to the normal follow bounce.
        local engaged = t ~= nil
        if engaged ~= SpitterEngaged then
            SpitterEngaged = engaged
            ReapplyAITuning()
        end
        -- Lob window state machine: cooldown ready + prey -> 0.5s WINDUP (deep slow) -> launch -> 0.5s RECOVERY
        -- (still deep slow) -> back to the plain stance. The deep slow brackets every lob instead of sitting on
        -- him permanently.
        if PostLob > 0 then
            PostLob = PostLob - 1
            if PostLob == 0 then
                ReapplyAITuning()   -- recovery over -> stance speed
            end
        end
        if SpitWindup > 0 then
            SpitWindup = SpitWindup - 1
            if SpitWindup == 0 then
                if t ~= nil then
                    NextSpitTick = TickCount + SPIT_CD_TICKS
                    LaunchSpit(t)
                end
                PostLob = LOB_WINDOW_TICKS
            end
        elseif t ~= nil and PostLob == 0 and TickCount >= NextSpitTick then
            SpitWindup = LOB_WINDOW_TICKS
            ReapplyAITuning()   -- windup begins -> deep slow
        end
        return
    end
    -- Melee form: make sure a live spitter->melee flip never strands the calm stance or a half-open lob window.
    if SpitterEngaged or SpitWindup > 0 or PostLob > 0 then
        SpitterEngaged = false
        SpitWindup = 0
        PostLob = 0
        ReapplyAITuning()
    end
    -- Melee: glued to you, but redirect his hop onto a hostile within HUNT_RANGE, damage on body contact.
    -- ONE engine scan serves target selection AND the empty-room early-out: the 6m query is collider-based and a
    -- superset of the 1m contact query, so an empty result means no bite scan (and no damage-stat marshals) needed.
    local enemies = ScanEnemies(HUNT_RANGE, cpos)
    if enemies == nil or #enemies == 0 then
        ClearHuntTarget()
        return
    end
    local prey = NearestEnemy(enemies, cpos)
    if prey ~= nil then
        SetHuntTarget(prey)
    else
        ClearHuntTarget()
    end
    if TickCount >= NextBiteTick then
        if BiteNearby(cpos) then
            NextBiteTick = TickCount + MELEE_BITE_CD
        end
    end
end

-- Leash: past LEASH_DIST he despawns, and onGlobalTick respawns him 1.5 m behind you after RESPAWN_DELAY_TICKS.
function LeashBody()
    if Body == nil then
        return
    end
    local tooFar = false
    pcall(function()
        if vector3.Distance(player.transform.position, Body.transform.position) > LEASH_DIST then
            tooFar = true
        end
    end)
    if tooFar then
        DeleteGunk()
        NextSpawnTick = TickCount + RESPAWN_DELAY_TICKS
        GunkLog("too far -> despawn, respawn in ~5s")
    end
end

function ResetGunkRun(reason)
    DeleteGunk()
    -- Belt-and-braces: run-scoped saves reset themselves on every NEW run, but clearing here too keeps the state
    -- honest for the remainder of THIS session (e.g. between death and the next run starting).
    pcall(function() player.StoreSavedRunBool("gunk_recruited_run", false) end)
    pcall(function() player.StoreSavedRunBool("gunk_spawned_run", false) end)
    RecruitedCache = false
    FormCache = 0
    GunkLog("reset run (" .. reason .. ")")
end

-- ===================== ADVR callbacks =====================
function ADVR.onLoad()
    pickup.name = "Gunk"
    pickup.desc = "A filthy little sewer slime who fights at your side - he hops in, bowls into enemies, and just will not die."
    pickup.weight = 100
    pickup.maxAmount = 1
    pickup.amountUses = -1
    pickup.price = 5
    pickup.tier = 1
    -- MUST be set, even empty. The base relic systems (relic_hunter.lua, ItemInterpreter.GetRandomPickup) iterate
    -- EVERY registered pickup and read spawnsIn -- a nil crashes relic rolling/display GAME-WIDE. Empty = valid AND
    -- in no loot pool (Gunk comes only from the swamp). The swamp detector drops him via the generic relic-pickup
    -- prefab (objects.ITEM_UPGRADE_ALL .. ":gunk"), NOT game.DropItem("gunk") -- a bare mod-relic id is not in the
    -- object-prefab mapping and throws "key not present in the dictionary".
    pickup.spawnsIn = {}
    pickup.supportedInMultiplayer = true
    pickup.globalTickDelay = 0.1
    LoadGunkConfig()
    GunkLog("onLoad")
end

function ADVR.onPickup()
    pickup.RegisterItem()
    -- Re-read the run save fresh: this may be the first callback of a resumed session (re-grab of the watcher's
    -- re-delivered relic), where the caches have never been initialized from the restored run save.
    RecruitedCache = nil
    FormCache = nil
    if IsRecruited() then
        -- Same-run re-grab (manual drop + re-grab, or the watcher's post-resume re-delivery): form lock and lore
        -- already happened THIS run. Run-scoped saves make a stale flag from another run impossible by
        -- construction, so this guard can no longer lock in a wrong form across sessions.
        GunkLog("pickup ignored, already recruited this run")
        return
    end
    pcall(function() player.StoreSavedRunBool("gunk_recruited_run", true) end)
    RecruitedCache = true
    -- Lock the STORY form at recruit time (pure function of NG+ level). The player's Spitter Form setting
    -- overlays this live in IsSpitter() -- refresh the config now so the lore below matches what they will see.
    LoadGunkConfig()
    local ng = 0
    pcall(function() ng = player.newGamePlusLevel end)
    local spitter = ng >= 2
    pcall(function() player.StoreSavedRunInt("gunk_form_run", spitter and 1 or 0) end)
    FormCache = spitter and 1 or 0
    -- Effective form for the recruit lore = story lock + setting overlay.
    spitter = IsSpitter()
    TickCount = 0
    NextSpawnTick = 0
    NextBiteTick = 0
    NextSpitTick = 0
    pcall(function() PlayerNetObj = player.networkObject end)
    if spitter then
        local seen = false
        pcall(function() seen = game.LoadBool("gunk_seen_corruption", false) end)
        if not seen then
            -- Long two-sentence lore -- needs the long display like the melee rescue's 8s (the 4s default was
            -- unreadable in VR).
            GunkSpeak("The sewers remember Gunk. The old filth seeps back into him - and there is a mouthful of acid where your harmless slime used to be.", 8)
            pcall(function() game.SaveBool("gunk_seen_corruption", true) end)
        else
            GunkSpeak("Gunk joins you - corrupted, and spitting acid.", 5)
        end
    else
        -- The rescue STORY unfolds HERE, on pickup -- so it plays when the player chooses to grab the relic
        -- (at their own pace, when safe), not thrust on-screen as they cross into the room mid-combat. The swamp
        -- detector only drops a short "something dropped" teaser.
        local seenRescue = false
        pcall(function() seenRescue = game.LoadBool("gunk_seen_rescue", false) end)
        if not seenRescue then
            GunkSpeak("Something small blinks up at you from the muck. Everything else down here wants you dead - but this one just bounces after you, leaving little acid footprints. You call him Gunk.", 8)
            pcall(function() game.SaveBool("gunk_seen_rescue", true) end)
        else
            GunkSpeak("Gunk joins you!")
        end
    end
    GunkLog("recruited ng=" .. tostring(ng) .. " spitter=" .. tostring(spitter))
end

function ADVR.onPickupProxies(originalPlayerRef)
    pickup.RegisterItemNoSync()
end

-- Mandatory cleanup on room change (design requirement): puddles must never leak across rooms.
function ADVR.onRoomEntered(room)
    ClearPuddles()
end

function ADVR.onGlobalTick()
    TickCount = TickCount + 1
    if not IsRecruited() then
        if Body ~= nil then
            DeleteGunk()
        end
        return
    end
    if Body == nil then
        if TickCount >= NextSpawnTick then
            SpawnGunk("tick-heal")
        end
        return
    end
    if BodyEnemy == nil then
        TameBody()
    end
    -- Live settings: reload the player's config + re-apply movement tuning every ~2s, so slider changes in the
    -- in-game settings panel take effect in-headset without a redeploy or floor change.
    if TickCount % CFG_REFRESH_TICKS == 0 then
        LoadGunkConfig()
        ReapplyAITuning()
        -- Live body corruption: if the effective form no longer matches the body he was spawned with (NG++
        -- corruption at recruit, or the Spitter Form setting flipped mid-run), respawn him in the right skin.
        if BodyIsSpitter ~= nil and BodyIsSpitter ~= IsSpitter() then
            SpawnGunk("form-change")
        end
    end
    Hunt()
    -- Land the projectile / expire puddles REGARDLESS of current form: on a live spitter->melee switch the
    -- leftovers must still land and age out (both are no-ops when nothing is tracked).
    TickSpit()
    TickPuddles()
    LeashBody()
end

function ADVR.onDungeonGenerated(worldGenerator)
    -- Respawn his body on a fresh floor if he is recruited but the body is gone (leash despawn / floor change).
    if IsRecruited() and Body == nil then
        SpawnGunk("onDungeonGenerated")
    end
end

function ADVR.onPostGameReload()
    if IsRecruited() and Body == nil then
        SpawnGunk("onPostGameReload")
    end
end

function ADVR.onPreGameReload()
    DeleteGunk()
end

-- KNOWN LIMITATION (no fix available): there is no documented ADVR callback for "item manually dropped from
-- inventory mid-run" (checked the full ADVR callback table -- onGlobalTick, the only thing that could poll for
-- this, itself only fires while the relic is HELD, so it can't detect its own loss). If the relic is dropped
-- mid-run, gunk_recruited_run stays true and Body/Puddles are only cleaned up at the next onSpawnInHomeBase/
-- onRunComplete. Revisit if the API ever exposes an onPickupDropped-style hook.

function ADVR.onSpawnInHomeBase()
    ResetGunkRun("homeBase")
end

function ADVR.onRunComplete()
    ResetGunkRun("runComplete")
end

function ADVR.onPlayerDeathOrRunComplete()
    ResetGunkRun("deathOrComplete")
end
