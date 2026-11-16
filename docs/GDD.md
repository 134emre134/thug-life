# Thug Life — Game Design Document

> Working title. Living document.
> **[Decided]** = settled · **[Proposal]** = suggested, awaiting approval · **[Open]** = needs brainstorming · **[Postponed]** = deliberately deferred

---

## 1. Overview [Decided]

- **Genre:** 3D sandbox action game with RPG elements
- **Premise:** The player starts as a low-level criminal and rises through the criminal hierarchy by whatever means they choose.
- **Camera:** Third-person, over-the-shoulder
- **Engine:** Godot 4.7, GDScript, Forward+ renderer
- **Platform:** PC (Windows) first; architecture should not block other platforms later

## 2. Tech Setup [Decided]

- **IDE:** VS Code + godot-tools extension
- **Version control:** GitHub, Git LFS for binary assets (.png, .wav, .ogg, .glb, .blend, .fbx, …)
- **Data-driven content:** items, NPCs, factions and ranks defined as data (`.tres` resources / JSON in `/data`), not hardcoded
- **File moves:** only via Godot's FileSystem panel; `.uid` files are committed

## 3. Design Pillars [Proposal]

1. **Your rise, your way** — multiple valid routes up the hierarchy (force, business, manipulation, loyalty/betrayal).
2. **The world reacts** — police and NPCs remember what the player did and respond to it.
3. **Weighty close-range action** — over-the-shoulder combat should feel physical. Fists and melee weapons are the primary way to solve problems and come first; firearms are an escalation added later.

## 4. Scope Strategy [Proposal]

Over-the-shoulder 3D is the expensive option; scope is controlled through world size, not camera.

- First playable = **one small, dense district**, not a full city
- Use existing animation/asset sources (e.g. Mixamo, asset store) for prototyping
- Build systems (police, ranks, economy) data-first so content can grow without code changes

## 5. Core Loop [Open]

_What does a typical 10-minute session look like?_ — **must be defined before M3 (District & first crime).** The M2 melee prototype is built in a test arena and doesn't depend on it.

## 6. Progression & Criminal Hierarchy [Open]

- Rank structure (names, number of tiers)
- How rank is gained: reputation, money, respect, kills, territory?
- RPG elements: stats, skills, perks, gear?

## 7. Combat

### Direction [Decided]
- **Melee first.** Fists and melee weapons are the fundamental problem-solving verb in this non-dialogue-heavy game. They get built and tuned before firearms (see §12: M2 melee, M4 firearms).

### Melee model [Proposal]
- **Readable, committal, physical** — closer to Sleeping Dogs than to a button-mashing brawler: every attack has a windup, active and recovery phase; hits land with hit stop, camera shake and a visible reaction.
- **Soft targeting, no hard lock-on:** attacks snap/lunge toward the best target in a cone in front of the camera (magnetism). The camera stays free.
- **Move set (player):** light attack combo (up to 3 hits) · heavy attack (hold) that breaks guard · guard (hold) · dodge/sidestep · weapon pickup and drop
- **Guard stance replaces aim mode while unarmed or holding a melee weapon:** same strafing/facing behaviour as M1.4 (reuses the strafe blend space), but blocks instead of aiming
- **No stamina** in the first version; guard is limited by guard break (heavy attacks) instead
- **Hit reactions** by severity: flinch (light) → stagger (heavy / combo finisher) → knockdown → knockout (ragdoll)
- **Group fights:** attack tokens: only 1–2 enemies attack at the same time, the others circle and wait. Required for readability over the shoulder.

### Weapons [Proposal]
- First set: **fists** + **one blunt weapon** (bat/pipe). Bladed weapons later, together with the lethality decision.
- Weapons are items (`WeaponData` extends `ItemData`), picked up via the M1.5 interaction, dropped on knockout.

### Still open [Open]
- **Lethal vs. non-lethal:** M2 ends every fight in a knockout. Whether and how the player can kill (and what that does to heat, reputation and witnesses) is decided at the Core Loop gate, together with the crime system.
- **Cover system:** only relevant for firearms; decide before M4.
- Melee vs. firearms balance (M4).
- Stealth takedowns, finishers, environmental attacks (later; must not be designed out).

## 8. Police & Crime [Proposal]

Early-game focus: the individual player gets hunted for small crimes.

### Core principle: police only know what was reported
No omniscient wanted level. Every crime passes through a chain the player can interrupt:

1. **Crime** — emits a crime event with a severity
2. **Witness** — NPC with field of view sees it and reacts (flee / call police / film)
3. **Report** — the call takes a few seconds; intimidating the witness or breaking line of sight in time prevents it
4. **Response** — police search the **last known position**, not the player's live location

### Heat levels (capped at 3 in the early game)

