# NIGHT SHIFT: NOT HUMAN

A first-person psychological horror cashier game. You work the night shift at a small
grocery store. Customers come in, shop, and bring their groceries to your counter. Most of
them are people. Some of them are wearing people.

Scan their items. Study their hands, their eyes, the way they breathe. Then either take
their money or refuse the sale.

Built with **Godot 4.7.1** (Mobile renderer) for the **Logitech G Cloud** handheld.

---

## Download the APK

Open this on the handheld's browser and it will download straight to the device:

**https://github.com/InVisionx/mylas_game/raw/main/dist/NightShift-NotHuman.apk**

Then:
1. Open **Files → Downloads** and tap `NightShift-NotHuman.apk`.
2. Allow "install unknown apps" for Chrome/Files when prompted.
3. Launch **Night Shift: Not Human**; it starts in landscape with controller support.

The build is arm64-v8a, minSdk 24, signed, ~25 MB. Current file hash is in
[`dist/SHA256.txt`](dist/SHA256.txt). It only needs to be installed again when a new
version is posted.

Optional: to serve it from a short release URL
(`https://github.com/InVisionx/mylas_game/releases/latest/download/NightShift-NotHuman.apk`)
run `tools\publish_release.ps1` once with a GitHub token; the plain link above needs no setup.

---


## Status

Playable, end to end:

- Main menu → five authored nights → shift report → next night → endless overtime.
- Customers spawn outside, walk in through sliding doors, browse aisles, queue, place
  groceries on the belt, talk, pay or get refused, and leave.
- Full checkout: pick an item, it slides to the scanner, beep, price, running total.
- Inspection with 13 focus points (face, eyes, mouth, hands, neck, posture, reflection,
  shadow, behaviour, items, payment, register, security feed).
- 25 anomalies across visual / behavioural / checkout categories, plus 10 harmless traits
  that exist specifically to make you wrong sometimes.
- Five jumpscare sequences, fifteen environmental horror events, procedural audio.
- Local save of money, progress, discovered clues, settings and key bindings.

---

## Running it

Requires Godot 4.7.1 (`Godot_v4.7.1-stable_win64.exe`).

```powershell
# Editor
& "C:\Users\mattm\Desktop\godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe" --editor --path .

# Direct to a shift (skips the menu)
& "...\Godot_v4.7.1-stable_win64_console.exe" --path . -- --night=1

# Headless smoke test of the real systems (28 checks)
& "...\Godot_v4.7.1-stable_win64_console.exe" --headless --path . -- --night=1 --selftest
```

Debug launch flags (after the bare `--`): `--night=1` … `--night=5`, `--endless`,
`--selftest`.

---

## Controls

### Controller (Logitech G Cloud, standard Android gamepad)

| Action | Input |
|---|---|
| Move / look | Left stick / right stick |
| Interact, scan, talk | A |
| Cancel / leave dialogue | B |
| Inspect customer | X |
| Notebook | Y |
| Approve | Right trigger |
| Reject | Left trigger |
| Sprint | Left stick click |
| Crouch | Right stick click |
| Zoom inspection | Left bumper |
| Switch inspection focus | D-pad left / right (up / down also works) |
| Pause | Menu / Start |

### Mouse and keyboard

`WASD` move · mouse look · `E` interact/scan · `F` inspect · `Tab` notebook ·
`Enter` approve · `Backspace` reject · `Shift` sprint · `Ctrl` crouch · `Q` / right mouse zoom
· `,` `.` switch focus · `Esc` pause.

All of these are the *same* actions at runtime — see `scripts/autoload/input_manager.gd`.
Every action can be rebound in **Pause → Controls & Bindings**, and bindings persist.

### Touch

On a touchscreen without a gamepad, on-screen sticks and buttons appear and feed the same
action map. They hide automatically when a controller is connected.

---

## How to play

