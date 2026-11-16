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
| M1 | Character skeleton (GDD §12, M1.1–M1.7) | implemented, needs playtest and tuning in the editor |
| M2 | District and first crime (pickpocket → witness → report → heat 1) | next |
| — | **Gate:** define the Core Loop (GDD §5) before M3 | |
| M3 | Combat prototype | |
| M4 | First progression loop | |

Each milestone is built on its own branch and merged by PR. A task is done when its GDD "Done when" criterion works in the test level.

## Running

- Main scene: `res://scenes/levels/test_gym.tscn` (gray-box gym, M1.1).
- Controls (all bound in the InputMap, `project.godot` `[input]`): WASD move · Shift sprint · Ctrl walk · Space jump · RMB aim · Q swap shoulder · E interact · F3 debug overlay · Esc release mouse.
- Headless checks (CI or a cloud container):
  ```bash
  godot --headless --import            # (re)generate .godot/ cache and .uid files
  godot --headless --quit-after 120    # boot the main scene for ~2 s, watch for script errors
  ```
- Lint and format (gdtoolkit 4.x, `pip install "gdtoolkit==4.*"`). Config is in `gdlintrc`:
  ```bash
  gdformat scripts && gdlint scripts
  ```

## Folder structure

```
assets/        art and audio. Binary formats go through Git LFS (.gitattributes)
  animations/  AnimationLibrary resources (placeholder mannequin clips for now)
  materials/   .tres materials (gray-box grid ShaderMaterials, solid colours)
  shaders/     .gdshader files
  models/ textures/ audio/
data/          data-driven content as .tres/.json (items, later NPCs, crimes, ranks)
docs/          GDD and other design docs
scenes/        .tscn, by feature: player/, levels/, interactables/, props/, ui/
scripts/       .gd, mirrors scenes/ by feature:
  autoload/    global singletons (keep these few and small)
  camera/ components/ data/ interactables/ levels/ player/ ui/
```

Scenes and scripts are kept in parallel trees. Reusable building blocks (e.g. `Interactable`, `InteractionComponent`) go in `scripts/components/`.

## Architecture rules

1. **Components, not god scripts.** The player is a thin `CharacterBody3D` (`scripts/player/player.gd`) that reads input and passes **intent** to separate components: `PlayerMovement`, `CameraRig`, `PlayerAim`, `InteractionComponent`, `PlayerAnimator`. Components don't read `Input` directly (exceptions: the camera's mouse look, and UI). This lets NPC controllers drive the same components later.
2. **Explicit update order.** `Player._physics_process` calls components in a fixed order: aim → movement → interaction → animation. The camera rig runs in `_process`.
3. **No hardcoded keys.** Every input goes through an InputMap action. New actions go in `project.godot` `[input]`.
4. **Every tuning value is an `@export`** (grouped with `@export_group`) or lives in a Resource. No magic numbers in logic.
5. **Data-first content.** Items, crimes, NPC types, factions and ranks are Resources in `data/` (e.g. `ItemData` → `data/items/*.tres`), never hardcoded.
6. **No special cases in the player.** Interactive objects add an `Interactable` child (an Area3D on the `interactable` layer) and connect to its `interacted` signal. External effects use duck-typed methods such as `apply_knockback(impulse: Vector3)`.
7. **Signals up, calls down.** A parent calls methods on its children. Children report back through signals. `Events` (autoload, `scripts/autoload/events.gd`) is reserved for cross-cutting fire-and-forget events (UI notifications, later crime events).
8. Planned M2 systems from the GDD use these names: `CrimeManager`, `WitnessComponent`, `HeatManager`. Crime definitions are `.tres`.

### Physics layers (`project.godot` `[layer_names]`)

| Layer | Bit value | Name | Used by |
|---|---|---|---|
| 1 | 1 | world | static level geometry, doors (camera and LOS collide with this) |
| 2 | 2 | player | player body |
| 3 | 4 | props | RigidBody3D props |
| 4 | 8 | interactable | `Interactable` areas (detection only) |
| 5 | 16 | npc | NPCs (M2) |

The player body mask is world + props + npc. The camera sweep hits only `world`, so small props don't make the camera jitter. The aim ray hits world + props + npc.

### Things that are easy to get wrong

- **Physics interpolation is on** (`physics/common/physics_interpolation`). Move gameplay bodies only in `_physics_process`. Anything that follows a body in `_process` (the camera rig) must set `physics_interpolation_mode = OFF` on itself and interpolate the body's position itself: sample it in `_physics_process` and lerp with `Engine.get_physics_interpolation_fraction()`. Don't use `get_global_transform_interpolated()` for this. It returned a stale position in 4.7. After teleporting a body, call `reset_physics_interpolation()`.
- **The camera sweeps for collisions itself**, in `CameraRig._process`, using shape casts. The `SpringArm3D` node is kept only to hold the arm's shape and mask, and its own processing is disabled: a physics-rate spring arm under a frame-rate rig jitters. It does two sweeps: pivot → shoulder (so the side offset doesn't clip in narrow corridors), then shoulder → camera.
- **The aim ray starts at the character's depth** along the camera ray, so geometry between the camera and the character (e.g. a cover edge) is ignored. `PlayerAim.is_obstructed` reports whether the line of fire from the chest is blocked. The HUD shows this as a red marker.
- **AnimationTree** lives in `player.tscn`, holds the animation library itself (no AnimationPlayer) and uses `root_node = ../Model/Mannequin`. Its parameter names (`locomotion`, `strafe`, `aim_blend`, `air_blend`) are a contract with `PlayerAnimator`. Blend-space points sit at the speed each clip was authored for (walk 2.0, run 4.5, sprint 7.0, strafe 2.5 m/s, matching `PlayerMovement`), which prevents foot sliding. If you change a speed, move the point too.
- Stair stepping is done in code (`PlayerMovement._try_step_up`, `step_height` 0.35 m). Slopes up to `max_slope_degrees` (46°) are handled by `move_and_slide`. Rigid bodies are pushed, never stepped onto.

### Swapping in the Mixamo character (M1.7 follow-up)

The mannequin in `scenes/player/mannequin.tscn` is a primitive-mesh stand-in with procedurally authored clips (`assets/animations/mannequin_placeholder.tres`). To replace it:
1. Import the Mixamo FBX/GLB into `assets/models/` (it goes through LFS). Download the clips "In Place".
2. Replace the `Model/Mannequin` instance and point `AnimationTree.root_node` at the new model.
3. Put the new clips in an AnimationLibrary under the same names (`idle`, `walk`, `run`, `sprint`, `aim_idle`, `aim_forward`, `aim_backward`, `aim_left`, `aim_right`, `fall`), or rename the nodes in the tree.
4. Measure each clip's real ground speed and move its blend-space point to that speed.

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
