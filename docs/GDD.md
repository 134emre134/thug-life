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
3. **Weighty close-range action** — over-the-shoulder combat should feel physical: melee and firearms, cover, impact.

## 4. Scope Strategy [Proposal]

Over-the-shoulder 3D is the expensive option; scope is controlled through world size, not camera.

- First playable = **one small, dense district**, not a full city
- Use existing animation/asset sources (e.g. Mixamo, asset store) for prototyping
- Build systems (police, ranks, economy) data-first so content can grow without code changes

## 5. Core Loop [Open]

_What does a typical 10-minute session look like?_ — **must be defined before M3 (Combat).**

## 6. Progression & Criminal Hierarchy [Open]

- Rank structure (names, number of tiers)
- How rank is gained: reputation, money, respect, kills, territory?
- RPG elements: stats, skills, perks, gear?

## 7. Combat [Open]

- Melee vs. firearms balance
- Cover system yes/no
- Lethal vs. non-lethal options, consequences

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

**First vertical slice:** pickpocketing + heat level 1 (fits M2).

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

Rationale: build the gameplay skeleton (movement, aiming, interaction) first, then validate the unique pillar (police/witness system) before investing in generic, expensive combat.

| # | Milestone | Content |
|---|-----------|---------|
| M0 | Setup | Godot, VS Code, GitHub, folder structure ✅ |
| M1 | Character skeleton | Locomotion, camera, aim mode, interaction, basic physics, placeholder animation — in a gray-box test level 🔧 (implemented; Mixamo model + playtest tuning pending) |
| M2 | District & first crime | Block-out district, walking NPCs, pickpocketing → witness → report → heat level 1 |
| — | _Gate_ | _Define Core Loop (§5) before M3_ |
| M3 | Combat prototype | One melee + one firearm, hit reactions, ragdolls, basic enemy AI |
| M4 | First progression loop | One job type → money/reputation → first rank-up |

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

### M2 — District & first crime [Proposal: details]

| Task | Content |
|---|---|
| M2.1 District block-out | Small part of Brickhaven in gray-box: a few streets, a square, alleys, enough line-of-sight breakers |
| M2.2 NPC walkers | `NavigationAgent3D` civilians following simple routines (walk between points, idle) |
| M2.3 Crime events | `CrimeManager` + crime definitions as `.tres`; pickpocketing as an interaction (built on M1.5) |
| M2.4 Witnesses | `WitnessComponent`: field of view + line of sight; reactions: flee / call police; the report timer can be interrupted |
| M2.5 Heat level 1 | `HeatManager`: heat level, last known position, search radius that shrinks over time |
| M2.6 Police response | One patrol unit walks to the last known position and searches the area; minimal arrest = cash lost + respawn |

**Done when:** the full chain plays out in the district: pickpocket → seen or unseen → report or prevented → patrol searches → escape or get arrested.

## 13. Technical Risks (3D, over-the-shoulder)

- Camera collision and aiming feel
- Character animation volume (locomotion, combat, NPCs)
- NPC crowds and AI performance (incl. witness perception checks)
- World streaming / LOD once the map grows beyond one district
