# Factory phase — open TODOs

Two issues found during a battle-loop playtest that live on the **factory** side. They were left for
the factory owner rather than fixed from the battle branch. Both are about returning to the factory
after winning a wave.

## 1. Build timer doesn't reset between waves

When a wave is won, `Factory._on_battle_resolved()` (`factory/Factory.gd:770-775`) advances
`current_wave` and autosaves, but never resets `build_time_left`. The 30-minute build timer
(`WAVE_BUILD_TIME`, `factory/Factory.gd:29`,`64`) just keeps counting from whatever was left when the
battle started (often `0:00`), so the next build phase starts with no time.

**Fix:** on a win, reset `build_time_left = WAVE_BUILD_TIME` (and likely `disarm_launch()`) **before**
`autosave()`, so the fresh timer is what gets persisted:

```gdscript
func _on_battle_resolved(won: bool, card_count: int) -> void:
    Run.clear_manifests()
    if won:
        current_wave = mini(current_wave + 1, Database.wave_count())
        build_time_left = WAVE_BUILD_TIME   # <-- reset the build clock for the next wave
        disarm_launch()                     # <-- drop back to unprimed
        autosave()
        hud.show_upgrade_picker(card_count)
    else:
        print("Defeated")
```

## 2. No wave number shown in the factory

`current_wave` advances internally, but nothing in the factory surfaces it — the top status bar
(`factory/Hud.gd:60-68` / `_build_top_bar`) only shows scrap, ingots, and the timer. The only place
"Wave N" appears is the battle overlay (`battle/Battle.gd`). During the playtest this read as "still
Wave 1" because there was no factory-side indicator at all.

**Fix:** add a small wave label to the top bar and update it each frame from `factory.current_wave`,
mirroring how `timer_label` is handled (`factory/Hud.gd:40` updates `timer_label.text` in
`_process`). e.g. build a `wave_label` in `_build_top_bar()` and set
`wave_label.text = "Wave %d" % factory.current_wave` in `Hud._process()`.

---

*Context:* the battle-side fixes from the same playtest (enemy portals across randomized rows, the
swarm-hop cell-overlap fix, and the "Tech Tree fully upgraded!" perk card) are already done on the
`feature/battle-sim` branch. See `design/battle-contract.md` for the phase boundary.
