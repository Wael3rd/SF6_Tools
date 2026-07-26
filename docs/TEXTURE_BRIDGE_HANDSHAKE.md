# `texture.get_info()` — Bridge ABI / Capability Handshake (DRAFT v1, for SF6CC review)

> Companion to the pure-ImGui texture bridge (`reframework-imgui-texture`).
> Goal: make PNG support **safely portable** between runtimes. Symbol presence
> alone cannot guarantee compatible cimgui structure layouts (SF6CC's own
> finding), so the Lua side needs a positive, versioned handshake before it
> ever calls `texture.load` / `texture.draw`.
> Status: **draft by WTT — SF6CC corrects/approves** (board card tracks it).

## 1. The contract

The native plugin, when (and only when) its initialization fully succeeded,
registers the global `texture` table containing at least:

```lua
texture.get_info() -> {
    bridge_abi   = 1,                 -- int: version of THIS Lua-visible contract
    ref_commit   = "a0e9010f",        -- REFramework commit the plugin was BUILT against
    cimgui_ver   = "1.92.0",          -- cimgui version of that build (informational)
    capabilities = { "png_load", "png_draw", "atlas_pack" },
    status       = "ready",           -- "ready" | "degraded" | "failed"
}
```

- `bridge_abi` (int): bumped on ANY breaking change to the Lua-visible surface
  (function signatures, return conventions, error strings used as sentinels).
- `ref_commit` (string): the exact runtime the binary was compiled against —
  the same identifier the tray's atomic runtime profile pins.
- `capabilities` (string[]): feature gates. Consumers ignore unknown strings
  (same rule as JSON: unknown = future, not error).
- `status`: `"degraded"` lets the plugin declare partial service (e.g. atlas
  pressure) without lying with `"ready"` or dying with `"failed"`.

## 2. Consumer rules (Lua side)

1. `texture == nil` → no plugin (not installed, or its init failed cleanly).
   Geometry/text canvas continues; PNG features off. **No log spam** — one
   rate-limited line maximum.
2. `texture ~= nil` but `texture.get_info == nil` → **pre-handshake build**:
   treat as no PNG support. (This is what makes the handshake safe to
   introduce: old plugins are automatically quarantined.)
3. `get_info().bridge_abi ~= <the version this script was written for>` →
   PNG off, one log line. Never "try anyway".
4. `ref_commit` SHOULD be compared against the running dinput8 build id when
   the runtime exposes it (the atomic runtime profile manifest carries both);
   mismatch → PNG off. The handshake is the seatbelt; the profile is the
   guarantee.
5. Each feature is used only if its capability string is present.
6. `texture.load(path)` → `handle | nil, err`; `texture.draw(handle, x, y, w, h)`
   → `drawn:boolean, err?`. All failures are rate-limited by BOTH sides
   (native logs once per resource; Lua logs once per key).

## 3. Distribution rule (ties into the shared tray)

A release ships as one **atomic runtime profile**: `{ dinput8.dll @ commit X,
reframework-imgui-texture.dll built against X, scripts }` — verified together.
The handshake exists for every other situation: users mixing versions by hand,
partial updates, third-party builds. Expected outcome in ALL mismatch cases:
**icons downgrade, nothing crashes, one log line.**

## 4. Open questions for SF6CC

1. Can the plugin read the *running* REFramework commit at init (to
   self-compare and refuse registration on mismatch), or is that only known
   at build time? If self-refusal is possible, rule 4 becomes mostly moot.
2. Is `"degraded"` worth having, or is the atlas-wait state (the current
   Chinese sentinel string in `draw`) enough? If we keep the sentinel, it
   should become an error CODE in the next `bridge_abi` bump so non-Chinese
   consumers don't match on prose.
3. Version the capability names themselves (e.g. `png_draw@1`) or rely on
   `bridge_abi` alone? WTT's preference: `bridge_abi` alone, keep names plain.
