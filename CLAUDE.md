# CLAUDE.md

Guidance for Claude (and humans) working in this repository.

## Project

**Thug Life** (working title): a 3D third-person (over-the-shoulder) sandbox action game with RPG elements. The player starts as a low-level criminal and climbs the criminal hierarchy. The setting is a fictional, present-day harbour district (*Brickhaven*), with a light satirical tone aimed upward (systems, corporations, authorities), never at ethnic groups or the poor.

- **Engine:** Godot **4.7** (4.7.2-stable), **GDScript**, Forward+ renderer, **Jolt** physics
- **Platform:** PC (Windows) first. Don't add anything that blocks other platforms.
- **IDE:** VS Code + godot-tools

**The design source of truth is [`docs/GDD.md`](docs/GDD.md).** Read the relevant section before implementing a feature. Status tags in the GDD:
**[Decided]** settled · **[Proposal]** suggested, awaiting approval · **[Open]** needs brainstorming · **[Postponed]** deferred.
Never treat an [Open] item as decided. If a task needs one, ask instead of inventing the design. Proposal details can be implemented, but flag any deviation.

## Milestones

| # | Milestone | Status |
|---|---|---|
| M0 | Setup and folder structure | done |
| M1 | Character skeleton (GDD §19, M1.1–M1.7) | implemented, needs playtest and tuning in the editor |
| M2 | Melee combat (GDD §7, §19 M2.1–M2.8): fists + one blunt weapon, one enemy type, combat arena | implemented; Mixamo model + locomotion in, combat clips are generated placeholders until Mixamo combat clips arrive; needs playtest/tuning |
| M3a | Inventory, loot and lethality (GDD §7, §12, §13, §19 M3a): slot inventory, wallet, looting, death, knife, HUD | implemented; needs playtest/tuning |
| M3b | District (GDD §19 M3b): gray-box Brickhaven, district gym, civilians that panic and can be fought/looted, thug spawns, basic minimap; no police, crime or cars | implemented; needs playtest/tuning |
| M4a | Combat update (GDD §7, §19 M4a): animation pass, clip-driven attack timing, feel tuning, crouch, stomp, inventory pauses the game | implemented; real clips for jab, uppercut, knife, hit reactions, knockdown, get-up, crouch and jumps; cross, hook, bat, guard, dodge and stomp are still placeholders (`assets/animations/CLIPS.md`); needs playtest/tuning |
| M4b | Firearms (GDD §7, §19 M4b): one firearm, ammo, weapon switching, sticky cover, ranged enemy | implemented: rifle (real rifle clips for aim/strafe/fire/reload/hit), magazines, switching, cover (no cover clips yet), rifle thug, mixed fight mode; needs playtest/tuning (balance is a proposal) |
| — | **Gate:** define the Core Loop (GDD §5) before M5a | |
| M5a | Crime fundamentals (GDD §8, §19 M5a): pickpocket → witness → report → heat 1, police patrol, arrest, firearm use → heat | |
| M5b | First progression loop (shop robbery, shops, interiors, `WorldClock`, heat 2, first rank-up) | |
| M6 | Nightlife (day/night cycle, fight club) | |
| M7–M9 | Customization, second district + cars, vehicle roster (GDD §17, §18) | |

Each milestone is built on its own branch and merged by PR. A task is done when its GDD "Done when" criterion works in the test level.

## Running

