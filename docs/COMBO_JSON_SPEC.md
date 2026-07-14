# SF6 Combo Trial File Format — Versioned Specification (DRAFT v2 proposal)

> Joint specification proposal for WTT/SF6_Tools and SF6_TOOLS_CC (+ SF6CM), so
> combo files recorded in either project replay in the other, permanently.
> Status: **draft for review** — nothing here is frozen.

## 1. Goals

1. A combo file recorded by any compliant tool replays in every compliant tool.
2. Old files never break: readers accept every schema version they know, and
   ignore fields they don't.
3. Ecosystem components (mods, sites, trays) can tell which versions produced a
   file and whether they can handle it — without parsing heuristics.

## 2. File shape (current, shared today)

A combo file is a JSON **array of steps**. Step 1 additionally carries the
file-level payloads:

```
[ step1 = { <step fields> + _xt_meta + scene_state? + raw_inputs? + combo_stats
            + start_pos_* + timeline? + recorded_by },
  step2 = { <step fields> },
  ... ]
```

### Step fields (all steps)

| Field | Type | Meaning |
|---|---|---|
| `id` | int | Action id of the expected move |
| `motion` | string | Display/matching notation ("5HP", "236+P", "> 214+P"…) |
| `motion_aliases` | string[]? | Extra notations accepted by the matcher |
| `expected_combo` | int | Combo counter expected after the previous step |
| `expected_hp` | int? | Victim HP expected (strict only in oki phases) |
| `delay_from_prev` | int | Frames between this step and the previous one |
| `counter_type` | int | 0 normal / 1 CH / 2 PC required on this step |
| `victim_pose` | int? | 0 stand / 1 crouch (live pose at recording) |
| `dummy_action_type`, `dummy_jump_type` | int? | Configured dummy behavior (v2) |
| `is_holdable`, `hold_frames`, `hold_partial_check` | — | Hold system |
| `dual_threshold`, `is_projectile_hit`, `group_id`, `facing_left` | — | Matching helpers |
| `validation_role` | string? | e.g. `"pressure_tail"` (CC) |
| `actual_combo`, `has_hit`, `damage_at_step` | — | Runtime; writers SHOULD reset, readers MUST ignore |

### File-level payloads (step 1)

| Field | Meaning |
|---|---|
| `_xt_meta` | Authoring metadata — see §3 |
| `scene_state` | Unique resources snapshot, schema `xt.combo_trial.scene.v1` (both sides, per-fighter `unique` map) |
| `raw_inputs` | uint16[] — raw per-frame input stream for native-fidelity DEMO playback (WTT) |
| `combo_stats` | `{ damage, drive_used, super_used }` (+ legacy `style_stock`/`style_char_id`, superseded by `scene_state`) |
| `start_pos_p1/p2` (+`_raw`) | Recorded positions |
| `recorded_by` | 0/1 — recording side (orients `scene_state.players`) |
| `timeline` | Legacy step-timeline DEMO data (superseded by `raw_inputs`) |

## 3. `_xt_meta` — the versioning carrier (v2 proposal)

```json
"_xt_meta": {
    "schema": 2,
    "title": "", "author": "", "note": "", "tags": [],
    "language": "en",                 // BCP-47: "en", "zh-CN", "fr"... (authoring language of title/note/tags)
    "control_mode": "classic",        // "classic" | "modern" — inputs are not portable across modes
    "created_at": "2026-07-13 18:00:00",
    "versions": {
        "game": "SF6 v1.14.2",
        "recorder": "wtt-2.9",        // or "sf6cc-0.9a"
        "json": "xt.combo_trial.v2"
    },
    "environment": { ... }            // dummy behavior etc. (CC layout)
}
```

- `schema` (int): **major** version of the step/file layout. Bump ONLY on
  breaking change (field renamed/retyped/removed).
- `versions.json` (string id): fully-qualified format id, mirrors `schema`.
- `versions.recorder`: producing tool + its version (`wtt-*`, `sf6cc-*`,
  `sf6cm-*`). Covers cdjay/#15 (tray/game/json/CM/CC traceability).
