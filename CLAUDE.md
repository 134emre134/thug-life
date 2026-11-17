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
| M3b | District (GDD §19 M3b): gray-box Brickhaven, district gym, civilians that panic and can be fought/looted, thug spawns, basic minimap; no police, crime or cars | |
| M4a | Combat update (GDD §7, §19 M4a): animation pass, clip-driven attack timing, feel tuning, crouch, stomp, inventory pauses the game | |
| M4b | Firearms (GDD §7, §19 M4b): one firearm, ammo, weapon switching, sticky cover, ranged enemy | |
| — | **Gate:** define the Core Loop (GDD §5) before M5a | |
| M5a | Crime fundamentals (GDD §8, §19 M5a): pickpocket → witness → report → heat 1, police patrol, arrest, firearm use → heat | |
| M5b | First progression loop (shop robbery, shops, interiors, `WorldClock`, heat 2, first rank-up) | |
| M6 | Nightlife (day/night cycle, fight club) | |
| M7–M9 | Customization, second district + cars, vehicle roster (GDD §17, §18) | |

Each milestone is built on its own branch and merged by PR. A task is done when its GDD "Done when" criterion works in the test level.

## Running

- Main scene: `res://scenes/levels/combat_gym.tscn` (M2.8 combat arena, extended in M3a: mixed NPC types with loot, bats and a knife). The M1 gym `res://scenes/levels/test_gym.tscn` still works (open it and press F6).
- Controls (all bound in the InputMap, `project.godot` `[input]`): WASD move · Shift sprint · Ctrl walk · Space jump · LMB attack (tap = light, hold 0.28 s = heavy) · MMB heavy · RMB guard · Space while guarding = dodge · E interact / pick up (hold E: search a body) · G drop weapon · H holster/draw weapon · Tab inventory overlay · Q swap shoulder · F3 debug overlay (also floating labels on NPCs) · F4 play the next combat clip (debug) · F5 restart fight · F6 next fight mode (1 vs 3 → 1 vs 1 → training dummy) · Esc release mouse.
- RMB is **guard** while unarmed or holding a melee weapon; aim mode is only used with firearms (M4b). `PlayerAim` is kept intact (it is updated with `wants_aim = false`); it is needed again in M4b. The M2 bindings and their deviations from the proposal are in GDD §19, "M2 implementation notes".
- Headless checks (CI or a cloud container):
  ```bash
  godot --headless --import            # (re)generate .godot/ cache and .uid files
  godot --headless --quit-after 120    # boot the main scene for ~2 s, watch for script errors
  godot --headless --fixed-fps 60 res://tests/combat_tests.tscn   # M2 test suite, exit code 0 = pass
  godot --headless --fixed-fps 60 res://tests/m3a_tests.tscn      # M3a test suite, exit code 0 = pass
  ```
  The test suites load the real arena and drive the real player through the InputMap (`Input.action_press`). Headless can't capture the mouse, so it sets `Player.require_mouse_capture = false`.
- Placeholder combat clips are generated for the character skeleton: `godot --headless --script res://scripts/tools/generate_combat_clips.gd` rewrites `assets/animations/combat_placeholder.tres` (needs the model imported first).
- Lint and format (gdtoolkit 4.x, `pip install "gdtoolkit==4.*"`). Config is in `gdlintrc`:
  ```bash
  gdformat scripts tests && gdlint scripts tests
  ```

## Folder structure

```
assets/        art and audio. Binary formats go through Git LFS (.gitattributes)
  animations/  humanoid_tree.tres (shared AnimationTree), combat_placeholder.tres (generated),
               mixamorig9_bone_map.tres (retarget map), mixamo/*.fbx (one clip per file)
  materials/   .tres materials (gray-box grid ShaderMaterials, solid colours);
               characters/ = external materials of the character model
  shaders/     .gdshader files
  models/      character models (player.fbx and the textures extracted from it on import)
  textures/ audio/
data/          data-driven content as .tres/.json
  attacks/     AttackData (one per punch/swing/stab)
  items/       ItemData and WeaponData (fists, thug_fists, bat, knife, pocket items)
  loot/        LootTable per NPC type (thug, collector)
docs/          GDD and other design docs
scenes/        .tscn, by feature: player/, npc/, levels/, interactables/, props/, ui/
scripts/       .gd, mirrors scenes/ by feature:
  autoload/    global singletons (keep these few and small)
  camera/ components/ data/ interactables/ levels/ npc/ player/ ui/
  tools/       editor/CLI generators (not used at runtime)
tests/         headless test scenes (combat_tests.tscn, m3a_tests.tscn)
```

