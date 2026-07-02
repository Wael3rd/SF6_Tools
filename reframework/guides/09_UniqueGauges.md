# SF6 Unique Gauge System — Research & Integration Notes

> How Street Fighter 6 stores and applies per-character "unique" resources (Jamie drinks,
> Blanka-chan bombs, Juri Fuha stocks, etc.), and how Custom Combo Trials records and
> replays them.

## TL;DR

| Need | Answer |
|---|---|
| Read the CURRENT level (live) | `cPlayer.mStyleNo` (0 = none, N = current stock/level) |
| Previous level | `cPlayer.style_old` (65535 = never changed this round) |
| Apply a level programmatically | Set `TrainingManager._tData.ParameterSetting.UniqueData.stock_0_XXX = N`, then `TrainingManager:call("set_IsReqRefresh", true)` |
| Damage modifier (Jamie) | `style_hosei_atk = 90 + 5 × drinks` |

## The fields (nBattle.cPlayer)

| Field | Meaning |
|---|---|
| `mStyleNo` | **Current** style level — the source of truth. Jamie: 0–4 drinks. |
| `mReqStyle` | Requested style level (consumed by the engine). |
| `style_old` | **Previous** level, not the current one. `65535` means "never had a style this round". |
| `style_hosei_atk` | Attack modifier %. Jamie: `90 + 5 × drinks` (90 sober → 110 at 4 drinks). |
| `comb_id` | Active command-table id. Changes with style level (Jamie: 2 → 4 → 5) but only syncs on the next act/round init — do not write it manually. |
| `style_timer` | Timer for install-type styles (Feng Shui Engine, Devil's Song…). |

## The methods (nBattle.cPlayer)

| Method | Semantics |
|---|---|
| `pl_style_change(delta, 1)` | **Relative** change. The natural drink action calls `pl_style_change(1, 1)`. |
| `pl_style_change(level, 0)` | **Absolute** re-assert. The game itself calls this periodically to refresh modifiers. Called alone from script it only updates modifiers/visuals — not the counter UI or command table. |
| `pl_style_set(level)` | Writes the level field only. No side effects. |
| `pl_style_update()` | Frame update tick, no arguments. Not a refresh trigger. |

**Important:** none of these, called in isolation, reproduce the complete natural drink
(counter UI + command table + visuals + modifiers). The complete state only assembles
when the engine itself applies the style — which happens on a **training refresh**.

## The reliable apply path (what Combo Trials uses)

```lua
-- 1. Set the training menu unique stock for the character
local tm = sdk.get_managed_singleton("app.training.TrainingManager")
local ud = tm:get_field("_tData"):get_field("ParameterSetting"):get_field("UniqueData")
ud:set_field("stock_0_021", 2)          -- Jamie = char id 21, field = stock_0_%03d
-- 2. Trigger the native refresh
tm:call("set_IsReqRefresh", true)
```

The refresh applies everything natively: `mStyleNo`, `comb_id`, drink counter UI, hair,
unlocked moves. It also re-applies every other menu setting (HP/gauges/positions), which
Combo Trials already compensates for with its own gauge/vital injection.

`UniqueData` field names per character (`stock_0_%03d` / `timer_0_%03d` with the ESF
character id): Ryu `timer_0_001`, Kimberly `stock_0_003`, Manon `stock_0_005`, Lily
`stock_0_012`, Blanka `timer/stock_0_015`, Juri `timer/stock_0_016`, Guile `timer_0_018`,
E.Honda `stock_0_020`, Jamie `timer/stock_0_021`, Mai `stock_0_028`, C.Viper
`timer_0_030`, Ingrid `stock_0_032`.

## Combo Trials integration (TrainingComboTrials_v1.0.lua)

The implementation uses the `unique_resources` module shared with
[SF6_TOOLS_CC](https://github.com/cdjay/SF6_TOOLS_CC) so combo files are interchangeable
between the two projects:

- **Registry** — `unique_resources.by_fighter_id`: per-character resource list
  (`id`, `kind` stock/timer, `min`/`max`, `allow_infinite`/`reject_infinite`, optional
  ParamFunc `setter` such as Mai's `SetUnique028_stock_0`).
- **Recording** — `unique_resources.capture_scene_state()` snapshots both sides' unique
  values at recording start and saves them in the combo JSON as:
  ```json
  "scene_state": {
    "schema": "xt.combo_trial.scene.v1",
    "capture_mode": "portable",
    "recorded_by": 0,
    "players": { "p1": { "fighter_id": 21, "unique": { "stock_0_021": 2 } } }
  }
  ```
  Local extension: for stock resources the capture also reads the live
  `cPlayer.mStyleNo` and keeps the higher value — so resources gained **in-game**
  (drinking with 22P) are recorded even though the training menu still says 0.
- **Trial start** — `unique_resources.apply_recorded()` collects entries from
  `scene_state` (plus legacy `meta.environment` layouts and a bridge for the
  transitional `combo_stats.style_stock` format), backs up the current menu values
  (`save_current()`), writes the recorded values, and requests a training refresh.
- **Trial end** — `unique_resources.restore()` writes the backed-up menu values back
  and refreshes.

Combos recorded without an active unique resource carry no `scene_state` key and
behave exactly as before (zero overhead, fully backward compatible).

## Current status & testing

| Character | Type | Status |
|---|---|---|
| **Jamie** (Drink Level) | stock | ✅ **Tested — works 100%** (record, replay, restore) |
| Kimberly, Manon, Lily, E.Honda, Mai, Ingrid, Blanka/Juri stocks | stock | ⚠ Untested — same code path as Jamie, should work but needs in-game verification |
| Ryu (Denjin), Guile, C.Viper, Blanka/Juri/Jamie timers | timer | ⚠ Menu value is captured/applied, but a timer activated **in-game** is not detected and the remaining install time is not restored — untested |

### How to contribute

1. **Verify a stock character**: gain the resource in-game (not via the menu), record a
   combo, then open the JSON in `data/TrainingComboTrials_data/CustomCombos/<char>/` and
   check `scene_state.players.<side>.unique.stock_0_XXX` matches what you had. Launch
   the trial and verify the counter/moves/visuals apply; exit the trial and verify the
   training menu value is restored. If a character's `mStyleNo` does not map 1:1 to its
   menu stock value, adjust the live-overlay block in
   `unique_resources.capture_for_fighter()`.
2. **The integration points** in `TrainingComboTrials_v1.0.lua` (`unique_resources`
   module):
   - `capture_scene_state()` — called at recording start, saved as `scene_state`
   - `apply_recorded()` — called from `start_trial()`, backs up + writes menu values +
     refresh
   - `restore()` — called on trial exit paths, restores the backup + refresh
3. **Adding timer-type support** (Denjin Charge, Feng Shui Engine, Solid Puncher…):
   the registry already declares `timer_0_XXX` resources (0 = Standard,
   1 = Activated/Maximum, 2 = Infinite) and they are captured/applied as menu values —
   but a timer activated **in-game** is not detected yet (needs a `style_timer`-based
   live overlay, like the `mStyleNo` one for stocks), and the remaining install time is
   not restored. The refresh path is the same as for stocks.

## Verified caveats

- The in-game drink **counter UI** does not follow programmatic `pl_style_change` calls —
  only the menu + refresh path updates it.
- `comb_id` (unlocked moves) also requires the refresh; it does not sync from
  `mStyleNo` writes alone in a static training state.
- A training refresh **resets programmatic style state** to whatever the menu says —
  which is exactly why writing the menu first is the only stable approach.
- Timer-type installs (Denjin Charge, Feng Shui Engine…) use `timer_0_XXX` + 
  `style_timer` and are **not** recorded yet — only stock-type styles are.
- Scripts placed in **subfolders of `autorun/`** are not re-run by Reset Scripts:
  test probes must live at the top level of `autorun/`.