1. Stand behind the counter. The first customer walks in on their own.
2. When they reach the counter, their groceries appear on the belt.
3. Look at an item and press **A / E** to scan it. Repeat.
4. Press **X** to inspect. Cycle focus with the D-pad. **Hold** a focus — a bar fills.
   When it fills you either find evidence, or find nothing, or find something harmless.
5. Ask questions (walk up and press **A / E**) to hear how they talk.
6. **RT / Enter** approves, **LT / Backspace** rejects.
7. Being wrong costs money. Letting an entity pay costs more than money.

Rule of thumb the game teaches: *one* strange thing is not proof. An innocent customer can
have a scar, a lazy eye, a bandaged hand. Entities always carry at least one findable clue,
and higher nights make clues subtler rather than removing them.

---

## Project layout

```
scenes/            boot, main_menu, store, player, customer
scripts/autoload/  Events, SaveManager, SettingsManager, GameData, InputManager,
                   AudioManager, GameManager
scripts/world/     store_layout (floor plan + nav graph), store_builder, store, staff_door
scripts/customer/  customer (AI/state machine), customer_body (procedural rig + anomalies)
scripts/systems/   shift_manager, checkout_manager, inspection_manager, security_monitor
scripts/items/     product_mesh, product_item
scripts/horror/    horror_director (environmental events + jumpscares)
scripts/ui/        ui_kit, hud, touch_controls, pause_menu, notebook_ui, shift_report, main_menu
scripts/audio/     audio_synth (offline synthesis)
scripts/dev/       self_test (headless smoke test, excluded from export)
data/              products.json, anomalies.json, personalities.json, shifts.json, horror_events.json
shaders/           store_floor, vignette
```

Deliberate design notes:

- **No navmesh baking.** `StoreLayout` authors the floor plan and an `AStar3D` waypoint graph
  is connected by line-of-sight tests against shelf/counter rectangles. Cheap and
  deterministic on mobile.
- **No imported art or audio.** Customers are assembled from ~20 primitives with a code
  animation layer, and every sound is synthesised at startup. This keeps the APK tiny and
  makes the whole game tunable in place.
- **Data-driven balance.** Products, anomalies, dialogue, night tuning and horror events are
  JSON in `data/`. Add an anomaly there and it joins the inspection pool automatically.
- **One input map.** Gamepad, keyboard, mouse and touch write to the same actions.

---

## Tuning the game without code

| File | What it controls |
|---|---|
| `data/shifts.json` | customers per night, entity chance, clue obviousness floor, basket size, time limit, pay, fines, endless scaling |
| `data/anomalies.json` | every clue: focus, obviousness, dwell time, text, which visual mutation it applies |
| `data/personalities.json` | greetings and answers per personality, entity dialogue pools |
| `data/products.json` | products, prices, shapes, impossible items |
| `data/horror_events.json` | environmental event weights, unlock night, cooldowns; jumpscare pool |

`min_obviousness` in a night is the fairness dial: `3` only spawns blatant clues, `1` allows
the subtle ones. Night 1 uses 2, Night 3+ uses 1.

---

## Saving

`user://nightsave.json` holds money, nights completed, unlocked shift, endless best, stats and
discovered anomalies. Settings and bindings live in `user://settings.cfg`. Everything is local
and offline; saves happen automatically after every shift, and whenever a new clue is logged.