- Main scene: `res://scenes/levels/district.tscn` (M3b gray-box Brickhaven: streets, Brix Square, back alleys with street thugs, walking civilians, reserved lots, the district gym in the boxing club yard up Dock Street, minimap). In the yard, press the **Start fight** button (E) or F5/F6; outside it those keys do nothing. A rifle and magazines are laid out in the yard; another rifle lies in the south-west back alley (`Stash`); two street rifle thugs live in the south-east alley and on the Old Quay. A downed player wakes up at St. Brix Clinic and pays a fee. The M2/M3a arena `res://scenes/levels/combat_gym.tscn` is kept as a debug scene (F5/F6 anywhere), and the M1 gym `res://scenes/levels/test_gym.tscn` still works (open either and press F6).
- Controls (all bound in the InputMap, `project.godot` `[input]`): WASD move · Shift sprint · Ctrl walk · Space jump · C crouch (toggle; `Player.crouch_toggle` = false for hold) · LMB attack (tap = light, hold 0.28 s = heavy; next to a knocked-out body: stomp) · MMB heavy · RMB guard · Space while guarding = dodge · E interact / pick up (hold E: search a body) · G drop weapon · H holster/draw weapon · Tab inventory overlay (pauses the game) · Q swap shoulder · F3 debug overlay (also floating labels on NPCs) · F4 play the next clip, every clip except grenades (debug) · F5 restart fight · F6 next fight mode (1 vs 3 → 1 vs 1 → training dummy → mixed: 2 thugs + 2 rifle thugs) · Esc release mouse. Firearm (M4b): RMB aim · LMB fire (without RMB: hip fire) · R reload · Space while aiming = dodge · 1 fists / 2 melee / 3 firearm · mouse wheel cycles weapons · H holsters/draws the last weapon · G drops the weapon in hand · F sticky cover (again, pull away, sprint or jump to leave; aim to pop up / peek). The low scaffold in the north-east corner of the gym yard is the crouch test spot.
- RMB is **guard** while unarmed or holding a melee weapon and **aim** with a firearm in hand (both actions are bound to RMB; the player decides per tick from what is in hand). The M2 bindings and their deviations from the proposal are in GDD §19, "M2 implementation notes"; the M4b ones in "M4b implementation notes".
- Headless checks (CI or a cloud container):
  ```bash
  godot --headless --import            # (re)generate .godot/ cache and .uid files
  godot --headless --quit-after 120    # boot the main scene for ~2 s, watch for script errors
  godot --headless --fixed-fps 60 res://tests/combat_tests.tscn   # M2 test suite, exit code 0 = pass
  godot --headless --fixed-fps 60 res://tests/m3a_tests.tscn      # M3a test suite, exit code 0 = pass
  godot --headless --fixed-fps 60 res://tests/m3b_tests.tscn      # M3b test suite (district), exit code 0 = pass
  godot --headless --fixed-fps 60 res://tests/m4a_tests.tscn      # M4a test suite (clips, timing, crouch, stomp, pause)
  godot --headless --fixed-fps 60 res://tests/m4b_tests.tscn      # M4b test suite (firearm, ammo, switching, cover, rifle thug, mixed fight)
  ```
  The test suites load the real arena (M3b: the real district) and drive the real player through the InputMap (`Input.action_press`). Headless can't capture the mouse, so it sets `Player.require_mouse_capture = false`.
- Placeholder combat clips are generated for the character skeleton: `godot --headless --script res://scripts/tools/generate_combat_clips.gd` rewrites `assets/animations/combat_placeholder.tres` (needs the model imported first). Only moves without a real clip are generated (cross, hook, bat, guard poses, dodge, stomp).
- The shared AnimationTree is generated: `godot --headless --script res://scripts/tools/build_humanoid_tree.gd` rewrites `assets/animations/humanoid_tree.tres` from the tables in the script. Measure a clip with `godot --headless --script res://scripts/tools/analyze_clips.gd -- <clip> [--frames]`.
- Lint and format (gdtoolkit 4.x, `pip install "gdtoolkit==4.*"`). Config is in `gdlintrc`:
  ```bash
  gdformat scripts tests && gdlint scripts tests
  ```

## Folder structure

