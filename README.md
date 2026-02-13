# VaporRush Endless Starter (Godot 4)

This project is now a polished **Endless v1** loop with mobile-safe rendering:
- Continuous 360-degree tube surfing (angle-based control), deterministic collision (no physics)
- MultiMesh rendering for enemies/elites/pickups with capped instance budgets
- Shield pickup flow: elite hit breaks shield; no-shield elite hit ends run
- Rewarded continue path: continue grants shield only on reward callback
- Interstitials shown with a run-frequency cap and never immediately after rewarded
- Juice layer: wave rhythm phases, combo-chain scaling, near-miss rewards, slipstream boosts, shader hit pulses, camera/FOV feedback

## Controls
- Desktop: Left/Right arrows or A/D (hold for angular steering)
- Desktop: `Space` fires player lasers
- Mobile: drag left/right (continuous angular steering)

## AdMob IDs (your values)
- App ID: ca-app-pub-8413230766502262~7166483341
- Interstitial: ca-app-pub-8413230766502262/6763158660
- Rewarded: ca-app-pub-8413230766502262/8678767766

## Plugin recommendation
This starter assumes you'll use Poing Studios' Godot AdMob plugin (Godot 4.2+), installed under `res://addons/`.
Docs: https://poingstudios.github.io/godot-admob-plugin/

## Architecture (systems)
- `RunController`: authoritative start/end/resume and run timer
- `SpeedSystem`: fixed-speed by default (time-ramp disabled for comfort), with optional tunable bonuses
- `DifficultySystem`: run-time ramp + recent-combo performance term
- `PatternGenerator`: weighted Galaga-like formation templates with deterministic motion (angle sway + z follow/drift), density scaling, and shield pity timer
- `SpawnSystem`: incremental MultiMesh window updates (no full per-frame rebuild)
- `CollisionSystem`: deterministic overlap using runtime angle+z windows, elite-priority resolution, combo-reset miss behavior, near-miss detection
- `AngleSystem`: continuous angle integration and player placement around the tube
- `WaveSystem`: Build -> Surge -> Release -> Powerup rhythm cycle, with periodic boss surge windows
- `SlipstreamSystem`: moving flow lines around the tube that grant speed boost when matched
- `ComboSystem` + `ScoreSystem`: timed combo-chain multiplier, score scaling, near-miss bonuses
- `ProgressionSystem`: persistent high score/runs, daily-seed helper, cosmetic unlock placeholders
- `UISystem`: HUD + wave status + score popups + run-end panel + continue/restart flow
- `VFXSystem`: camera shake/FOV ramp, near-miss micro slow-mo, shader pulses/flashes/desaturation/flow intensity

## GitHub Pages Deploy (Like LumaRush)
- Workflow file: `.github/workflows/deploy-pages.yml`
- Trigger: push to `main` (or manual `workflow_dispatch`)
- Export target: Godot preset `"Web"` -> `build/web/index.html`

### One-time GitHub setup
1. Push this repo to GitHub (default branch `main`).
2. In GitHub: `Settings -> Pages`.
3. Set Source to `GitHub Actions`.
4. Push to `main` and wait for the `Deploy Godot Web To Pages` workflow.
5. Your game URL will be shown in the Pages deployment environment output.

### CI notes
- The workflow disables editor plugins during CI export to avoid plugin parse/runtime issues.
- It also disables common AdMob plugin folders for web CI if present.
- Godot headless + export templates are installed in the runner (no extra secrets needed).

## AdMob setup
1. Install the Poing plugin in `res://addons/admob/` and enable it in Project Settings -> Plugins.
2. Confirm autoload: `AdManager` points to `res://scripts/core/AdManager.gd` (already set in `project.godot`).
3. Use these IDs in `scripts/core/AdManager.gd`:
   - App ID: `ca-app-pub-8413230766502262~7166483341`
   - Interstitial: `ca-app-pub-8413230766502262/6763158660`
   - Rewarded: `ca-app-pub-8413230766502262/8678767766`

### Android notes
- Per Poing docs, set the AdMob Application ID in:
  `res://addons/admob/android/config.gd` (`APPLICATION_ID`)
- Ensure your Android export uses Internet permissions required by the plugin.

### iOS notes
- Set the AdMob iOS app ID in the plugin iOS config/plist integration path described by Poing docs.
- Re-run Xcode dependency sync after changing plugin ad config.

## Tuning defaults (juice-critical)
- `ComboSystem.gd`: `combo_chain_window = 1.2`, `combo_step_for_multiplier = 5`
- `CollisionSystem.gd`: `hit_window_angle = 0.16`, `near_miss_angle_window = 0.24`
- `WaveSystem.gd`: `10s build / 8s surge / 4s release / 3s powerup`
- `SlipstreamSystem.gd`: `flow_line_count = 3`, `flow_width = 0.22`
- `VFXSystem.gd`: `near_miss_time_scale = 0.94`, `near_miss_slow_duration = 0.07`
- `PatternGenerator.gd`: shield quota per stage (`min_shields_per_stage = 1`, `max_shields_per_stage = 2` by default)

## Laser Shader Resources
- Base shader: `res://shaders/laser_blaster_glow.gdshader`
- Player laser material (green): `res://materials/player_laser_green.tres`
- Enemy laser material (red): `res://materials/enemy_laser_red.tres`
- Attribution base: https://godotshaders.com/shader/laser-blaster-glow/

## Explosion Shader Resources
- Explosion shader: `res://shaders/explosion_3d_vfx.gdshader`
- Explosion material: `res://materials/explosion_vfx.tres`
- Runtime system: `scripts/systems/ExplosionSystem.gd` (enemy hit + player death)
- Attribution base: https://godotshaders.com/shader/3d-explosion-vfx/

## Audio Hooks
- Runtime system: `scripts/systems/AudioSystem.gd`
- Sources used from `assets/sound/explosion/`:
  - laser fire: `laserShoot*.wav`
  - explosion/death: `explosion*.wav`
  - powerup pickup: `powerUp.wav`

## Next steps
- Tune formation motion (`formation_follow_ratio`, `formation_forward_drift`, sway amplitudes) from device playtests.
- Add projectile attacks for formation dive phases once shooting loop is finalized.
- Add audio layering tied to combo milestones and wave phases.
