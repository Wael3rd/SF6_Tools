# SF6 Training Tools (Wael3rd Edition)

Welcome to the **SF6 Training Tools** suite. This collection of Lua scripts and Web Dashboards is designed to enhance your training experience in Street Fighter 6 by adding Hit Confirm drills, Reaction drills, and advanced Recording Slot management.

## 📦 Prerequisites

Before installing, ensure you have the following installed for Street Fighter 6:

1.  **REFramework:** [Download here](https://github.com/praydog/REFramework/releases) (Extract `dinput8.dll` into your SF6 folder).
2.  **REFramework Font Support:** The scripts require specific fonts to render the UI correctly.

## 📂 Installation Guide

### 1. Script Installation
Copy the following `.lua` files into your **SF6 installation folder** under:
`Street Fighter 6\reframework\autorun\`

* `Training_ScriptManager.lua` (The Main Controller)
* `TrainingHitConfirm_v1.0.lua`
* `TrainingReactions_v1.0.lua`
* `SF6_RecordingSlotManager.lua`

### 2. Font Installation
Copy the required `.ttf` font files (found in this repository) into:
`Street Fighter 6\reframework\fonts\`

* `SF6_college.ttf`
* `capcom_goji-udkakugoc80pro-db.ttf`

> **Note:** If the `fonts` folder does not exist inside `reframework`, create it manually.

### 3. Dashboards & Editor (Stats)
The `.html` files are standalone tools. **Do not** put them in the game folder.
* Create a folder on your Desktop (e.g., "SF6 Stats") and keep these files there:
    * `HitConfirmDashBoard.html`
    * `ReactionDashBoard.html`
    * `SF6_Replay_Editor.html`

---

## 🎮 How to Use

### The "Trainer Manager"
Once in-game, press **Insert** to open the REFramework menu. Go to **"Script Generated UI"** -> **"Trainer Manager"**.

This script acts as the "Conductor". You use it to select your active mode:
1.  **Normal:** Standard Training Mode.
2.  **Reaction Training:** Practicing whiff punishes, anti-airs, etc.
3.  **Hit Confirm:** Practicing hit/block recognition.

---

## ⌨️ Shortcuts & Controls

You do not need to keep the menu open. The tools are designed to be controlled entirely via your controller using a **Function Button** system.

**The "Function" Key (Func):**
* **Default:** `Select` (Share Button) **OR** `R3`.
* You must **HOLD** this button to access the shortcuts below.

| Action | Shortcut (Hold Func + Press...) | Description |
| :--- | :--- | :--- |
| **Start / Pause** | `RIGHT` (D-Pad) | Starts the drill or pauses the current session. |
| **Stop / Reset** | `LEFT` (D-Pad) | Stops the drill, resets the score, and **Exports stats** to a file. |
| **Increase Timer** | `UP` (D-Pad) | Adds time to the current drill timer. |
| **Decrease Timer** | `DOWN` (D-Pad) | Reduces time from the current drill timer. |

---

## 🛠️ Game Modes Explained

### 1. Reaction Training (Auto-Config)
This tool helps you practice reacting to specific enemy moves (Drive Impact, Jumps, Whiffs).

* **Auto-Configuration:** You do **not** need to configure the Dummy manually in the game menus.
    * Simply record your slots (or import them via Slot Manager).
    * The script automatically sets the Dummy to **"Replay Recording"**.
    * It handles the **Randomness** and **Playback** logic automatically.
* **Visual Aid:** A large overlay shows you the timer and your success rate in real-time.

### 2. Hit Confirm Training
* **Goal:** The CPU will randomly Hit or Block. You must react:
    * **On Hit:** Complete your combo.
    * **On Block:** Stop safely.
* **Customization:** Inside the REFramework menu, you can set the Block Rate (%), Damage settings, and specific trigger moves.

### 3. Recording Slot Manager
Found in the REFramework menu under **"Slot Manager"**.
* **Export Slots:** Saves your current dummy recordings to a JSON file.
* **Import Slots:** Loads saved recordings onto the current character.
* **Useful for:** Sharing setups with friends or saving specific character drills (e.g., "Ken Whiff Punish Setups").

---

## 📊 Analytics Dashboards

When you finish a session and press **Stop (Func + Left)**, the tool generates a `.txt` log file in your SF6 folder (e.g., `Reaction_SessionStats.txt`).

1.  **View Your Stats:**
    * Open `ReactionDashBoard.html` or `HitConfirmDashBoard.html` in your web browser.
    * Click **Import** and select the generated text file.
    * View detailed graphs, reaction times, and success rates.

2.  **Edit Replays (SF6_Replay_Editor.html):**
    * A visual tool to create or edit recording slots in your browser.
    * Export the result as JSON and load it back into the game using the **Slot Manager**.

---

## ⚠️ Troubleshooting

* **Menu not showing?** Press `Insert` to open REFramework.
* **Text looks wrong/blocks?** Ensure the `.ttf` files are correctly placed in `reframework/fonts/`.
* **Shortcuts not working?** Make sure you are **holding** the Function button (`Select` or `R3`) while pressing the D-Pad.
* **Script crash?** Ensure you have the latest REFramework Nightly build.

---
*Created by Wael3rd.*