- `versions.game`: game build the combo was recorded on (act_ids can shift
  between game patches — lets tools warn instead of failing).
- `language` (BCP-47 tag): authoring language of the human-readable metadata.
  Lets sites/tools filter and lets UIs decide when to show original vs
  translated text. Notations ("236+HP") are language-neutral by design.
- `control_mode`: `"classic"` or `"modern"`. Recorded inputs and expected
  actions are NOT portable across control modes; players and tools must be
  able to filter on it. Absent = assume classic (legacy files).

## 3b. Explicit playback preconditions (principle)

Everything required to replay a combo MUST be explicitly declared in the file —
never inferred from titles, notes or filenames. The complete precondition set:

| Precondition | Where |
|---|---|
| Positions | `start_pos_p1/p2` (+`_raw`) |
| Dummy behavior (stance/jump config) | `dummy_action_type` + `dummy_jump_type` (step 1), `victim_pose` per step as live fallback |
| Unique resources (installs, stocks, drinks) | `scene_state.players.*.unique` |
| Gauges | `combo_stats.drive_used` / `super_used` (exact injection) + HP via `expected_hp` |
| Counter/punish requirements | `counter_type` per step |
| Control mode | `_xt_meta.control_mode` |
| Recording side | `recorded_by` |

A reader that honors this table needs zero heuristics before pressing play.

## 3c. Action id drift and `motion_aliases`

Real-world case (E.Honda Sumo Spirit, verified 2026-07-14): install states can
CHANGE the action ids of empowered normals (5HP under Sumo Spirit is a
different id than normal 5HP — and the install move itself shifts id too).
Matching MUST therefore accept id OR normalized notation, and files SHOULD be
able to declare equivalences explicitly:

```json
{ "id": 970, "motion": "5252+K", "motion_aliases": ["22+K"] }
```

- Matchers normalize notations (uppercase, strip whitespace and whiff markers)
  and accept `motion` or any alias.
- Per-character exception files map variant ids to the base notation
  (`force` + `override_name` = base move notation) so both states record and
  replay interchangeably.

## 4. Compatibility rules

1. **Readers MUST ignore unknown fields** (both file-level and step-level).
2. **Writers MUST NOT reuse a field name with different semantics** — new
   meaning = new name (+ schema bump if breaking).
3. Additive changes (new optional field) do NOT bump `schema`.
4. A reader seeing `schema` > its known max SHOULD still attempt playback with
   known fields, warning the user, unless the file declares
   `requires_strict: true` in `_xt_meta`.
5. Runtime fields (`actual_combo`, `has_hit`, …) are never meaningful on disk.
6. Sidecar runtime files (e.g. `CompletedTrials.json`) MUST live outside the
   per-character combo directories.

## 5. Known divergences to reconcile (open questions for review)

| Topic | WTT | CC | Proposal |
|---|---|---|---|
| DEMO playback data | `raw_inputs` (uint16/frame) | timeline-driven | Adopt `raw_inputs` as v2 canonical; keep `timeline` as legacy fallback |
| Unique resources capture | menu + live `mStyleNo` overlay | menu only | Overlay behavior recommended; format identical (`scene_state`) |
| Dummy behavior | `victim_pose` per step (live) | `meta.environment` (configured) | Keep both: `environment` = intent, `victim_pose` = fallback |
| Display strings in files | English notations | zh notations via display layer | Files store neutral notation; localization stays in UI layer |
| Completion tracking | — | `CompletedTrials.json` sidecar | Standardize sidecar name + key format |

## 6. Version history

| `schema` | Date | Changes |
|---|---|---|
| 1 | 2026-06 | `_xt_meta` introduced (author/title/tags/created_at) |
| 2 | draft | `versions` block, `language`, `control_mode`, `environment`, `raw_inputs`, `scene_state`, `motion_aliases`, explicit-preconditions principle, compat rules formalized |