| Level | Triggers | Response |
|---|---|---|
| 1 – Suspicion | Pickpocketing, shoplifting, vandalism | Patrol checks the scene, questions NPCs |
| 2 – Pursuit | Car theft, assault, resisting arrest | Foot/vehicle pursuit, search area around last sighting |
| 3 – Manhunt | Armed robbery, firearm use | More units, roadblocks, district lockdown |

### Evasion & identity
- **Description instead of radar:** police search for a description ("red jacket, cap"); changing clothes, leaving main streets and breaking line of sight all help
- **Search radius** shrinks over time; staying hidden long enough ends the search

### Consequences
- **Arrest, not death,** is the default fail state for small crimes: lose cash and confiscated items, time skip
- **Criminal record:** known faces are recognized faster; record decays slowly
- Bribes and lawyers later as progression rewards

### Satire touch (light)
- Filming witnesses add extra heat
- "Quota week" = more patrols, delivered via radio/flavor text

### Godot structure
- `CrimeManager` — receives crime events
- `WitnessComponent` — on NPCs, perception + reaction
- `HeatManager` — heat level, search area, decay
- Crime definitions as `.tres` data (severity, base heat, witness radius)

**First vertical slice:** pickpocketing + heat level 1 (M3).

## 9. World & Setting

- **[Decided]** Fictional district as the starting point, set in the present day
- **[Decided]** Tone: lively, with a touch of satire
- **[Proposal]** District concept: old harbour district *Brickhaven*, being rebranded by developers as "BRIX – The Creative Quarter"; satire aimed upward (systems, corporations, trends, authorities), never at ethnic groups or the poor
- **[Proposal]** City internationally readable (English names, no explicit country), European grit visually
- **[Proposal]** Satire delivered cheaply via text/audio: billboards, radio, NPC chatter, in-game social feed

## 10. Factions & NPCs [Postponed]

Early game focuses on the player's individual character, not faction influence. Revisit after the first progression loop.

- Rival gangs, civilians
- Joining vs. founding a faction

## 11. Economy [Open]

- Income sources (jobs, rackets, businesses)
- Money sinks

## 12. Milestones [Decided: order]

Rationale: build the gameplay skeleton (movement, aiming, interaction) first, then the core verb: fists and melee weapons are how problems get solved in this game, so their feel has to hit the mark before anything is built on top of them. The police/witness system follows and gets real crimes to react to (assault, not only pickpocketing). Firearms are an escalation on top of a working melee system.

| # | Milestone | Content |
|---|-----------|---------|
| M0 | Setup | Godot, VS Code, GitHub, folder structure ✅ |
| M1 | Character skeleton | Locomotion, camera, aim mode, interaction, basic physics, placeholder animation — in a gray-box test level 🔧 (implemented; Mixamo model + playtest tuning pending) |
| M2 | Melee combat | Fists + one blunt weapon, guard/dodge, hit reactions, knockout ragdolls, one melee enemy type with group behaviour — in a combat arena 🔧 (implemented on placeholder clips; Mixamo swap + playtest tuning pending) |
| — | _Gate_ | _Define Core Loop (§5) and lethality (§7) before M3_ |
| M3 | District & first crime | Block-out district, walking NPCs, pickpocketing → witness → report → heat level 1 |
| M4 | Firearms | One firearm, cover decision (§7), ranged enemy behaviour, firearm use → heat |
| M5 | First progression loop | One job type → money/reputation → first rank-up |

### M1 — Character skeleton [Proposal: details]

Tasks are listed in implementation order. Each one is done when it works in the test level.

| Task | Content | Done when |
|---|---|---|
| M1.1 Test level | Gray-box "gym": flat area, ramps, stairs, narrow corridor, walls/low cover, physics props, test interactables | Scene loads with the player spawned in it |
| M1.2 Locomotion | `CharacterBody3D`; walk / run / sprint with acceleration and deceleration; slopes and stairs; character turns toward movement direction | Moving through the whole gym feels responsive, no snagging on stairs/edges |
| M1.3 Camera | `SpringArm3D` over-the-shoulder rig; mouse look with sensitivity and pitch clamp; shoulder swap; collision without clipping or jitter | Camera never goes through walls in the corridor; shoulder swap is smooth |
| M1.4 Aim mode | Hold to aim: camera moves closer + lower FOV (tweened); character faces the aim direction and strafes; slower movement; crosshair; aim target = raycast from the camera center | The crosshair point is correct at close and far distances, including behind cover edges |
| M1.5 Interaction | Reusable `Interactable` component; detects the best target in front of the player; on-screen prompt; test objects: door, pickup, button | All three test objects work through the same component, with no special-case code in the player |
| M1.6 Physics | Player pushes `RigidBody3D` props; `apply_knockback(impulse)` on the player | Props react plausibly; knockback can be triggered from a test object |
| M1.7 Animation | Mixamo placeholder model; `AnimationTree` with a locomotion blend space plus an aim/strafe blend space | Animation matches speed and direction, without foot sliding at normal speeds |