Scenes and scripts are kept in parallel trees. Reusable building blocks (e.g. `Interactable`, `InteractionComponent`) go in `scripts/components/`.

## Architecture rules

1. **Components, not god scripts.** The player is a thin `CharacterBody3D` (`scripts/player/player.gd`) that reads input and passes **intent** to separate components: `PlayerMovement`, `CameraRig`, `PlayerAim`, `InteractionComponent`, `PlayerAnimator`. Components don't read `Input` directly (exceptions: the camera's mouse look, and UI). This lets NPC controllers drive the same components: from M2 on, enemies use the same movement, health and combat components as the player. (`PlayerMovement` keeps its name for now; renaming it means a move through the Godot editor, so do it only when asked.)
2. **Explicit update order.** `Player._physics_process` calls components in a fixed order: aim → movement → interaction → animation. From M2, combat runs before movement (aim/guard → combat → movement → interaction → animation), because attacks lock or drive movement (lunge). The camera rig runs in `_process`.
3. **No hardcoded keys.** Every input goes through an InputMap action. New actions go in `project.godot` `[input]`.
4. **Every tuning value is an `@export`** (grouped with `@export_group`) or lives in a Resource. No magic numbers in logic.
5. **Data-first content.** Items, crimes, NPC types, factions and ranks are Resources in `data/` (e.g. `ItemData` → `data/items/*.tres`), never hardcoded.
6. **No special cases in the player.** Interactive objects add an `Interactable` child (an Area3D on the `interactable` layer) and connect to its `interacted` signal. External effects use duck-typed methods such as `apply_knockback(impulse: Vector3)`.
7. **Signals up, calls down.** A parent calls methods on its children. Children report back through signals. `Events` (autoload, `scripts/autoload/events.gd`) is reserved for cross-cutting fire-and-forget events (UI notifications, later crime events).
8. System names from the GDD:
   - **M2 (melee, implemented):** `HealthComponent`, `HitboxComponent` (attacker's damaging volume), `HurtboxComponent` (where a character can be hit), `MeleeCombat`, `SoftTargeting`, `CombatDirector` (attack tokens), `RagdollComponent`, `ModelFlash`, `CombatAudio`, `HitStop`; NPC side `NpcCharacter` (thin body) + `ThugAI` (controller). Resources `AttackData` (`data/attacks/*.tres`) and `WeaponData` (extends `ItemData`, `data/items/`). `MeleeCombat` takes a `MeleeCombat.Intent` each tick, like `PlayerMovement`, and changes movement only by editing the movement intent in `apply_to_movement()` (lock, lunge/dodge velocity override, guard strafing). Animation requests go up as `clip_requested` / `clip_stopped` signals; the character root connects them to its `PlayerAnimator`.
   - **M3a (inventory/loot, implemented):** `InventoryComponent` (melee slot drawn/holstered, firearm slot locked until M4b, pocket slots, wallet; owns weapons and drops them: `MeleeCombat` only holds what `set_weapon()` puts in hand), `LootTable` + `LootEntry` (`data/loot/*.tres`, rolled into an NPC's inventory on spawn), `BodySearch` (hold-to-search `Interactable` on a downed body, emits `looted(victim, by)`). `HealthComponent` states `ACTIVE` → `KNOCKED_OUT` → `DEAD` with downed damage and a knockout recovery timer; `AttackData.damage_type` (blunt knocks out, blade/firearm kill). `Interactable.hold_time` + `InteractionComponent.update_hold()` for held interactions. Pickups hand items over through a duck-typed `receive_item(item) -> bool`; searches find the interactor's inventory through `get_inventory()`. NPC types are scene variants for now (`scenes/npc/collector.tscn` inherits `thug.tscn`), each with its own `LootTable`.
   - **M5a (crime):** `CrimeManager`, `WitnessComponent`, `HeatManager`. Crime definitions are `.tres`.
9. **Combat doesn't know about crime.** Combat reports hits and knockouts through signals: `MeleeCombat.hit_landed(attacker, victim, attack)` and `HealthComponent.knocked_out(victim, by)` / `killed(victim, by)`, and `BodySearch.looted(victim, by)`. Every `MeleeCombat` is in the `combatants` group, so the M5a `CrimeManager` can find and connect to all of them; no crime or heat code goes into combat components.

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
- **The aim ray starts at the character's depth** along the camera ray, so geometry between the camera and the character (e.g. a cover edge) is ignored. `PlayerAim.is_obstructed` reports whether the line of fire from the chest is blocked. The HUD shows this as a red marker.
- **AnimationTree**: player and thug scenes each have an AnimationTree node (no AnimationPlayer, `root_node = ../Model/Character`). Its libraries are one per Mixamo clip file, keyed by clip name (`idle`, `walk`, … each holding one animation of the same name, so paths are `walk/walk`), plus `combat` (`combat_placeholder.tres`). Both scenes share the tree resource `assets/animations/humanoid_tree.tres` (parameters are per node, so sharing is safe). Its node names (`locomotion`, `locomotion_speed`, `strafe`, `strafe_speed`, `aim_blend`, `air_blend`, `guard_clip`, `guard_blend`, `combat_clip`, `combat_speed`, `combat_blend`) are a contract with `PlayerAnimator`. The inputs of the `combat_clip` / `guard_clip` Transition nodes are named after the clips (`AttackData.clip`, `WeaponData.guard_clip` / `ready_clip` refer to them); each input is fed by a node `clip_<name>`, and **that node decides which animation plays**, so swapping a placeholder for a real clip means changing its `animation` (`combat/punch_1` → `punch_1/punch_1`). `guard_blend` is filtered to every bone from `Spine` up, so the legs keep moving. `PlayerAnimator.play_combat_clip` time-stretches a clip so `AttackData.clip_hit_time` lines up with the start of the active phase. Blend-space points sit at each clip's measured ground speed (walk 1.53, run 3.91, sprint 5.63; strafe fwd 2.26, back 1.32, left 2.06, right 2.18 m/s); `PlayerAnimator` speeds clips up (TimeScale) when moving faster than the outermost point, so `PlayerMovement` speeds can stay higher. New clip → measure its speed and move its point.
- **Hand-edited `.tscn` files:** a Node-typed `@export` (e.g. `@export var model: Node3D`) is only resolved if its name is listed in the node header, as in `[node name="Movement" ... node_paths=PackedStringArray("body", "model")]`. Without it the property stays null and nothing reports an error. Prefer assigning these in the editor.
- **Character bodies are never rotated.** `PlayerMovement` writes a *world* yaw into `model.rotation.y`, so only the `Model` node turns. Spawn and revive code sets the body position and turns the model (`EnemySpawner.spawn`, `Player.revive`); never assign a rotated `global_transform` to a character body.
- **Hit stop** (`HitStop`) slows the whole game through `Engine.time_scale` and ends with an unscaled `SceneTreeTimer`. Don't compare it against wall-clock time (fixed-fps runs and hitches desync it), and don't capture the timer in its own callback (reference cycle → every timer leaks). `HitStop.cancel()` on fight restarts.
- **Navigation**: the arena bakes with `NavigationBaker.bake_csg_boxes()` (CPU-side source geometry from `CSGBox3D` sizes). The engine's CSG parser reads meshes back from the GPU and finds nothing headless. Bake into a *new* `NavigationMesh` (re-assigning the region's own resource doesn't update the server), and the map syncs asynchronously: `combat_gym.gd` waits until the region owns the map before spawning NPCs.
- **The character model faces +Z** (Mixamo); `Model/Character` is turned 180° in the scenes. Clips and the placeholder generator work in the skeleton's own space (+Z forward, character's right = −X).
- **Retargeted import**: models and clips import with `retarget/bone_map = mixamorig9_bone_map.tres`, so bones have humanoid names (`Hips`, `LeftUpperArm`, …) and the skeleton is the unique node `%GeneralSkeleton`; clip tracks are `%GeneralSkeleton:<Bone>`. Hips position tracks are stored divided by `Skeleton3D.motion_scale` (hip height) and scaled back on playback. A Mixamo download with another prefix (`mixamorig_`) needs its own map: `godot --headless --script res://scripts/tools/generate_mixamo_bone_map.gd -- mixamorig_`.
- **Character materials are external** (`assets/materials/characters/*.tres`, wired in `player.fbx.import` under `_subresources.materials`). The FBX importer's own materials came out untextured, taking their colour from vertex colours the mesh doesn't have (grey and see-through in game). A new model needs the same: one material per surface with its albedo and normal textures.
- **Keep GDScript warnings at zero.** The editor and VS Code's Problems panel show them; the debug console lists them when the game starts.
- **Ragdoll**: `RagdollComponent` builds `PhysicalBone3D`s under the skeleton at knockout (runtime, so the imported scene stays untouched) and frees them on revive.
- **Downed bodies**: a knocked-out NPC's `HurtboxComponent.follow` is set to the ragdoll's root body, so the standing-size hurtbox stays over the body and normal attacks still hit it (downed damage). Dead bodies disable the hurtbox. `apply_knockback` on a downed character goes to `RagdollComponent.apply_impulse`. On recovery `NpcCharacter` moves the body to where the ragdoll's pelvis lies before stopping the simulation. The player's hurtbox is still switched off when downed (thugs never attack downed targets).
- **Searching uses held interactions**: `InteractionComponent.try_interact()` ignores interactables with a `hold_time`; the player drives them through `update_hold()` each tick (only while combat is idle and on the floor), and is held in place meanwhile. A landed hit cancels it.
- **Weapon pickup scenes don't reference their `WeaponData`** (`bat.tres` → `pickup_scene` → `bat.tres` would be a cyclic load). Whoever spawns a pickup sets `pickup.weapon`.
- Stair stepping is done in code (`PlayerMovement._try_step_up`, `step_height` 0.35 m). Slopes up to `max_slope_degrees` (46°) are handled by `move_and_slide`. Rigid bodies are pushed, never stepped onto.

### Adding Mixamo clips (M2.1)

Download from Mixamo as FBX, 30 fps, **without skin**, **"In Place"** (the import removes leftover drift and prints its speed, but in-place is cleaner), for the same character as `player.fbx`.
1. Put the file in `assets/animations/mixamo/<clip>.fbx` (LFS). The file name becomes the clip name.
2. Give it the same import settings as the existing clips: copy a neighbouring `.fbx.import`, keep its own `uid` and `source_file` (or in the Import dock: *Animation Library*, skeleton retarget with `mixamorig9_bone_map.tres`, post-import script `scripts/tools/mixamo_clip_post_import.gd`, and *Loop Mode* for looping clips). Commit the `.import` file.
3. Add the library to the AnimationTree `libraries` in **both** `scenes/player/player.tscn` and `scenes/npc/thug.tscn` under the clip's name.
4. Point the tree node at it: for a combat clip, set `clip_<name>.animation` to `<clip>/<clip>` in `humanoid_tree.tres`; for a new clip name, add a `combat_clip` input and an `AttackData.clip` referencing it.
5. Combat clips: set `AttackData.clip_hit_time` to the clip's contact time. Locomotion: measure its ground speed and move its blend point.
6. Run the test suites; F4 in game plays every combat clip.

The knife (M3a) reuses the punch clips until it gets its own. `Inventory.drop_origin` points at the same `Grip` socket as `Combat.weapon_socket`.

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