To wipe progress: delete those two files from
`%APPDATA%\Godot\app_userdata\Night Shift Not Human\` (Windows) or the app's files dir on
Android.

---

## Updating the game

The APK checks GitHub on every launch. If a newer build is published, the main menu shows an
**UPDATE AVAILABLE** banner with the version and notes; one press opens the download in the
browser, then tapping the downloaded file installs it over the old build (same signing key, higher
version code).

Android never lets a sideloaded app install an APK silently — that requires device-owner or root —
so this is the closest safe flow: automatic detection, one press to download, one confirm to install.

To publish an update:

```powershell
powershell -ExecutionPolicy Bypass -File tools\publish_update.ps1 -Version 0.3.0 -Notes "What changed"
```

That bumps `project.godot` + the Android preset, rebuilds `dist/NightShift-NotHuman.apk`, rewrites
`dist/version.json` (the manifest the game reads), then commits and pushes. Add `-NoPush` to build
without publishing. Keep the same keystore (`%APPDATA%\Godot\keystores\nightshift.keystore`) or
Android will refuse to upgrade over the installed copy.

The check reads the GitHub contents API first (never CDN-cached, so a fresh publish is seen
immediately) and falls back to `raw.githubusercontent.com` (cached a few minutes). It fails
silently when offline and never blocks play.

---

## Android / G Cloud

The project is configured for the Mobile renderer, 1920×1080 canvas, landscape, arm64-v8a.

```powershell
# One-time: install export templates + Android SDK, then
& "...\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --export-release "Android" build/NightShift-NotHuman.apk
```

- Export templates go in `%APPDATA%\Godot\export_templates\4.7.1.stable\`.
- Android SDK path is read from the editor setting `export/android/android_sdk_path`
  (`%LOCALAPPDATA%\Android\Sdk`).
- The JDK path must be set in `export/android/java_sdk_path` (JDK 17 here:
  `C:/Program Files/Microsoft/jdk-17.0.20.101-hotspot`) or the exporter refuses to run.
- Install into the SDK: `platform-tools`, `build-tools;34.0.0` and `build-tools;35.0.0`,
  `platforms;android-34` and `platforms;android-35`.
- `tools\build_android.ps1` does the SDK check + export in one step.
- Output: `build\NightShift-NotHuman.apk` — 25.5 MB, arm64-v8a, signed, sideload with
  `adb install -r build\NightShift-NotHuman.apk`.
- The release signing key lives at `%APPDATA%\Godot\keystores\nightshift.keystore`
  (alias `nightshift`, password `nightshift`). Generate your own key before distributing.
- A debug build is also produced with `--export-debug` if you need remote debugging.
- JSON data files are packed via the preset's `include_filter="*.json"`; without that they
  are not resources and would be missing at runtime.

Performance choices that matter on the G Cloud: no shadows from point lights, no SSAO/glow,
one 384×216 SubViewport for CCTV that only renders while you look at it, products batched into
MultiMeshes, ~230 meshes total, and a Quality setting that trims fill lights and render scale.
60 FPS cap by default, with a 30 FPS option.

---

## What is still placeholder

Art and audio are intentionally procedural, not final. Clean replacement points:

- **Characters:** `scripts/customer/customer_body.gd` is the only place that builds a body.
  Swap `build()` for a glTF instance and keep the anchor API (`head_anchor`, `hand_anchor`,
  `eyes_anchor`, `animate`, `freeze`, `set_skin_glitch`) and every anomaly keeps working.
- **Products:** `scripts/items/product_mesh.gd`; drop a `models/products/<id>.glb` and it is used
  automatically, scaled to the size in `data/products.json` (see `models/README.md`).
- **Store:** `scripts/world/store_builder.gd`; each fixture is one function, and
  `scripts/world/store_layout.gd` holds the dimensions the AI depends on.
- **Audio:** `scripts/autoload/audio_manager.gd` keeps a name → stream dictionary. Replace any
  entry with `load("res://audio/your_file.wav")` and nothing else changes.

---

## Known limits

- No voice acting: dialogue is text with synthesized vocal blips per customer.
- "No reflection" is reported through inspection text rather than a real-time mirror; the
  store has no reflective surfaces.
- The five nights share one store layout, one customer rig and one product set; variety comes
  from anomaly mix, behaviour, dialogue and horror events.
- Release APK is signed with a local self-signed key, which is fine for sideloading on your own
  device but not for store distribution (generate your own keystore for that).
- Endless mode reuses the night content with scaling; it has no unique final encounter.

