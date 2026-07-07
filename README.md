# Gunk: the sewer slime that follows you home

> Everything in the Noxious Sewers wants you dead. **Gunk** just wants to come along.

A fan-made companion mod for [Ancient Dungeon VR](https://store.steampowered.com/app/1125400/Ancient_Dungeon_VR/)
(by ErThu), built on the game's official Lua modding API. Not affiliated with or endorsed by ErThu.

---

## Who is Gunk?

Gunk is the runt of the Noxious Sewers: too small to threaten anyone, too filthy to be worth the boot. Find him
on a New Game Plus run and he imprints on the first delver who doesn't squish him. Take his relic and he's yours
for the run: bouncing at your heel, hurling his whole tiny body at anything hostile, and hitting harder as *you*
hit harder (his damage is carved off your own).

But the deeper you go, the more his homeland wants him back. At **NG++** the sewers reclaim him. Permanently,
and visibly. His skin darkens into the sewers' own festering rot, and the harmless headbutt becomes a mouthful of
acid: slow, fat globs lobbed in a lazy arc that burn where they land and keep burning after. Same little slime.
Much worse manners. *(Prefer him one way or the other? The "Spitter Form" setting can force or forbid the
corruption.)*

## Features

- **A real companion, not a turret.** He hops around like any slime, pounces on nearby enemies, body-slams
  them, and bounces back to your side like nothing happened.
- **Scales with you.** His hits draw on your live primary + secondary damage. Upgrade yourself and you've
  upgraded him.
- **Unkillable.** The dungeon has tried. Nothing puts Gunk down, so the chaos of a deep run never costs you
  your buddy.
- **Earned, not handed out.** He only appears at New Game Plus, a reward for going back down.
- **A story with a cost.** At NG++ his home corrupts him into the Spitter, for good. He announces the change
  himself, both ways.
- **An honest artillery slime.** Spitter globs are real projectiles on a smooth arc. Damage lands where the
  glob lands: dodgeable, splashy, and every impact leaves an acid puddle. He even winds up before each lob and
  settles after, like he means it.
- **Tune him in the headset.** Damage, movement, spit behavior, unlock rules: every knob is a row of one-tap
  presets under **Settings → Mods → Gunk**, applying live within seconds. Works on Quest and PCVR, no file
  editing.
- **Survives everything, including you quitting.** Leave mid-run and continue later, and his relic re-drops at
  your feet when the save loads, whatever floor you're on.

## Mod settings

Open **Settings → Mods → Gunk** in-game. Every setting is a row of notched presets. The selected option is
always visible, the panel re-opens on whatever you chose, and changes apply live (within ~2 s):

| Setting | Options | Default | What it does |
| --- | --- | --- | --- |
| Damage | 20 / 40 / 80 / 150 % | 40 % | Gunk's hit = (your Primary + Secondary damage) × this |
| Hop Height | 100 / 130 / 180 / 250 % | 130 % | Base hop height |
| Attack Hop | 100 / 130 / 180 / 250 % | 130 % | Extra pounce height while hunting an enemy (100 % = none) |
| Move Speed | 80 / 106 / 130 / 160 % | 106 % | Hop movement speed |
| Hunt Range | 4 / 6 / 8 / 10 m | 6 m | He redirects onto hostiles within this radius |
| Leash | 8 / 12 / 16 / 20 m | 12 m | Past this from you he despawns and respawns at your side |
| Spit Cooldown | 2 / 3.6 / 5 / 8 s | 3.6 s | Time between spits in Spitter form |
| Spit Speed | 3 / 5 / 8 / 12 m/s | 5 m/s | Glob flight speed (lower = slower, lazier lobs) |
| Spit Range | 5 / 8 / 10 / 12 m | 8 m | He spits at visible hostiles within this radius |
| Spit Splash | 0.8 / 1.2 / 1.6 / 2.0 m | 1.2 m | Impact damage radius where the glob actually lands |
| Appears At | NG+ / Any Run | NG+ | Require New Game Plus (the intended unlock), or let Gunk appear on regular runs too |
| Spitter Form | At NG++ / Always / Never | At NG++ | The story rule (corrupted at NG++), force the acid-spitter everywhere, or keep him melee forever. Switches live, even mid-run |
| Teaser Delay | 1 / 2 / 3 / 5 s | 2 s | How long after the relic drops the teaser text appears |

The leash always stays at least 2 m longer than the hunt range. Otherwise he could chase prey straight out of
his own leash and despawn mid-pounce, which is embarrassing for everyone.

## How to get Gunk

1. Reach **New Game Plus**. *(Or set "Appears At" to **Any Run** and skip the grind.)*
2. Descend into the **Noxious Sewers**. Something small tumbles into the muck nearby.
3. **Pick up the relic** to recruit him for the rest of the run. Leave it, and he waits in the muck. He's used
   to waiting.
4. Reach **NG++** and the sewers take him back: corrupted, and spitting.

## Install

Download the latest `Gunk.zip` from the Releases page (or Nexus Mods, rename it if needed) and **keep it zipped**: the game reads
the zip directly.

### PCVR (Steam / Rift)

1. First, enable mods to set up the proper folder structure. Launch the game in VR, and in the settings menu on the right, you’ll see a box that enables mods when clicked. Then you can exit the game.
2. Drop **Gunk.zip** into `%USERPROFILE%\AppData\LocalLow\ErThu\Ancient_Dungeon\ADVR_Mods\` *(paste that straight into the File Explorer address bar - AppData is a hidden folder)*.
3. Launch the game in VR and enable the mod in the in-game **mods menu**.

### Quest (standalone headset)

1. **In the headset:** start Ancient Dungeon, open **Settings**, and press the **enable modding** button. Grant
   the **Read External Storage** permission when the prompt appears. The game reloads, and you can close it
   after.
2. Connect the Quest to a computer with a USB cable and **allow file access** (approve the prompt inside the
   headset). Browse the Quest's storage with Windows Explorer, SideQuest, or Android File Transfer on Mac.
3. Navigate to `/sdcard/Android/data/de.erthu.ancientdungeonfull/files/ADVR_Mods/`.
4. Copy `Gunk.zip` into that folder, unplug, launch the game, and enable the mod in the in-game **mods menu**.

**Mod version:** 1.0.0 (see [CHANGELOG.md](CHANGELOG.md)) · **Game version:** built and tested against `ea0.1.10.1`.

## Known interactions

- **A Walk in the Park** (Acolyte upgrade): the game's own "no enemies within 13 m" check counts Gunk as a
  nearby enemy, which would silently disable the perk's speed boost for as long as he's with you. The mod
  compensates: when Gunk is the only "enemy" in the perk's radius, it applies the same boost itself — same
  +20 % cap, same ramp speed — and drops it the moment a real hostile closes in. You keep the perk you paid
  for. *(In co-op, the compensation follows whoever carries the relic.)*
- Gunk's hits are attributed to the player's secondary damage (the same mechanism vanilla relics like Vicious
  Barb use), so on-hit effects can trigger from his attacks.
- Multiplayer: the relic and companion are untested in co-op. `supportedInMultiplayer` is set, and the design is
  co-op-aware, but treat it as experimental.

## For developers

The mod is plain Lua + a manifest. To build and deploy locally (Windows, PowerShell):

```powershell
./deploy.ps1
```

This zips the `Gunk/` folder and copies `Gunk.zip` into your `ADVR_Mods` folder. The script refuses to build if any
`.lua` contains a semicolon (the ADVR linter rejects them). Source layout:

```
Gunk/
  mod.modinfo                              # mod manifest
  settings.lua                             # in-game settings panel (Settings -> Mods -> Gunk)
  items/gunk/gunk.lua                      # the companion relic (all per-tick logic)
  progress_shops/acolyte/gunk_watcher.lua  # the swamp detector: drops the relic on fresh AND resumed runs
```

Why a progress-shop script for the detector: it is the only always-on mod content type whose `onGlobalTick` fires
on *resumed* (continued) runs. Achievements only receive world callbacks on runs started fresh from the home
base. It registers as a small "Gunk's Watcher" node in the Acolyte's insight shop; it works identically whether
or not it is ever bought.

## License

Released under the [MIT License](LICENSE): free to use, fork, and learn from, as long as the copyright notice is
kept. *Ancient Dungeon VR* and its assets remain the property of ErThu.

## Credits

- **Ancient Dungeon VR** by ErThu, the game this mod extends.
- Mod by [RobThePCGuy](https://github.com/RobThePCGuy).
