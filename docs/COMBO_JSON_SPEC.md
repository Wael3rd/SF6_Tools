# SF6 Combo Trial File Format — Versioned Specification (DRAFT v2, rev 2)

> Joint specification proposal for WTT/SF6_Tools and SF6_TOOLS_CC (+ SF6CM), so
> combo files recorded in either project replay in the other, permanently.
> Status: **draft under review** — rev 2 incorporates the first review pass.

## 1. Goals

1. A combo file recorded by any compliant tool replays in every compliant tool.
2. Old files never break: readers accept every schema version they know, and
   ignore fields they don't.
3. Ecosystem components (mods, sites, trays) can tell which versions produced a
   file and whether they can handle it — without parsing heuristics.

## 2. File shape

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
| `motion_aliases` | string[]? | Extra notations accepted by the matcher (§3d) |
| `expected_combo` | int | Combo counter expected after the previous step |
| `expected_hp` | int? | Victim HP expected at this step (validation, NOT the starting HP — see §3c) |
| `delay_from_prev` | int | Frames between this step and the previous one |
| `counter_type` | int | 0 normal / 1 CH / 2 PC required on this step |
| `victim_pose` | int? | 0 stand / 1 crouch (live pose at recording) |
| `dummy_action_type`, `dummy_jump_type` | int? | Configured dummy behavior (step 1) |
| `is_holdable`, `hold_frames`, `hold_partial_check` | — | Hold system |
| `dual_threshold`, `is_projectile_hit`, `group_id`, `facing_left` | — | Matching helpers |
| `validation_role` | string? | e.g. `"pressure_tail"` (CC) |
| `actual_combo`, `has_hit`, `damage_at_step` | — | Runtime; writers SHOULD reset, readers MUST ignore |

### File-level payloads (step 1)

| Field | Meaning |
|---|---|
| `_xt_meta` | Authoring metadata + versioning — see §3 |
| `scene_state` | Playback preconditions snapshot — see §3c |
| `raw_inputs` | uint16[] — raw per-frame input stream for native-fidelity DEMO playback. **Optional** (§5) |
| `combo_stats` | Result analytics ONLY: `{ damage, drive_used, super_used }` — consumption/outcome, never starting state (§3c) |
| `start_pos_p1/p2` (+`_raw`) | Recorded positions |
| `recorded_by` | 0/1 — recording side (orients `scene_state.players`) |
| `timeline` | Step-timeline DEMO data — supported playback source when `raw_inputs` is absent (§5) |

## 3. `_xt_meta` — authoring metadata and versioning carrier

```json
"_xt_meta": {
    "schema": 2,
    "title": "", "author": "", "note": "", "tags": [],
    "step_notes": ["", "Slight delay before 236MK", ""],
    "language": "en",
    "control_mode": "classic",
    "created_at": "2026-07-13T18:00:00+02:00",
    "updated_at": "2026-07-14T12:00:00+02:00",
    "versions": {
        "game":     { "id": "sf6", "version": "1.14.2" },
        "recorder": { "id": "wtt", "version": "2.9.0" },
        "json":     { "id": "xt.combo_trial", "version": "2.0.0" }
    },
    "environment": { ... }
}
```

- `schema` (int): **major** version of the step/file layout. Bump ONLY on
  breaking change (field renamed/retyped/removed).
- `versions.*`: structured `{ id, version }` objects. `game` covers act-id
  drift between patches; `recorder` identifies the producing tool
  (`wtt`, `sf6cc`, `sf6cm`); `json` is the format id.
  *Open question: neutral format id (`xt.combo_trial`) vs platform-branded
  (`SF6CM`) — proposal: neutral id, since the format is co-owned; platforms
  can add their own `distribution` entry if needed.*
- `step_notes` (string[]): per-step community annotations, **index-aligned
  with the step array** (empty string = no note). Kept in `_xt_meta` so the
  step objects stay engine-only.
- `language` (BCP-47): authoring language of title/note/tags/step_notes.
  Notations ("236+HP") are language-neutral by design.
- `control_mode`: `"classic"` or `"modern"`. Recorded inputs and expected
  actions are NOT portable across control modes; tools must be able to
  filter on it. Absent = assume classic (legacy files).