**Applies to the whole milestone:**
- All tuning values (speeds, acceleration, camera offsets, FOVs, sensitivity) are `@export` variables or live in a resource, so they can be tuned without code changes
- All inputs go through the InputMap; no hardcoded keys
- Components stay separate (movement, camera, aim, interaction) instead of one large player script

**Out of scope for M1:** firing weapons, melee, ragdolls, hit reactions, crouch/cover (cover is still open, see §7), vehicles.

### M2 — Melee combat [Proposal: details]

Goal: one-on-one and one-against-three fights with fists and a bat feel weighty and readable. Tasks are listed in implementation order.

| Task | Content | Done when |
|---|---|---|
| M2.1 Character & combat animations | Finish the M1.7 follow-up: Mixamo character replaces the mannequin. Add in-place clips for light combo (3), heavy, guard, dodge, hit reactions (flinch/stagger/knockdown), get-up; unarmed and bat variants. `AnimationTree` gets a combat layer (one-shot/state machine on top of locomotion) | All combat clips play from a debug key on the new model; locomotion still meets the M1.7 criterion |
| M2.2 Health & damage | Reusable `HealthComponent` (health, knocked-out state, signals); `HitboxComponent` / `HurtboxComponent` (Area3D, new physics layers); `AttackData` resource (damage, reaction severity, knockback impulse, windup/active/recovery times, lunge distance, clip name) in `data/attacks/` | A test dummy takes damage and shows reactions; all attack values are tunable in `.tres` files |
| M2.3 Combat component | `MeleeCombat` component driven by intent (light, heavy, guard, dodge), like `PlayerMovement`: attack phases, combo window, input buffering, cancel rules (dodge cancels recovery), lunge toward the soft target | Full combo, heavy, guard and dodge chain without dropped inputs |
| M2.4 Soft targeting | Best target in a cone around the camera direction (distance + angle score); attack rotates/lunges toward it; no target = attack in camera direction | Attacks reliably connect with the intended enemy out of three, without a lock-on button |
| M2.5 Hit feel | Hit stop (per `AttackData`), camera shake, hit reactions by severity, knockout → ragdoll (physical bones), placeholder hit sounds | A heavy hit is clearly distinguishable from a light one, both by sound alone and with sound off |
| M2.6 Melee weapon | `WeaponData` extends `ItemData`; bat pickup via `Interactable`; own `AttackData` set; dropped on knockout | Picking up the bat changes reach, timing and damage with no special-case code in the player |
| M2.7 Enemy AI | One thug type: `NavigationAgent3D`; approach → circle → attack with clear telegraph → occasional guard; drives the **same** `PlayerMovement` and `MeleeCombat` components through an NPC controller; `CombatDirector` hands out attack tokens (max 1–2 attackers) | A 1 vs. 3 fight is readable: never more than 2 attack at once, every attack can be seen coming |
| M2.8 Combat arena | `combat_gym.tscn`: open area, narrow alley, props to knock around, enemy spawner, debug overlay (health, attack phase, current target) | Scene loads; fights can be restarted without reloading |

**Applies to the whole milestone:**
- Same rules as M1: tuning values in `@export`s or resources, inputs via InputMap, separate components
- New inputs: `attack_light`, `attack_heavy` (may share a button with hold detection), `guard`, `dodge`. Proposed default: LMB attack (hold = heavy), RMB guard (replaces aim while unarmed/melee), dodge = jump key while guarding. Final bindings are decided in playtest
- Combat emits signals (`hit_landed(attacker, victim, attack)`, `knocked_out(victim, by)`) so the M3 `CrimeManager` can turn them into assault crime events without changing combat code
- Player, enemies and later civilians/police share the same health, hurtbox and combat components

**Out of scope for M2:** firearms, killing/lethal outcomes (§7 open), crime/heat integration (M3), stealth takedowns, finishers, stamina, skills/perks, bladed weapons, more than one enemy type.

#### M2 implementation notes [Proposal: awaiting playtest]

What was built, and where it deviates from the table above. All numbers are starting values in `.tres`/`@export`s, to be tuned in playtest.

