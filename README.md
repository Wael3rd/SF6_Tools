# SF6 Training Tools (Wael3rd Edition)

Welcome to the **SF6 Training Tools** suite — a comprehensive collection of Lua scripts, visual overlays, analytics dashboards, and a mobile remote control app designed to enhance your training experience in Street Fighter 6.

Whether you want to practice hit confirms, drill reactions, learn custom combos, visualize distances and hitboxes, or control everything from your phone — this toolkit has you covered.

## 📦 Prerequisites

Before installing, ensure you have the following for Street Fighter 6:

1. **REFramework:** Already included in the release — just copy `dinput8.dll` into your SF6 folder (next to `StreetFighter6.exe`).
2. **REFramework D2D Plugin:** Required for all on-screen overlays. Also included in the release (`plugins/reframework-d2d.dll`) — no separate download needed.

## 📂 Installation Guide

Download the latest release from the [releases page](https://github.com/Wael3rd/SF6_Tools/releases) and extract the contents into your SF6 game folder. The `reframework/` folder structure merges automatically.

### 1. Script Installation

The following `.lua` scripts go into `Street Fighter 6\reframework\autorun\`:

**Training Suite (Script Manager + 4 modes):**
| Script | Description |
| :--- | :--- |
| `Training_ScriptManager.lua` | The Main Controller — central hub for all training modes |
| `TrainingComboTrials_v1.0.lua` | Custom Combo Trials with recording, playback, demo, and validation |
| `TrainingHitConfirm_v1.0.lua` | Hit Confirm reaction training with random guard |
| `TrainingReactions_v1.0.lua` | Reaction Drills against randomized dummy recordings |
| `TrainingPostGuard_v0.1.lua` | Post-Guard punish training after blocking |

**Analysis & Visualization Tools:**
| Script | Description |
| :--- | :--- |
| `SF6_DistanceViewer.lua` | Real-time attack range visualization with zones, crossup indicators, and jump arcs |
| `SF6_DistanceLogger.lua` | Records distance data during gameplay for offline analysis |
| `SheldonsBoxes.lua` | Hitbox/hurtbox display with ruler and charge visualization |

**Utilities:**
| Script | Description |
| :--- | :--- |
| `SF6_RecordingSlotManager.lua` | Advanced recording slot management (import/export/program) |
| `SF6_Teleport.lua` | Teleport players to specific positions for distance testing |
| `SF6_TrainingRemoteControlServerState.lua` | State bridge for the WIT Remote Control app |

**Shared Modules** (in `autorun/func/` — loaded automatically):
- `ComboTrials_UI.lua` — Combo Trials UI rendering
- `ComboTrials_D2D.lua` — Combo Trials overlay (input notation, step display)
- `Training_SessionRecap.lua` — End-of-session stats summary
- `Training_SharedUI.lua` — Shared UI utilities and color palette
- `SharedHooks.lua` — Shared REFramework hook setup

### 2. Font Installation

Copy the font files from `fonts/` into `Street Fighter 6\reframework\fonts\`:

- `SF6_college.ttf` / `sf6_college.otf`
- `capcom_goji-udkakugoc80pro-db.ttf`
- `capcom_goji-udkakugoc80pro-r.ttf`
- `frutigerltarabic-57cn.ttf`

> **Note:** If the `fonts` folder does not exist inside `reframework`, create it manually.

### 3. Dashboards & Editor

The `.html` files in `html viewers/` are standalone tools. Open them in any browser — no server needed.

| File | Description |
| :--- | :--- |
| `TrainingDashBoard.html` | Unified analytics dashboard — import session stats to view graphs, reaction times, and success rates |
| `SF6_Replay_Editor.html` | Visual editor to create/edit recording slot data. Export as JSON and import via Slot Manager |

---

## 🎮 How to Use

### The Training Script Manager

Once in-game, press **Insert** to open the REFramework menu. The **Training Script Manager** provides a floating top bar at the top of the screen for quick mode switching.

Select your active training mode:

| # | Mode | Description |
| :--- | :--- | :--- |
| 0 | **Disabled** | Standard Training Mode (all scripts off) |
| 1 | **Hit Confirm** | Practicing hit/block recognition |
| 2 | **Reaction Drills** | Practicing reactions to random dummy actions |
| 3 | **Post Guard** | Practicing punishes after blocking |
| 4 | **Custom Combo Trials** | Recording and practicing your own combos |

---

## ⌨️ Shortcuts & Controls

You do not need to keep the menu open. The tools are controlled entirely via your controller using a **Function Button** system.

**The "Function" Key (Func):**
- **Default:** `Select` (Share Button) **OR** `R3`.
- You must **HOLD** this button to access the shortcuts below.

| Action | Shortcut (Hold Func + Press...) | Description |
| :--- | :--- | :--- |
| **Start / Pause** | `RIGHT` (D-Pad) | Starts the drill or pauses the current session. |
| **Stop / Reset** | `LEFT` (D-Pad) | Stops the drill, resets the score, and **Exports stats** to a file. |
| **Increase Timer** | `UP` (D-Pad) | Adds time to the current drill timer. |
| **Decrease Timer** | `DOWN` (D-Pad) | Reduces time from the current drill timer. |

Keyboard shortcuts are also available per mode — see the individual guides in `guides/`.

---

## 🛠️ Training Modes Explained

### 1. Custom Combo Trials (NEW)

Record your own combos and practice them with full input validation, visual feedback, and stats tracking.

- **Record** a combo on the dummy, then **practice** it with step-by-step input display
- **Demo Mode** plays back the combo for you to watch before attempting
- **Per-character combo libraries** — comes pre-loaded with combos across 30 characters
- **Stats tracking** with success rate, timing data, and session history
- D2D overlay shows input notation in real-time with button/arrow icons

### 2. Hit Confirm Training

- **Goal:** The CPU will randomly Hit or Block. You must react:
  - **On Hit:** Complete your combo.
  - **On Block:** Stop safely.
- **Customization:** Set the Block Rate (%), Damage settings, and specific trigger moves.

### 3. Reaction Drills

Practice reacting to specific enemy moves (Drive Impact, Jumps, Whiffs).

- **Auto-Configuration:** No need to configure the Dummy manually.
  - Record your slots (or import them via Slot Manager).
  - The script automatically sets the Dummy to **"Replay Recording"**.
  - It handles **Randomness** and **Playback** logic automatically.
- **Visual Aid:** A large overlay shows the timer and your success rate in real-time.

### 4. Post Guard Training (NEW)

Practice punishing the dummy after blocking its attacks.

- The dummy attacks, you block, then **punish during its recovery**
- Includes **Drive Impact reaction training** — react with your own DI or counter
- Tracks your punish success rate and timing

### 5. Recording Slot Manager

Found in the REFramework menu under **"Slot Manager"**.

- **Export / Import** slot data as JSON per character (28 characters supported)
- **Save As** with custom filenames
- **Export All Chars** in one click
- **Activate On Load** — auto-activate imported slots
- **Input Sequence Programming** — create slot data from input notation
- Per-character subdirectories for organized storage

---

## 📐 Analysis & Visualization Tools

### Distance Viewer

Real-time visualization of attack ranges, opponent zones, crossup distances, and jump arcs.

- **Basic Mode** — Color-coded zones (Red/Orange/Yellow/Green) for quick spacing reads
- **Expert Mode** — Per-move distance data with configurable thresholds
- **Crossup Indicator** — Shows if a forward jump will cross up (standing/crouching)
- **Jump Arc** — Visual trajectory display
- Works in **Training Mode and Online Matches**

### Sheldon's Boxes

Hitbox/hurtbox display with advanced features:

- Hitbox and hurtbox visualization
- Ruler overlay for distance measurement
- Charge move visualization

### Distance Logger

Records distance data during gameplay sessions for offline analysis and zone configuration.

---

## 📱 WIT Remote Control (Android App)

Control your training tools from your phone over WiFi.

> **Patreon-exclusive** — Requires a subscription ($5/mo SF6 Remote tier or $30 Lifetime via Patreon shop).

### Setup

1. **PC:** Navigate to `SF6_TrainingRemoteControlServer/` and launch **WIT_RemoteControl.exe**
   - A tray icon appears in the Windows taskbar
   - A QR code is displayed at startup — scan it to download the APK
   - Auto-starts when SF6 launches, auto-stops when SF6 closes
2. **Phone:** Scan the QR code, install the APK, tap **LOGIN WITH PATREON**
3. **Control everything:** Switch modes, manage combo trials, toggle hitboxes, adjust Distance Viewer, manage recording slots — all from your phone while you play

---

## 📊 Analytics Dashboard

When you finish a session and press **Stop (Func + Left)**, the tool generates a log file in your SF6 folder.

1. Open `TrainingDashBoard.html` in your web browser
2. Click **Import** and select the generated file
3. View detailed graphs, reaction times, success rates, and per-drill analytics

---

## 📖 Documentation

Full user guides are included in the `guides/` folder:

| Guide | Topic |
| :--- | :--- |
| `00_GettingStarted.md` | Installation and first steps |
| `01_DistanceViewer.md` | Distance Viewer — Basic & Expert modes |
| `02_Training_ScriptManager.md` | Script Manager and mode switching |
| `03_CustomComboTrials.md` | Recording, practicing, and sharing combos |
| `04_HitConfirm.md` | Hit Confirm training setup |
| `05_PostGuard.md` | Post-Guard punish training |
| `06_ReactionDrills.md` | Reaction drill setup and slot management |
| `07_RecordingSlotManager.md` | Importing, exporting, and programming slots |
| `08_TrainingRemoteControl.md` | WIT Remote Control setup (PC + Android) |

---

## 📁 Directory Layout

```
reframework/
├── autorun/                         Lua scripts (auto-loaded by REFramework)
│   ├── func/                        Shared modules (UI, D2D, hooks, session recap)
│   └── Small Tools/                 Debug/inspection scripts
├── data/
│   ├── TrainingComboTrials_data/    Custom combos, replay records, input exceptions
│   ├── SF6_RecordingSlotManager_data/  Slot exports per character (28 characters)
│   ├── SF6_DistanceViewer_data/     Distance zone configs & attack data
│   ├── SheldonsBoxes_data/          Hitbox display configs
│   ├── SF6_TrainingRemoteControl_data/  WebBridge & WebState for remote control
│   ├── Stats/                       Session statistics
│   └── ...                          Per-module config files
├── fonts/                           Overlay fonts (.ttf/.otf)
├── guides/                          User documentation (9 guides)
├── html viewers/                    Standalone dashboards & replay editor
├── images/
│   ├── buttonsAndArrows/            Button input & directional icons
│   └── ui_icons/                    UI element icons
├── plugins/                         Native DLL plugins (reframework-d2d)
└── SF6_TrainingRemoteControlServer/ WIT Remote Control tray app
```

---

## ⚠️ Troubleshooting

- **Menu not showing?** Press `Insert` to open REFramework.
- **Text looks wrong/blocks?** Ensure the font files are correctly placed in `reframework/fonts/`.
- **Shortcuts not working?** Make sure you are **holding** the Function button (`Select` or `R3`) while pressing the D-Pad.
- **Script crash?** Ensure you have the latest REFramework Nightly build.
- **Distance Viewer not showing?** Make sure `reframework-d2d.dll` is in `reframework/plugins/`.

---

_Created by Wael3rd._
