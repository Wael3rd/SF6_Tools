# Fix — Sheldon's Boxes: recovery colour stuck when a direction is held

**Date:** 2026-08-04
**File:** `reframework/autorun/SheldonsBoxes.lua`
**Scope:** the state-coloured hurtboxes (idle / startup / active / recovery / hitstun).

This is written so it can be handed to another maintainer (e.g. the SF6CC
fork) whose Sheldon's-Boxes-style overlay colours hurtboxes by frame state and
shares the same recovery-exit logic.

---

## 1. Symptom

Hurtboxes are tinted by the character's current frame state:

| state | `clean` value | colour key |
|---|---|---|
| idle | 0 | `hurtbox` (green) |
| startup | 7 | `hurtbox_startup` |
| active | 13 / 14 | (active) |
| recovery | 8 | `hurtbox_recovery` (blue) |
| hitstun | 9 | `hurtbox_hitstun` |

Whiff a move standing still → boxes go **blue** during recovery, then back to
**green** (idle) the moment you recover. Correct.

**Bug:** if you **hold a direction** (or crouch) through the end of the move's
recovery, the boxes stay **blue** forever instead of returning to idle green.
Releasing to neutral does eventually clear it, which is the tell.

## 2. Root cause

Two facts combine:

1. **The frame meter can't report "idle".** The colour comes from
   `_sb_ft[idx].clean`, derived from the native training frame meter's history
   ring. The head-advance logic (`_sb_fm_check`) only moves onto **non-zero**
   cells and otherwise *parks on the last non-zero cell*. When recovery ends,
   the meter simply stops adding cells, so `head` stays on the last recovery
   cell and `clean` stays `8`. The meter history alone can never signal
   "recovery is over".

2. **The only exit was `act_st == 0`.** So the return to idle depended entirely
   on this line:

   ```lua
   if GS.p1_act_st == 0 then _sb_ft[0].clean = 0; _sb_ft[0].in_move = false; _sb_ft[0].in_hitstun = false end
   ```

   `act_st == 0` is **neutral standing idle only**. Holding a direction at the
   end of recovery puts the character straight into a **walk / crouch** action
   (`act_st ~= 0`), so the condition never fires and the recovery colour is
   never cleared.

Standing still works because the character passes through `act_st == 0`;
holding a direction skips it entirely.

## 3. Fix

A move's recovery (and hitstun) is a **single action state**. Capture that
`act_st` on the first held frame, and treat **any** change away from it —
walk, crouch, cancel, next move, or neutral — as "actionable → back to idle".
Neutral (`act_st == 0`) is still handled as an always-actionable shortcut, so
the original behaviour is preserved.

New per-player field: `hold_act_st` (added to the `_sb_ft` init tables).

New helper (defined before `_sb_update_frame_types`):

```lua
local function _sb_exit_if_actionable(st, act_st)
    if act_st == 0 then
        -- neutral idle is always actionable (preserves the original behaviour)
        st.clean = 0; st.in_move = false; st.in_hitstun = false; st.hold_act_st = nil
        return
    end
    -- Only the held recovery/hitstun states can get stuck; startup/active
    -- advance on their own via the meter and never read a movement act_st.
    if st.clean ~= 8 and st.clean ~= 9 then
        st.hold_act_st = nil
        return
    end
    if st.hold_act_st == nil then
        st.hold_act_st = act_st            -- first held frame: this is the move's state
    elseif act_st ~= st.hold_act_st then
        -- left the recovery/hitstun action (walking, crouching, cancelling...)
        st.clean = 0; st.in_move = false; st.in_hitstun = false; st.hold_act_st = nil
    end
end
```

The two `act_st == 0` lines at the end of `_sb_update_frame_types` become:

```lua
_sb_exit_if_actionable(_sb_ft[0], GS.p1_act_st)
_sb_exit_if_actionable(_sb_ft[1], GS.p2_act_st)
```

Why this is safe:

- **No hard-coded state values.** It never needs to know which `act_st` means
  "walk" or "crouch" — it only detects *change* away from the captured
  recovery/hitstun state, so it is character- and patch-agnostic.
- **Gated to `clean == 8/9`.** Startup (7) and active (13/14) advance through
  the meter and are never in a movement `act_st`, so they can't be affected.
- **`act_st == 0` path unchanged**, so the standing-still case behaves exactly
  as before.

## 4. Known edge cases (acceptable)

- A move whose recovery legitimately spans **two different action states**
  would clear one state early (boxes go green a few frames before the animation
  fully ends). This is rare, and an early return to idle is far less wrong than
  a colour stuck forever.
- Cancelling recovery straight into another move produces a 1-frame idle
  flash before the next move's startup (7) is picked up. Not noticeable in
  practice.

## 5. How to verify in-game

Sheldon's Boxes on, state colours on. Do a whiffed normal:

1. Recover **standing still** → blue during recovery, green after. (already OK)
2. Recover while **holding forward/back** → must now return to green instead of
   staying blue. **(the fix)**
3. Recover while **holding down (crouch)** → same, returns to idle.
4. Take a hit, then hold a direction as hitstun ends → hitstun colour clears.