```
assets/        art and audio. Binary formats go through Git LFS (.gitattributes)
  animations/  humanoid_tree.tres (shared AnimationTree, generated), combat_placeholder.tres
               (generated), mixamorig9_/mixamorig12_bone_map.tres (retarget maps per download
               prefix), clip_data.json (trims, markers, segments), CLIPS.md (clip manifest),
               mixamo/*.fbx (one clip per file, snake_case)
  materials/   .tres materials (gray-box grid ShaderMaterials, solid colours);
               characters/ = external materials of the character model
  shaders/     .gdshader files
  models/      character models (player.fbx and the textures extracted from it on import)
  textures/ audio/
data/          data-driven content as .tres/.json
  attacks/     AttackData (one per punch/swing/stab)
  items/       ItemData, WeaponData and FirearmData (fists, thug_fists, bat, knife, rifle,
               rifle_magazine, pocket items)
  loot/        LootTable per NPC type (thug, collector, civilian, rifle_thug)
docs/          GDD and other design docs
scenes/        .tscn, by feature: player/, npc/, levels/, interactables/, props/, ui/
scripts/       .gd, mirrors scenes/ by feature:
  autoload/    global singletons (keep these few and small)
  camera/ components/ data/ interactables/ levels/ npc/ player/ ui/
  tools/       editor/CLI generators (not used at runtime)
tests/         headless test scenes (combat_tests, m3a_tests, m3b_tests, m4a_tests, m4b_tests;
               m4b_test_base.gd holds the M4b helpers)
```

Scenes and scripts are kept in parallel trees. Reusable building blocks (e.g. `Interactable`, `InteractionComponent`) go in `scripts/components/`.

## Architecture rules

