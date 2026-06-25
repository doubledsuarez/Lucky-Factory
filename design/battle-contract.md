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

`Factory.start_battle()` currently stubs an instant win so the loop is testable without a battle.
Replace that with the transition into the battle scene; the scene reads the manifests + waves above,
runs the fight, and calls `GameManager.on_battle_done()` at the end. Everything else stays as written.
