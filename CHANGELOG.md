# Changelog

All notable changes to the Gunk mod.

## [1.0.0] — 2026-07-03

Initial public release.

- **Gunk**, an invincible slime companion recruited via a relic drop in the Noxious Sewers at New Game Plus.
- Melee form: follows you, redirects his hop onto hostiles within hunt range, deals body-contact damage scaled
  from your Primary + Secondary damage.
- **NG++ Spitter form**: permanently corrupted at recruit time on NG++ — ranged acid spit whose impacts leave
  short-lived burning puddles (capped, auto-expiring).
- In-game settings panel (Settings → Mods → Gunk): damage, hop height, attack hop bonus, move speed, hunt range,
  leash distance, spit cooldown/speed/range/splash radius, and the relic-teaser delay — all live-tunable with
  VR-tuned defaults, cross-platform (Quest + PCVR). Every setting is a row of notched presets whose selection is
  always visible, and the panel re-opens at your saved choice.
- "Appears At" setting: **New Game Plus** (default) or **Any Run** — lets players without an NG+ save meet Gunk
  on a regular Noxious Sewers visit.
- "Spitter Form" setting: **At NG++** (default, the story rule), **Always**, or **Never** — overlays the
  recruit-time form live, switching him mid-run within ~2 seconds.
- The corruption is **visible**: Spitter Gunk keeps his small body but his skin darkens into a rotten murky
  brown — applied (and removed) live when the form changes, with a short story line announcing the
  transformation either way.
- Spits are **real projectiles**: the game's own green slime-spit glob (fully disarmed — colliders and bullet
  logic off, all damage comes from the scripted impact), at 1.5× size, flying a smooth physics-driven,
  script-steered arc with flight time scaling with distance (~5 m/s). Damage splashes from **where the glob
  actually lands** — a dodged glob honestly misses — and each impact leaves a lingering acid puddle (the
  movement trail was removed in its favor). Targeting is line-of-sight only — he won't waste spits on enemies
  behind walls.
- **Artillery stance**: while the Spitter has prey in range he calms down — slower, lower, less frequent hops —
  instead of bouncing like melee Gunk mid-attack, snapping back to his normal follow-bounce when the range
  clears. Each lob is bracketed by a **half-second windup and recovery** where his movement and hops drop
  another 50 % — he visibly gathers himself, spits, and settles.
- Melee audio: a war-cry chirp when he locks onto prey and a wet squish when a body-slam connects.
- The relic-drop teaser is delayed ~2 s (so the floor-name banner clears first) and stays up 7 s.
- Robust acquisition: the relic drops on fresh runs *and* resumed (continued) runs, and re-drops after a resume
  if the companion was lost with the reload — on any floor, not just the sewers.
- Run-scoped state: recruit/form/drop flags live in the game's per-run save (auto-reset each run, auto-restored
  on resume), so state can never leak between runs.