1. **Components, not god scripts.** The player is a thin `CharacterBody3D` (`scripts/player/player.gd`) that reads input and passes **intent** to separate components: `PlayerMovement`, `CameraRig`, `PlayerAim`, `InteractionComponent`, `PlayerAnimator`. Components don't read `Input` directly (exceptions: the camera's mouse look, and UI). This lets NPC controllers drive the same components: from M2 on, enemies use the same movement, health and combat components as the player. (`PlayerMovement` keeps its name for now; renaming it means a move through the Godot editor, so do it only when asked.)
2. **Explicit update order.** `Player._physics_process` calls components in a fixed order: aim → movement → interaction → animation. From M2, combat runs before movement (aim/guard → combat → movement → interaction → animation), because attacks lock or drive movement (lunge). From M4b: pending weapon switch → aim/guard → combat → ranged → cover → movement → interaction → animation (cover edits the movement intent after combat; NPCs: think → combat → ranged → movement → animation). The camera rig runs in `_process`.
3. **No hardcoded keys.** Every input goes through an InputMap action. New actions go in `project.godot` `[input]`.
4. **Every tuning value is an `@export`** (grouped with `@export_group`) or lives in a Resource. No magic numbers in logic.
5. **Data-first content.** Items, crimes, NPC types, factions and ranks are Resources in `data/` (e.g. `ItemData` → `data/items/*.tres`), never hardcoded.
6. **No special cases in the player.** Interactive objects add an `Interactable` child (an Area3D on the `interactable` layer) and connect to its `interacted` signal. External effects use duck-typed methods such as `apply_knockback(impulse: Vector3)`.
7. **Signals up, calls down.** A parent calls methods on its children. Children report back through signals. `Events` (autoload, `scripts/autoload/events.gd`) is reserved for cross-cutting fire-and-forget events (UI notifications, later crime events).
8. System names from the GDD:
   - **M2 (melee, implemented):** `HealthComponent`, `HitboxComponent` (attacker's damaging volume), `HurtboxComponent` (where a character can be hit), `MeleeCombat`, `SoftTargeting`, `CombatDirector` (attack tokens), `RagdollComponent`, `ModelFlash`, `CombatAudio`, `HitStop`; NPC side `NpcCharacter` (thin body) + `ThugAI` (controller). Resources `AttackData` (`data/attacks/*.tres`) and `WeaponData` (extends `ItemData`, `data/items/`). `MeleeCombat` takes a `MeleeCombat.Intent` each tick, like `PlayerMovement`, and changes movement only by editing the movement intent in `apply_to_movement()` (lock, lunge/dodge velocity override, guard strafing). Animation requests go up as `clip_requested` / `clip_stopped` signals; the character root connects them to its `PlayerAnimator`.
   - **M3a (inventory/loot, implemented):** `InventoryComponent` (melee slot drawn/holstered, firearm slot locked until M4b, pocket slots, wallet; owns weapons and drops them: `MeleeCombat` only holds what `set_weapon()` puts in hand), `LootTable` + `LootEntry` (`data/loot/*.tres`, rolled into an NPC's inventory on spawn), `BodySearch` (hold-to-search `Interactable` on a downed body, emits `looted(victim, by)`). `HealthComponent` states `ACTIVE` → `KNOCKED_OUT` → `DEAD` with downed damage and a knockout recovery timer; `AttackData.damage_type` (blunt knocks out, blade/firearm kill). `Interactable.hold_time` + `InteractionComponent.update_hold()` for held interactions. Pickups hand items over through a duck-typed `receive_item(item) -> bool`; searches find the interactor's inventory through `get_inventory()`. NPC types are scene variants for now (`scenes/npc/collector.tscn` inherits `thug.tscn`), each with its own `LootTable`.
   - **M3b (district, implemented):** `District` (level root: navigation bake, NPC populations, clinic respawn, minimap data through `get_minimap_shapes()`), `FightArena` (restartable fight: spawner, weapons, modes; the district gym and `combat_gym.gd` both use it), `EnemySpawner` population mode (`population`, `start_population()`, respawns out of the player's range, removes old bodies), `NpcController` (base of `ThugAI` and `CivilianAI`; `NpcCharacter.ai` is typed to it), `CivilianAI` (walks a `WalkRoute`, panics: flee / calm down / back to the route), `WalkRoute` (Marker3D children = route points), `Minimap` (HUD). `ThugAI` aggro: `aggro_radius` / `lose_radius` (0 = arena behaviour, hunt anywhere), line of sight, provoked by hits, walks home. NPC scene variants: `street_thug.tscn` (aggro radius set), `civilian.tscn` (swaps the AI script for `civilian_ai.gd`, team `civilians`, own `LootTable`).
   - **M4a (combat update, implemented):** attack timing comes from clip markers (`hit`, `hit_end`, `end`; reactions `recover`, `down`): `MeleeCombat.get_attack_timing()` → `MeleeCombat.AttackTiming`, read through `MeleeCombat.clip_source` (the character root assigns its `PlayerAnimator`, which answers `get_clip_marker()` / `get_clip_end()`). `AttackData.speed` (≤ 1) replaces hand-typed windup/active/recovery (kept only as a fallback) and `AttackData.downed_damage` was added. `MeleeCombat.stomp_attack` + `SoftTargeting.find_downed()` (stomp, player only); `MeleeCombat.ragdoll` picks `getup_from_back` / `getup_from_front` (`RagdollComponent.is_face_down()`). Crouch is `PlayerMovement.Intent.crouch` / `is_crouched` / `can_stand()`; `MeleeCombat.Intent.hold_actions` keeps combat input buffered while crouched. `PlayerAnimator.notify_jump()` (connected to `PlayerMovement.jumped`) and the air/crouch layers. `HUD.set_inventory_open()` pauses the tree.
   - **M4b (firearms, implemented):** `FirearmData` (extends `WeaponData`, firearm slot: `fire_attack`, magazine, `ammo_item`, spread, fire/reload clips, `aim_yaw_offset_degrees`), `RangedCombat` (takes a `RangedCombat.Intent` each tick: aim, fire, reload, aim point; fires a ray from the chest at the aim point, hurtboxes of other teams take it; ammo lives in `InventoryComponent.firearm_rounds`, magazines are pocket items; reports shots through `MeleeCombat.report_shot()`), `FirearmEffects` (muzzle flash, tracer, impact, sound, NPC laser telegraph), `CoverComponent` (sticky cover, `CoverComponent.Intent`, edits the movement intent in `apply_to_movement()`), `RangedThugAI` (extends `ThugAI`, overrides `_engage()`; cover points sampled from the navmesh), `CombatDirector` shooter tokens (`request_shot_token()`, separate from melee tokens). `InventoryComponent.Hand` / `draw()` / `get_next_hand()` for switching, `pick_up_weapon(weapon, rounds)`, `drop_weapon(slot)`. `FightArena.Mode.MIXED` + `mixed_scenes`; `EnemySpawner.spawn(count, configure, scenes)`. NPC variants `rifle_thug.tscn` / `street_rifle_thug.tscn` (add `Ranged` + `FirearmFx` nodes; `NpcCharacter.ranged` is optional).
   - **M5a (crime):** `CrimeManager`, `WitnessComponent`, `HeatManager`. Crime definitions are `.tres`.
9. **Combat doesn't know about crime.** Combat reports hits and knockouts through signals: `MeleeCombat.hit_landed(attacker, victim, attack)` (also for landed shots), `MeleeCombat.shot_fired(shooter, weapon)` (every shot, M4b) and `HealthComponent.knocked_out(victim, by)` / `killed(victim, by)`, and `BodySearch.looted(victim, by)`. Every `MeleeCombat` is in the `combatants` group, so the M5a `CrimeManager` can find and connect to all of them; no crime or heat code goes into combat components.

### Physics layers (`project.godot` `[layer_names]`)

| Layer | Bit value | Name | Used by |
|---|---|---|---|
| 1 | 1 | world | static level geometry, doors (camera and LOS collide with this) |
| 2 | 2 | player | player body |
| 3 | 4 | props | RigidBody3D props |
| 4 | 8 | interactable | `Interactable` areas (detection only) |
| 5 | 16 | npc | NPCs and enemies |
| 6 | 32 | hitbox | `HitboxComponent` (attack volumes, detection only, mask = hurtbox) |
| 7 | 64 | hurtbox | `HurtboxComponent` (detection only) |
| 8 | 128 | ragdoll | knockout ragdoll bodies (collide with world, props, ragdoll; nothing collides with them) |

The player body mask is world + props + npc (NPC bodies: world + player + props + npc). Knocked-out characters set their body layer to 0 so others can walk through. The camera sweep hits only `world`, so small props don't make the camera jitter. The aim ray hits world + props + npc.

### Things that are easy to get wrong

- **Physics interpolation is on** (`physics/common/physics_interpolation`). Move gameplay bodies only in `_physics_process`. Anything that follows a body in `_process` (the camera rig) must set `physics_interpolation_mode = OFF` on itself and interpolate the body's position itself: sample it in `_physics_process` and lerp with `Engine.get_physics_interpolation_fraction()`. After teleporting a body, call `reset_physics_interpolation()`.
- **The camera sweeps for collisions itself**, in `CameraRig._process`, using shape casts. The `SpringArm3D` node is kept only to hold the arm's shape and mask, and its own processing is disabled: a physics-rate spring arm under a frame-rate rig jitters. It does two sweeps: pivot → shoulder (so the side offset doesn't clip in narrow corridors), then shoulder → camera.
- **The aim ray starts at the character's depth** along the camera ray, so geometry between the camera and the character (e.g. a cover edge) is ignored. `PlayerAim.is_obstructed` reports whether the line of fire from the chest is blocked. The HUD shows this as a red marker. Shots (`RangedCombat`) start at the same chest point (`origin_height` 1.45 = `PlayerAim.origin_height`; keep them equal) and hit hurtboxes (Area3D, layer 7), world and props, not character bodies.
- **Firearms:** with a firearm in hand `MeleeCombat.weapon` *is* the `FirearmData` (empty combo, so no melee attacks); `RangedCombat` only acts while `MeleeCombat.is_free()`. Weapon switches wait for `MeleeCombat.can_switch_weapon()`. A shot's `AttackData` uses only damage, reaction, guard and feel fields (`can_be_blocked = false`). The aim clips hold the rifle 28° left of the forward axis, so aiming turns the model by `FirearmData.aim_yaw_offset_degrees` (player and `RangedThugAI`). The reload's `reload` marker (magazine in) lives in `clip_data.json`. Rifle clip libraries are in both `player.tscn` and `thug.tscn` like every other clip.
- **Hurtbox height follows crouching** (`HurtboxComponent.set_height()`, connected to `PlayerMovement.crouched_changed` by the character root), so low cover hides a crouched body from shots. The hurtbox duplicates its capsule on first use, like the body.
- **`ModelFlash` clears its overlays in `_exit_tree`** (freeing a mesh with an overlay set makes the headless renderer print "material is null"), and leaves meshes under bone attachments (held weapons) alone.
- **Cover** keeps a fixed distance to the wall with a velocity override (no `move_and_slide` pushing into it) and stops at edges found by side rays. Cover objects must be on the `world` layer; the navigation mesh floats about 0.5 m above the floor in the arena, so code that samples navmesh points for line-of-sight checks (rifle thug cover search) flattens them to the body's height.
- **AnimationTree**: player and thug scenes each have an AnimationTree node (no AnimationPlayer, `root_node = ../Model/Character`). Its libraries are one per Mixamo clip file, keyed by clip name (`idle`, `walk`, … each holding one animation of the same name, so paths are `walk/walk`; clips with segments also hold `<clip>_<segment>`, e.g. `jump_standing/jump_standing_land`), plus `combat` (`combat_placeholder.tres`). **Every library must be listed in both `player.tscn` and `thug.tscn`.** Both scenes share the tree resource `assets/animations/humanoid_tree.tres` (parameters are per node, so sharing is safe), **generated by `scripts/tools/build_humanoid_tree.gd`**: change its tables and re-run instead of editing the tree in the editor (edits are lost on the next build). Its node names (`locomotion`, `locomotion_speed`, `strafe`, `strafe_speed`, `aim_blend`, `crouch`, `crouch_speed`, `crouch_blend`, `crouch_clip`, `crouch_shot`, `land_clip`, `land_shot`, `air_clip`, `air_blend`, `guard_clip`, `guard_blend`, `combat_clip`, `combat_speed`, `combat_blend`) are a contract with `PlayerAnimator`. The inputs of the `combat_clip` / `guard_clip` Transition nodes are named after the clips (`AttackData.clip`, `MeleeCombat` reaction clips, `WeaponData.guard_clip` / `ready_clip` refer to them); each input is fed by a node `clip_<name>`, and **that node decides which animation plays** (`COMBAT_CLIPS` / `GUARD_CLIPS` in the builder). `guard_blend` is filtered to every bone from `Spine` up, so the legs keep moving. `PlayerAnimator.play_combat_clip(clip, speed, hold)` plays a clip at a speed up to its `end` marker. Blend-space points sit at each clip's measured ground speed (walk 1.53, run 3.91, sprint 5.63; strafe fwd 2.26, back 1.32, left 2.06, right 2.18; crouch walk 1.28 m/s); `PlayerAnimator` speeds clips up (TimeScale) when moving faster than the outermost point, so `PlayerMovement` speeds can stay higher. New clip → measure its speed and move its point.
- **Clip timing lives in the clips (M4a.2).** Contact windows are animation markers (`hit`, `hit_end`, `end`, `recover`, `down`) written on import from `assets/animations/clip_data.json` (real clips, times in the source file's time line, before `trim`) or by the placeholder generator (`MARKERS`). Never put attack timing back into `AttackData`: tune `AttackData.speed` (≤ 1, so nothing plays faster than its clip) or move the marker. `clip_data.json` is **not an import dependency**: after editing it, reimport the clip (Import dock → Reimport; headless: delete `.godot/imported/<clip>.fbx-*` and run `--import`; deleting only the `.md5` does nothing).
- **Input buffer:** a press during an attack's windup/active phase waits until its recovery (the buffer only runs down after that), because windups are long now.
- **Hand-edited `.tscn` files:** a Node-typed `@export` (e.g. `@export var model: Node3D`) is only resolved if its name is listed in the node header, as in `[node name="Movement" ... node_paths=PackedStringArray("body", "model")]`. Without it the property stays null and nothing reports an error. Prefer assigning these in the editor.
- **Character bodies are never rotated.** `PlayerMovement` writes a *world* yaw into `model.rotation.y`, so only the `Model` node turns. Spawn and revive code sets the body position and turns the model (`EnemySpawner.spawn`, `Player.revive`); never assign a rotated `global_transform` to a character body.
- **Pause:** the inventory overlay sets `get_tree().paused` (temporary, GDD §12). Anything that must keep running while it is open needs `PROCESS_MODE_ALWAYS` (the HUD sets it on itself). Tests' `await get_tree().physics_frame` still advance while paused.
- **Crouch** resizes the body capsule: `PlayerMovement` duplicates the shape on the first crouch (the scene's `CapsuleShape3D` is shared between instances). The stand-up check is a `test_move` of the crouched capsule upwards. While crouched, `MeleeCombat.Intent.hold_actions` is set: combat input stays buffered and the player stands up first.
- **Get-up placement:** a recovering NPC is turned so the get-up clip's head direction matches the ragdoll's, and moved by `NpcCharacter.get_up_*_hips_offset` (where the clip's hips start) so the clip starts on the ragdoll. New get-up clips need those offsets measured (`analyze_clips.gd`).
- **Hit stop** (`HitStop`) slows the whole game through `Engine.time_scale` and ends with an unscaled `SceneTreeTimer`. Don't compare it against wall-clock time (fixed-fps runs and hitches desync it), and don't capture the timer in its own callback (reference cycle → every timer leaks). `HitStop.cancel()` on fight restarts.
- **Navigation**: the arena bakes with `NavigationBaker.bake_csg_boxes()` (CPU-side source geometry from `CSGBox3D` sizes). The engine's CSG parser reads meshes back from the GPU and finds nothing headless. Bake into a *new* `NavigationMesh` (re-assigning the region's own resource doesn't update the server), and the map syncs asynchronously: levels `await NavigationBaker.wait_for_region()` before spawning NPCs. Only *colliding* `CSGBox3D`s under the region are baked, and building roofs come out as unreachable navmesh islands (`CivilianAI` rejects flee goals at another height).
- **District layout** (`district.tscn`): solid geometry lives under `NavigationRegion3D/Geometry/` (`Buildings`: closed houses, fences, boundary; `Obstacles`: low objects and line-of-sight breakers). Roads, sidewalks, the plaza and reserved lots are flat boxes **without collision** under `Surface/` and `Lots/`, so they never form steps. The minimap draws whatever sits under the nodes listed in `District.minimap_layers`, so a new box in `Buildings` shows up on the map by itself. Reserved lots are walkable and marked with a "RESERVED" `Label3D`; build the M5b shops and the M6 warehouse on them.
- **NPC populations**: `EnemySpawner.start_population()` is called by the level once navigation is ready; a spawner with `population = 0` (the gym's) only spawns on request. Knocked-out NPCs still count towards the population. Civilians pick the nearest `WalkRoute` on their first tick, so put spawn markers on or near a route.
- **The character model faces +Z** (Mixamo); `Model/Character` is turned 180° in the scenes. Clips and the placeholder generator work in the skeleton's own space (+Z forward, character's right = −X).
- **Retargeted import**: models and clips import with `retarget/bone_map = mixamorig9_bone_map.tres`, so bones have humanoid names (`Hips`, `LeftUpperArm`, …) and the skeleton is the unique node `%GeneralSkeleton`; clip tracks are `%GeneralSkeleton:<Bone>`. Hips position tracks are stored divided by `Skeleton3D.motion_scale` (hip height) and scaled back on playback. A Mixamo download with another prefix (`mixamorig_`) needs its own map: `godot --headless --script res://scripts/tools/generate_mixamo_bone_map.gd -- mixamorig_`.
- **Character materials are external** (`assets/materials/characters/*.tres`, wired in `player.fbx.import` under `_subresources.materials`). The FBX importer's own materials came out untextured, taking their colour from vertex colours the mesh doesn't have (grey and see-through in game). A new model needs the same: one material per surface with its albedo and normal textures.
- **Keep GDScript warnings at zero.** The editor and VS Code's Problems panel show them; the debug console lists them when the game starts.
- **Ragdoll**: `RagdollComponent` builds `PhysicalBone3D`s under the skeleton at knockout (runtime, so the imported scene stays untouched) and frees them on revive.
- **Downed bodies**: a knocked-out NPC's `HurtboxComponent.follow` is set to the ragdoll's root body, so the standing-size hurtbox stays over the body and normal attacks still hit it (downed damage). Dead bodies disable the hurtbox. `apply_knockback` on a downed character goes to `RagdollComponent.apply_impulse`. On recovery `NpcCharacter` moves the body to where the ragdoll's pelvis lies before stopping the simulation. The player's hurtbox is still switched off when downed (thugs never attack downed targets).
- **Searching uses held interactions**: `InteractionComponent.try_interact()` ignores interactables with a `hold_time`; the player drives them through `update_hold()` each tick (only while combat is idle and on the floor), and is held in place meanwhile. A landed hit cancels it.
- **Weapon pickup scenes don't reference their `WeaponData`** (`bat.tres` → `pickup_scene` → `bat.tres` would be a cyclic load). Whoever spawns a pickup sets `pickup.weapon`.
- Stair stepping is done in code (`PlayerMovement._try_step_up`, `step_height` 0.35 m). Slopes up to `max_slope_degrees` (46°) are handled by `move_and_slide`. Rigid bodies are pushed, never stepped onto.

### Adding Mixamo clips (M2.1, M4a.1)

Download from Mixamo as FBX, 30 fps, **without skin**, **"In Place"** (the import removes leftover drift and prints its speed, but in-place is cleaner), for the same character as `player.fbx`.
1. Put the file in `assets/animations/mixamo/<clip>.fbx` (LFS) with a **snake_case name that says what the clip does** (`hit_react_face`, not `Receive Punch To The Face`); the file name becomes the clip name. Check what the clip really shows: Mixamo's left/right names can be wrong (`analyze_clips.gd -- <clip> --frames` shows which hand moves). Firearm clips start with `rifle_` / `grenade_`.
2. Give it the same import settings as the existing clips: copy a neighbouring `.fbx.import`, keep its own `uid` and `source_file` (or in the Import dock: *Animation Library*, skeleton retarget with the bone map of the download's prefix, post-import script `scripts/tools/mixamo_clip_post_import.gd`, and *Loop Mode* for looping clips). Check the bone prefix (the M4a downloads are `mixamorig12_`); a new prefix needs its own map (`generate_mixamo_bone_map.gd -- <prefix>`). Rename existing clips headlessly with `git mv` of both files and update `source_file` / `dest_files` / `path` in the `.import`. Commit the `.import` file.
3. Add the library to the AnimationTree `libraries` in **both** `scenes/player/player.tscn` and `scenes/npc/thug.tscn` under the clip's name.
4. Measure it: `analyze_clips.gd -- <clip> --frames`. Combat clips: add `hit` / `hit_end` (and `end` to cut a long tail, `trim` to cut a slow start) to `clip_data.json`; reactions: `recover`; reimport the clip. Locomotion: measure its ground speed and move its blend point.
5. Wire it in `scripts/tools/build_humanoid_tree.gd` (`COMBAT_CLIPS` / `GUARD_CLIPS` / blend-space tables) and re-run it; point an `AttackData.clip` or a `MeleeCombat` reaction export at the input name. Any other non-firearm clip shows up on F4 by itself after a rebuild.
6. Update `assets/animations/CLIPS.md`. Run the test suites; F4 in game plays every clip.

`Inventory.drop_origin` points at the same `Grip` socket as `Combat.weapon_socket` (right hand: knife and bat clips must strike with the right hand).

## Code style

- GDScript 2.0 with **static typing everywhere** (`var x: float`, `:=` where the type is obvious, typed arrays, typed signal arguments).
- `class_name` for reusable types. Use `##` doc comments on classes, exports and public methods.
- Member order (gdlint `class-definitions-order`): signals → enums → consts → `@export` → public vars → private `_vars` → `@onready` → methods (built-ins first, then public, then private).
- `snake_case` for files, functions and variables. `PascalCase` for classes and nodes. Use StringName literals (`&"action"`) for actions, groups and parameters.
- Format with `gdformat` and lint with `gdlint` (100-char lines). Keep both clean.

## Repository rules

- **Move or rename files only through Godot's FileSystem panel**, so references and `.uid` files stay in sync. **Commit `.uid` files.** `.godot/` is ignored.
- Binary assets go through **Git LFS**. Check `.gitattributes` before adding a new binary type.
- Scenes and resources are text (`.tscn`/`.tres`). Keep them diff-friendly and avoid embedding large binary data.
- When a design question comes up, update `docs/GDD.md` (with the right status tag) in the same PR as the code.
