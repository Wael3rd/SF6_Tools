# SF6 Record Slot File Format — Versioned Specification (v1.0.0, FROZEN)

> Companion to `COMBO_JSON_SPEC.md`. Defines a portable format for **training
> dummy record slots** (the game's built-in recording buffers used for oki
> setups, punish drills, reversal timing, etc.) so slot files created in
> SF6_Tools (RSM) or SF6_TOOLS_CC replay in either, and can be shared via the
> community platform.
> Status: **FROZEN v1.0.0 (2026-07-23)** — agreed by both maintainers.
> §6 resolutions: single-character files; kept as a sibling doc. The shared
> `timeline` token-grammar appendix is tracked on the shared board (additive,
> does not block the freeze). Changes follow the same board process as the
> combo spec.

## 1. Why a separate format

Combos (`xt.combo_trial`) are *player* input sequences validated step by step.
Record slots are *dummy* behavior buffers (up to 8 per character, uint16 input
per frame, 3600-frame cap) applied to the training opponent. Different lifecycle,
different consumer — but the same versioning discipline applies.

## 2. File shape

A slot file is a JSON object describing one character's 8 slots:

```json
{
    "_meta": {
        "schema": 1,
        "title": "", "author": "", "note": "", "tags": [],
        "language": "en",
        "fighter_id": 1,
        "created_at": "2026-07-16T12:00:00+02:00",
        "updated_at": "2026-07-16T12:00:00+02:00",
        "versions": {
            "game":     { "id": "sf6", "version": "1.14.2" },
            "recorder": { "id": "wtt", "version": "2.9.0" },
            "json":     { "version": "1.0.0" }
        }
    },
    "slots": [
        { "id": 1, "empty": false, "weight": 0, "name": "Meaty 2MK",
          "timeline": ["5f : 2", "4f : 5", "3f : 2MK"] },
        { "id": 2, "empty": true, "timeline": [] }
    ]
}
```

## 3. Slot fields

| Field | Type | Meaning |
|---|---|---|
| `id` | int (1–8) | Slot index |
| `empty` | bool | No recording in this slot |
| `weight` | int | In-game randomization weight for this slot |
| `name` | string? | User label |
| `timeline` | string[] | Run-length compressed input: `"<frames>f : <numpad+buttons>"` |
| `inputs` | uint16[]? | Optional raw per-frame masks (alternative to `timeline`, native fidelity) |

- `timeline` is the portable, human-readable form (numpad direction + button
  tokens), already produced by RSM's `export_json_compressed`.
- `inputs` (optional) mirrors the combo spec's `raw_inputs`: raw uint16 per
  frame for exact reproduction; when present it takes precedence.

## 4. Compatibility rules (shared with combo spec)

1. Readers MUST ignore unknown fields.
2. Writers MUST allocate slot memory before applying inputs that exceed the
   current buffer capacity (RSM handles this automatically).
3. A slot file targets ONE `fighter_id`; readers SHOULD warn on mismatch.
4. Backups: importers MUST snapshot the live slots before writing (RSM writes
   `<char>/Backups/<char>_pre_import_<ts>.json`) so an import is always
   reversible.
5. `game.version` lets tools warn when a slot was recorded on a different patch
   (act ids / timing can drift).

## 5. Relationship to the combo format

| | `xt.combo_trial` | `xt.record_slot` |
|---|---|---|
| Subject | Player input (validated) | Dummy behavior (applied) |
| Count per file | 1 combo (N steps) | 8 slots |
| Playback | trial validation / raw DEMO | native record-slot playback |
| Shared meta | `_xt_meta`, versions, language, ISO 8601 | same |

Both formats share the `_xt_meta` versioning carrier and compatibility rules,
so a community platform (SF6CM) can index, filter and sync them uniformly.

## 6. Open questions for review

- Single-character files (8 slots) vs multi-character bundles — proposal:
  single-character, matching RSM's per-character folders.
- Standardize `timeline` token grammar (numpad + button names) as a shared
  appendix so both projects parse identically.
- Whether to fold this into the combo spec repo/PR or keep a sibling doc.
