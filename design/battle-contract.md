# Factory ↔ Battle contract

The boundary between Phase 1 (factory) and Phase 2 (battle). The factory loads robots into
portal manifests and reads back a `BattleResult`; the battle reads the manifests + enemy waves and
hands the result back. All globals are autoloads — no imports/preloads needed.

## Factory → Battle: the player's army

```gdscript
Run.PORTAL_COLORS       # Array[StringName]: [blue, green, red, orange, yellow] (order)
Run.manifest(color)     # -> Array[RobotLoadout]   robots loaded into that portal
Run.portal_manifests    # Dictionary: color -> Array[RobotLoadout]   (the whole set)
Run.all_robots()        # -> Array[RobotLoadout]   combined across all portals
Run.total_robots()      # -> int

Unlocks.is_unlocked("portal_blue")   # -> bool   which portals are active
```

- Each portal's manifest is a separate array, keyed by color. The player places matching-color pads
  pre-battle (battle-side UI); `manifest(color)` → the pad for that color → spawn there.
- A locked portal can't be loaded, so its manifest is just empty — safe to skip when iterating.
- **Manifests stay loaded through the whole battle.** The factory clears them after rewards are
  tallied; the battle must **not** clear them.

## Enemy waves

```gdscript
Database.wave_count()   # -> int
Database.wave(n)        # -> WaveDef   (1-indexed, 1..wave_count(); null past the end)
WaveDef.loadouts()      # -> Array[RobotLoadout]   enemies expanded, ready to spawn
WaveDef.total_count()   # -> int   (for the "5 left -> next wave" trigger)
WaveDef.intel           # -> String   briefing hint
```

## RobotLoadout (player robots and enemies share this type)

```gdscript
loadout.legs / .torso / .head / .arms   # ItemDef each
loadout.total_armor()    # -> int
loadout.move_speed()     # -> float
loadout.turn_rate()      # -> float
loadout.damage()         # -> int
loadout.attack_range()   # -> float
loadout.attack_speed()   # -> float
loadout.power()          # -> float    combat-strength estimate
loadout.signature()      # -> String   identical builds share one (group/dedupe)
```

## Battle → Factory: the result

```gdscript
var result := BattleResult.new()
result.won       = <bool>
result.sent      = Run.all_robots()        # combined army that went in
result.survivors = <Array[RobotLoadout]>   # player robots still alive
result.enemies   = <Array[RobotLoadout]>   # the wave(s) faced
GameManager.on_battle_done(result)         # the factory takes it from here

# BattleResult also exposes: sent_power(), survivor_power(), enemy_power()
```

Use `Run.all_robots()` for `sent` (not a single manifest) so the combined power is right.

## Integration hook

Implemented. `Factory.start_battle()` opens `battle/Battle.tscn` as a full-screen overlay on the HUD
layer and pauses the factory; the overlay reads the manifests + current wave, runs the fight, and emits
`finished(result)`, at which point the factory frees it and calls `GameManager.on_battle_done(result)`.
A win advances `current_wave` and autosaves. The contract above is untouched.

## Battle phase (`battle/`)

A tick-based lane auto-battler timed to the music (à la UFO 50's *Attactics*). It speaks the factory's
grid: a row × column board drawn at `Factory.CELL_SIZE`.

- **Beat clock** — every step is a half-beat (tempo baked from `assets/Lucky-Factory.mp3`, ≈112 BPM).
  Units move on the beat and fire on the off-beat; `Sim.speed` scales the tempo.
- **Deploy** — a hotbar of the five portal colors; place each onto a row, then Fight. Each portal emits
  its manifest one mech at a time onto its row.
- **Classes / counters** — mechs march straight down their row, then swarm cleared rows. The three
  classes form a rock-paper-scissors triangle: **Brawler ▸ Rifleman ▸ Spearman ▸ Brawler**. The
  brawler's `shield` (an `ItemDef` stat, on the boxer torso) soaks ranged fire so it walks through
  rifles; spears are melee and punch through it.
- **End** — a wave is won when every enemy portal and unit is destroyed, lost when the player's mechs
  are gone with nothing left to spawn.

Files: `BattleSim` (headless, deterministic tick logic), `BattleUnit` / `BattlePortal` (runtime state),
`BattleRenderer` (placeholder drawing), `Battle` (overlay: deploy UI, beat clock, result). Dev tools:
`battle/Sandbox.tscn` drops you into a battle with a ready-made army; `battle/_test_sim.tscn` is a
headless check that the RPS triangle holds.