- **Deviation — M2.1 still uses the mannequin.** The Mixamo character and clips need an Adobe login and were not imported. All combat clips exist as procedural placeholders on the primitive mannequin (light combo ×3, heavy, guard, dodge, flinch, stagger, knockdown, get-up; unarmed and bat), in a combat layer on the AnimationTree, and play from a debug key (F4). The swap steps are in `CLAUDE.md`.
- **Deviation — ragdoll without physical bones.** The mannequin has no skeleton, so knockouts spawn a rigid-body ragdoll built from the mannequin's parts (7 bodies, cone-twist joints). It switches to `PhysicalBoneSimulator3D` with the Mixamo skeleton.
- **Bindings (proposed defaults kept):** LMB tap = light (fires on release), LMB hold 0.28 s = heavy, RMB = guard, Space while guarding = dodge (otherwise jump), G = drop weapon. **Added:** MMB = heavy directly (`attack_heavy`), so heavies don't wait for the hold time.
- **Attack flow:** windup → active → recovery per `AttackData`. The next light attack chains during recovery or up to 0.25 s after it; one action is buffered for 0.3 s. Dodge cancels recovery. Attacks lunge toward the soft target (stop just inside reach) or step 0.25–0.4 m without one.
- **Soft targeting:** best enemy within 5 m and ±60° of the camera direction, scored by angle and distance with a small bonus for the current target. A marker shows the current soft target.
- **Guard:** blocks hits from a 150° front arc (no damage, half knockback, 0.15 s block stun). Heavy attacks break guard: 50% damage and a 0.9 s stagger.
- **Dodge:** 2.4 m in 0.35 s in the move direction (backwards without input), invulnerable for the first 0.25 s.
- **Reactions:** flinch 0.35 s → stagger 0.75 s → knockdown (fall 0.5 s, down 1.0 s, get-up 0.9 s, can't be hit while down) → knockout (ragdoll). Hits interrupt attacks (no hyper armour yet).
- **Hit feel:** global hit stop (time scale 0.05 for 45–150 ms per attack), camera shake (trauma model), white/yellow hit flash, knockback impulse, and synthesized placeholder sounds: short bright slap (light), long deep thud (heavy/knockout), dry clack (block). `AttackData.hit_sound` overrides.
- **Numbers:** player 150 HP, thug 100 HP, training dummy 400 HP. Fists 8/8/14, heavy 20 (reach 0.8 m). Bat 14/14/22, heavy 32 (reach 1.25–1.35 m, slower windups, finisher and heavy knock down).
- **Enemy (thug):** own move set (`thug_fists`): jab with a 0.5 s windup, hook 0.38 s, heavy 0.75 s (breaks guard, knocks down). Attacks commit their direction at the start of the windup and the thug glows red during every windup. Approaches with navigation, circles at 3.2 m and spreads out around the player (about 70° apart), attacks only with a `CombatDirector` token (max 2 at once, at least 0.6 s between grants, 1.4 s cooldown per thug), backs off after 1–2 hits or a heavy (20%), guards against 35% of the attacks aimed at it. Thugs don't pick up weapons.
- **Arena (`combat_gym.tscn`, now the main scene):** open area with cover and pillars, a 2.4 m wide alley, crates and barrels, two bats. F5 restarts the fight, F6 cycles 1 vs 3 → 1 vs 1 → training dummy (doesn't fight back). F3 shows health, state, attack phase, target and tokens for the player and above each thug.
- **Tests:** `tests/combat_tests.tscn` checks the "Done when" criteria headless (combo, buffering, heavy, guard/break, dodge, targeting out of three, bat, knockdown, knockout/drop/ragdoll, max 2 attackers over 25 s of 1 vs 3, navigation, restart, M1 regression). Feel and readability still need a human playtest.

### M3 — District & first crime [Proposal: details]

| Task | Content |
|---|---|
| M3.1 District block-out | Small part of Brickhaven in gray-box: a few streets, a square, alleys, enough line-of-sight breakers |
| M3.2 NPC walkers | `NavigationAgent3D` civilians following simple routines (walk between points, idle); builds on the M2.7 NPC controller |
| M3.3 Crime events | `CrimeManager` + crime definitions as `.tres`; pickpocketing as an interaction (built on M1.5) |
| M3.4 Witnesses | `WitnessComponent`: field of view + line of sight; reactions: flee / call police; the report timer can be interrupted |
| M3.5 Heat level 1 | `HeatManager`: heat level, last known position, search radius that shrinks over time |
| M3.6 Police response | One patrol unit walks to the last known position and searches the area; minimal arrest = cash lost + respawn |

**Done when:** the full chain plays out in the district: pickpocket → seen or unseen → report or prevented → patrol searches → escape or get arrested.

## 13. Technical Risks (3D, over-the-shoulder)

- Camera collision and aiming feel
- Character animation volume (locomotion, combat, NPCs); melee feel depends heavily on clip quality, and Mixamo's melee/bat selection is limited
- NPC crowds and AI performance (incl. witness perception checks)
- World streaming / LOD once the map grows beyond one district