- `created_at` / `updated_at`: **ISO 8601 with timezone offset**. `updated_at`
  changes on any re-record, fix, note edit or game-version adaptation —
  community platforms rely on it for sync.

## 3b. Explicit playback preconditions (principle)

Everything required to replay a combo MUST be explicitly declared in the file —
never inferred from titles, notes or filenames. The complete precondition set:

| Precondition | Where |
|---|---|
| Positions | `start_pos_p1/p2` (+`_raw`) |
| Dummy behavior (stance/jump config) | `dummy_action_type` + `dummy_jump_type` (step 1), `victim_pose` per step as live fallback |
| Starting resources (HP/drive/super) | `scene_state.players.*.resources` (§3c) |
| Unique resources (installs, stocks, drinks) | `scene_state.players.*.unique` |
| Character status (stun, burnout, stance) | `scene_state.players.*.status` (§3c) |
| Counter/punish requirements | `counter_type` per step |
| Control mode | `_xt_meta.control_mode` |
| Recording side | `recorded_by` |

A reader that honors this table needs zero heuristics before pressing play.

## 3c. `scene_state` — playback preconditions snapshot (v2)

Starting state is NOT the same thing as consumption: `drive_used` is what the
combo spends; the drive value before playback is a precondition. The two live
in different places:

```json
"scene_state": {
    "schema": "xt.combo_trial.scene.v2",
    "recorded_by": 0,
    "players": {
        "p1": {
            "fighter_id": 21,
            "resources": { "hp": 10000, "drive": 60000, "super": 20000 },
            "status": { "burnout": false, "stunned": false, "stance": "standing" },
            "unique": { "stock_0_021": 2 }
        },
        "p2": { ... }
    }
}
```

- `resources`: exact starting values injected before playback.
- `status`: `burnout` (bool), `stunned`/piyo (bool), `stance`
  (`"standing" | "crouching" | "airborne"`).
- `unique`: per-fighter unique resource map (unchanged from scene.v1).
- `combo_stats` keeps ONLY result analytics: `{ damage, drive_used,
  super_used }`.
- scene.v1 files (unique only) remain valid; readers fall back to legacy
  behavior for missing blocks.

## 3d. Action id drift and `motion_aliases`

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
7. **`raw_inputs` is optional.** A file without it is fully v2-compliant;
   `timeline` remains a supported playback source (not deprecated). When both
   are present, `raw_inputs` takes precedence for DEMO fidelity.
8. **No batch conversion required.** Existing community JSONs (schema 1 /
   scene.v1) stay valid forever; tools upgrade files opportunistically when
   re-saving.
9. Raw input portability caveat: `raw_inputs` streams are only guaranteed
   meaningful for the same `control_mode` and may drift across `versions.game`
   — players SHOULD be warned when either differs, and `timeline` used as the
   fallback source.

## 5. Remaining open questions

| Topic | Status |
|---|---|
| Format id: neutral (`xt.combo_trial`) vs platform-branded (`SF6CM`) | Proposal: neutral (§3) — needs agreement |
| Unique-resource capture: menu vs live overlay (`mStyleNo`) | WTT captures live-gained resources too; recommended behavior, same format |
| Dummy behavior: `environment` (configured) + `victim_pose` (live fallback) | Both kept; precedence = configured first |
| Localization of display strings | Files store neutral notation; localization stays in the UI layer |
| Completion tracking sidecar name/key format | `CompletedTrials.json`, lowercased forward-slash path keys — confirm |

## 6. Version history

| `schema` | Date | Changes |
|---|---|---|
| 1 | 2026-06 | `_xt_meta` introduced (author/title/tags/created_at) |
| 2 rev 1 | 2026-07-13 | `versions` block, `language`, `control_mode`, `environment`, `raw_inputs`, `scene_state`, `motion_aliases`, explicit-preconditions principle, compat rules |
| 2 rev 2 | 2026-07-14 | Review pass 1: `resources`/`status` in scene_state (start state ≠ consumption), `step_notes`, ISO 8601 + `updated_at`, structured `versions` objects, raw_inputs optionality + timeline status + no-batch-conversion rules |
