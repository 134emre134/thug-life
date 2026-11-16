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

_What does a typical 10-minute session look like?_ — **must be defined before M3b (District & first crime).** The M2 melee prototype and M3a (inventory, loot & lethality) are built in the combat arena and don't depend on it.

## 6. Progression & Criminal Hierarchy [Open]

- Rank structure (names, number of tiers)
- How rank is gained: reputation, money, respect, kills, territory?
- RPG elements: stats, skills, perks, gear?

## 7. Combat

### Direction [Decided]
- **Melee first.** Fists and melee weapons are the fundamental problem-solving verb in this non-dialogue-heavy game. They get built and tuned before firearms (see §19: M2 melee, M4 firearms).

### Melee model [Proposal]
- **Readable, committal, physical** — closer to Sleeping Dogs than to a button-mashing brawler: every attack has a windup, active and recovery phase; hits land with hit stop, camera shake and a visible reaction.
- **Soft targeting, no hard lock-on:** attacks snap/lunge toward the best target in a cone in front of the camera (magnetism). The camera stays free.
- **Move set (player):** light attack combo (up to 3 hits) · heavy attack (hold) that breaks guard · guard (hold) · dodge/sidestep · weapon pickup and drop
- **Guard stance replaces aim mode while unarmed or holding a melee weapon:** same strafing/facing behaviour as M1.4 (reuses the strafe blend space), but blocks instead of aiming
- **No stamina** in the first version; guard is limited by guard break (heavy attacks) instead
- **Hit reactions** by severity: flinch (light) → stagger (heavy / combo finisher) → knockdown → knockout (ragdoll)
- **Group fights:** attack tokens: only 1–2 enemies attack at the same time, the others circle and wait. Required for readability over the shoulder.

### Lethality
- **[Decided]** Both knockouts and deaths exist. Outcome depends on the weapon: fists (and blunt weapons) knock out; continuing to hit a knocked-out person kills them. Multiple knife stabs or firearm hits kill.
- **[Proposal] Damage types:** `AttackData.damage_type` = `blunt` / `blade` / `firearm`
  - **Blunt:** health 0 → knockout. Hits on a knocked-out body deal downed damage; past a threshold → death. A bat reaches it faster than fists.
  - **Blade:** no knockout stop; enough stabs → death.
  - **Firearm:** lethal (M4).
- **[Proposal]** `HealthComponent` states: `active` → `knocked_out` → `dead`; knocked-out NPCs recover after a while and can then flee or report the crime (§8)
- **[Proposal]** Killing is a separate, more severe crime than assault (§8); dead bodies are lootable (§12)
- **[Proposal]** Player: arrest remains the default fail state; lethal damage can kill the player → hospital respawn with a cash cost
- **[Proposal]** First bladed weapon: a knife, together with the lethality implementation (M3a)

### Weapons [Proposal]
- First set: **fists** + **one blunt weapon** (bat/pipe) in M2; **knife** in M3a.
- Weapons are items (`WeaponData` extends `ItemData`), picked up via the M1.5 interaction, dropped on knockout or death.

### Still open [Open]
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
| 1 – Suspicion | Pickpocketing, shoplifting, vandalism, looting a knocked-out person | Patrol checks the scene, questions NPCs |
| 2 – Pursuit | Car theft, assault, resisting arrest, shop robbery without a firearm | Foot/vehicle pursuit, search area around last sighting |
| 3 – Manhunt | Killing, armed robbery (firearm), firearm use | More units, roadblocks, district lockdown |

### Evasion & identity
- **Description instead of radar:** police search for a description ("red jacket, cap"); changing clothes (§17), leaving main streets and breaking line of sight all help
- **Search radius** shrinks over time; staying hidden long enough ends the search

### Delayed reports [Proposal]
- A knocked-out victim who wakes up can report the crime
- A dead body found by an NPC is reported as a crime after the fact (police start at the body, not at the player)

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
- **Sanctioned zones** (e.g. the fight club ring, §16): `CrimeManager` ignores the matching crime types inside them

**First vertical slice:** pickpocketing + heat level 1 (M3b).

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

Balancing is open; the sources and sinks below are the current set.

- **Income [Proposal]:** pickpocketing, looting, shop robbery, fight club purses and bets
- **Money sinks [Proposal]:** weapon shops, general stores, clothing stores, entry fees and lost bets, arrest confiscation, hospital costs; bribes, lawyers and buyable places to stay later
- Still open: jobs, rackets, businesses

## 12. Inventory & Looting

- **[Decided]** Inventory and looting come before the crime milestone (M3a)
- **[Proposal] Slot-based, no grid:** 1 melee slot · 1 firearm slot (active from M4) · a few pocket slots for small items. A spatial grid would slow down street crime.
- **[Proposal] Cash is a wallet value**, not an item; it is shown on the HUD
- **[Proposal]** `InventoryComponent` is shared by the player and NPCs (NPCs carry what can be stolen from them)
- **[Proposal]** `LootTable` resources per NPC type in `data/loot/` (cash range, item chances); used by looting **and** pickpocketing
- **[Proposal] Looting:** a knocked-out or dead body exposes a "Search" `Interactable`; searching is a hold action (the player is exposed while doing it); emits `looted(victim, by)` for the `CrimeManager`
- **[Proposal]** Weapons still drop physically on knockout or death (M2.6); cash and pocket items are taken by looting
- Stash storage later, together with buyable places to stay (§15)

## 13. HUD [Proposal]

Minimal and readable; elements appear with the milestone that gives them meaning.

| Element | Milestone | Notes |
|---|---|---|
| Cash | M3a | Wallet value |
| Health | M3a | From `HealthComponent` |
| Equipped weapon | M3a / M4 | Ammo count from M4 |
| Heat state | M3b | Named states (Suspicion / Pursuit / Manhunt), not stars |
| Minimap | M3b | Shows the police **search area** around the last known position, **never live police positions** (§8) |
| Clock | M5 | In-game time and day |

## 14. Shops & Interiors

- **[Decided]** Shops have interiors; regular stores exist and can be robbed; shops sell melee weapons and firearms
- **[Proposal] Seamless interiors:** the few enterable buildings live in the district scene, no loading screens, so fleeing into a shop during a pursuit works with the witness/search systems. All other buildings stay closed.

### Shop types [Proposal]

| Shop | Sells | Milestone |
|---|---|---|
| General store | Consumables (stock open) | M5, robbable |
| Melee weapon shop | Bats, pipes, knives | M5 (satire option: a sporting goods store selling bats in a city where nobody plays baseball) |
| Gun dealer | Firearms, ammo | M5; black-market back room rather than a street shop (fits the European setting); may be rank-gated |
| Clothing store | Outfits | M7 (§17) |

### Shop robbery [Proposal]
- First job type of the progression loop (M5)
- Intimidate the shopkeeper (draw/raise a weapon), take the register cash; the shopkeeper and customers are witnesses
- Heat 2 without a firearm, heat 3 with one (§8)
- After a robbery the shop is not robbable again for a set number of in-game days (§15)

## 15. Time & Day/Night

- **[Decided]** In-game time drives event resets (e.g. a robbed shop becomes robbable again after a set time); there is a day/night cycle
- **[Decided] Passing time:** sitting on benches and other sit spots lets the player wait. Buyable places to stay come later.
- **[Proposal]** Sit spots are `Interactable`s with a "wait until…" choice (e.g. next hour / evening / night / morning); waiting is interrupted when heat rises or the player is attacked
- **[Proposal]** `WorldClock` autoload: time of day, day counter, `hour_changed` / `day_changed` signals, tunable time scale (start at ~48 real minutes per in-game day)
- **[Proposal]** Resets are stored as "available again at" timestamps in game minutes (save-friendly), not as running timers
- **[Proposal] Daily limits reset at 06:00, not midnight**, so one night session counts as one night
- **[Proposal] Time affects gameplay:** shop opening hours, NPC density by hour, the fight club opens at night only (§16), arrest and hospital cause a time skip
- **[Proposal]** Day/night lighting: rotating `DirectionalLight3D`, sky/environment gradient, streetlights
- **[Postponed]** Buyable places to stay (sleep, stash, possibly a save point); after the first progression loop
- **[Postponed]** Darkness reducing witness sight range (must not be designed out)

## 16. Fight Club

- **[Decided]** Underground fight club as a side activity: fight, watch, bet. Daily limits, open at night only.
- **[Proposal] Location:** an old harbour warehouse that the developers rent out as an "event space" by day (light satire)
- **[Proposal] Fighting:** opponents are `FighterData` resources (health, `AttackData` set, AI aggression, rating); fists only at first, weapon nights later; knockout = loss and the fight ends there (no killing in the ring); entry fee, purse for a win; limited fights per night
- **[Proposal] Watching:** NPC vs. NPC fights run on the same components and `CombatDirector`; spectator camera and crowd
- **[Proposal] Betting:** odds derived from fighter ratings; max bet and bets per night are limited; max bet may scale with rank
- **[Proposal]** Fighting inside the ring is a sanctioned zone (§8); fight club wins can feed reputation/rank (§6)
- **[Proposal]** The fight club doubles as the in-game melee balancing test bed; the M2.8 combat arena is its prototype
- **[Postponed]** Rigged fights / throwing a fight for money
- **[Open]** Police raids

## 17. Customization

- **[Decided]** The player character can be customized; money is spent in matching shops
- **[Proposal]** Clothing slots (head, top, bottom, shoes); barber later
- **[Proposal] Tied to the police system:** outfit pieces carry description tags (color, type) that the police search for (§8); changing clothes reduces recognition, which turns the clothing store into an escape tool and a money sink
- **[Proposal] Technical constraint:** modular meshes skinned to one standard humanoid skeleton (Mixamo rig), so every animation keeps working. **Applies from M2.1 on:** no single-mesh-only setup.

## 18. Vehicles

- **[Decided]** Vehicles are a later milestone, after the world grows beyond one district
- **[Proposal] Order:** cars → vans (car with different data, cargo for later jobs) → bicycles → motorcycles (same leaning model; crash ragdolls reuse M2 ragdolls)
- **[Proposal]** Custom raycast suspension instead of `VehicleBody3D` (better handling control)
- **[Proposal]** The expensive parts are traffic AI and police vehicle pursuits, not the driving itself
- **[Postponed]** Public transport (needs AI drivers on fixed routes; little gameplay for the cost). If added later: a "BRIX Line" tram as a satire vehicle.

## 19. Milestones [Decided: order M0–M4 and M3a/M3b split · Proposal: M5+ content]

Rationale: build the gameplay skeleton (movement, aiming, interaction) first, then the core verb: fists and melee weapons are how problems get solved in this game, so their feel has to hit the mark before anything is built on top of them. Inventory, loot and lethality follow so crimes have something to gain and lose. The police/witness system follows and gets real crimes to react to (assault, not only pickpocketing). Firearms are an escalation on top of a working melee system. Vehicles come only once the world outgrows walking.

| # | Milestone | Content |
|---|-----------|---------|
| M0 | Setup | Godot, VS Code, GitHub, folder structure ✅ |
| M1 | Character skeleton | Locomotion, camera, aim mode, interaction, basic physics, placeholder animation — in a gray-box test level 🔧 (implemented; Mixamo model + playtest tuning pending) |
| M2 | Melee combat | Fists + one blunt weapon, guard/dodge, hit reactions, knockout ragdolls, one melee enemy type with group behaviour — in a combat arena 🔧 (implemented on placeholder clips; Mixamo swap + playtest tuning pending) |
| M3a | Inventory, loot & lethality | Slot inventory, wallet, loot tables, looting knocked-out/dead NPCs, damage types, death, knife, cash/health/weapon HUD — in the combat arena |
| — | _Gate_ | _Define Core Loop (§5) before M3b_ |
| M3b | District & first crime | Block-out district, walking NPCs, pickpocketing → witness → report → heat level 1, heat HUD + minimap (search area), arrest confiscates cash/items |
| M4 | Firearms | One firearm, firearm slot, ammo as item, weapon switching, cover decision (§7), ranged enemy behaviour, firearm use → heat |
| M5 | First progression loop | Shop robbery as the job type, heat level 2, first seamless interiors, general store + melee shop + gun dealer, `WorldClock` with reset timers, HUD clock and bench waiting, first rank-up |
| M6 | Nightlife | Day/night lighting cycle, fight club (fight, watch, bet), daily limits, night-time NPC density |
| M7 | Identity & customization | Modular outfits, clothing store, description tags → police search, criminal-record recognition |
| M8 | Second district & cars | World expansion, car driving, car theft → heat 2, basic traffic |
| M9 | Vehicle roster & pursuits | Vans, bicycles, motorcycles, police vehicle pursuits, heat level 3 roadblocks |
| — | _Postponed_ | Public transport, buyable places to stay, darkness & visibility, rigged fights |

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
- Combat emits signals (`hit_landed(attacker, victim, attack)`, `knocked_out(victim, by)`) so the M3b `CrimeManager` can turn them into assault crime events without changing combat code
- Player, enemies and later civilians/police share the same health, hurtbox and combat components
- The character keeps a standard humanoid skeleton (Mixamo rig) so modular customization (§17) works later without redoing animations
- `HealthComponent` uses a state field (not a bool) and `AttackData` gets a `damage_type` field (default `blunt`), so death and blades (M3a) can be added without refactoring

**Out of scope for M2:** firearms, death/lethal outcomes (implemented in M3a, §7), crime/heat integration (M3b), inventory/looting (M3a), stealth takedowns, finishers, stamina, skills/perks, bladed weapons, more than one enemy type.

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
- **Prepared for M3a:** `HealthComponent` has a `state` field (`ACTIVE`, `KNOCKED_OUT`; M3a adds `DEAD`) and `take_damage()` already receives the `AttackData`; `AttackData.damage_type` exists (`BLUNT` / `BLADE` / `FIREARM`, every M2 attack is `BLUNT`, nothing reads it yet).
- **Early HUD element:** a player health bar (and the held weapon's name) is on the HUD already in M2 for playtesting, although §13 schedules health and weapon for M3a.
- **Not done — standard humanoid skeleton:** follows with the Mixamo swap (M2.1); see the first bullet.
- **Tests:** `tests/combat_tests.tscn` checks the "Done when" criteria headless (combo, buffering, heavy, guard/break, dodge, targeting out of three, bat, knockdown, knockout/drop/ragdoll, max 2 attackers over 25 s of 1 vs 3, navigation, restart, M1 regression). Feel and readability still need a human playtest.

### M3a — Inventory, loot & lethality [Proposal: details]

Built and tested in the combat arena; moves into the district with M3b.

| Task | Content | Done when |
|---|---|---|
| M3a.1 Inventory | `InventoryComponent` on player and NPCs: melee slot, firearm slot (inactive until M4), pocket slots, wallet; equip/drop; the M2.6 bat goes into the melee slot | Bat can be picked up, equipped, unequipped and dropped through the inventory, no special-case code |
| M3a.2 Loot tables | `LootTable` resources in `data/loot/` (cash range, item chances); assigned per NPC type; rolled into the NPC's inventory on spawn | Two NPC types carry different loot, defined only in `.tres` files |
| M3a.3 Lethality | `dead` state in `HealthComponent`; damage types; downed damage on knocked-out bodies; knockout recovery timer; knife as `WeaponData` with blade `AttackData`; `killed(victim, by)` signal | Punching a downed thug long enough kills him; a few knife stabs kill; an untouched knocked-out thug gets back up |
| M3a.4 Looting | Knocked-out or dead body exposes a "Search" `Interactable` (hold action); transfers cash and items; emits `looted(victim, by)` | KO or kill a thug, search the body, cash and items move to the player |
| M3a.5 HUD & inventory UI | HUD: cash, health, equipped weapon; simple inventory overlay | Cash on the HUD updates when looting; inventory overlay shows all slots |

#### M3a implementation notes [Proposal: awaiting playtest]

Built on top of the M2 branch (PR #5, not merged yet). What was built, and where it deviates from the table above. All numbers are starting values in `.tres`/`@export`s, to be tuned in playtest.

- **Inventory (M3a.1):** `InventoryComponent` on player and NPCs: melee slot, firearm slot (present but locked until M4), 4 pocket slots, wallet. The inventory owns weapons; `MeleeCombat` only fights with what is put in hand. The melee weapon is **drawn** (in hand) or **holstered** (carried, fists in use). Picking up a weapon while carrying one drops the old one (swap). Weapons only go in the melee slot, everything else in pockets. **Added bindings:** H = holster/draw, Tab = inventory overlay. G still drops (also a holstered weapon).
- **Loot tables (M3a.2):** `LootTable` (cash range, cash chance, entries with a chance each, optional item cap) rolled into the NPC's inventory on spawn. Two types: **thug** ($5–30, lighter 60%, phone 30%) and **collector** (a loan shark's debt collector: $80–160, collection ledger 100%, wristwatch 70%, phone 50%, 120 HP, blue tint). The 1 vs 3 fight is two thugs and a collector.
  - **Deviation — NPC types are scene variants, not Resources** (`scenes/npc/collector.tscn` inherits `thug.tscn` and overrides the loot table, health and tint). CLAUDE.md rule 5 asks for NPC types as Resources; an `NpcTypeData` resource can replace the variants once NPC types carry more than loot and stats (M3b walkers).
- **Lethality (M3a.3):** `HealthComponent` states `ACTIVE` → `KNOCKED_OUT` → `DEAD`. Blunt damage at 0 HP knocks out; blade (and later firearm) damage at 0 HP kills straight away. A knocked-out body has 40 points of **downed health**; downed damage is scaled by type (blunt ×1, blade ×2, firearm ×4), so fists need about 5 hits and the bat 3. An untouched knocked-out thug gets up after **12 s** with 30% health (every downed hit restarts the timer) and fights again. `killed(victim, by)` on `HealthComponent`; downed hits are still reported as `hit_landed`.
  - **Knife:** `WeaponData` with blade attacks: 2-hit combo 30/30, heavy 45 (breaks guard, staggers), reach 0.85 m. Four light stabs kill a thug. One knife lies in the arena.
  - **Deviation — no ground attacks.** Hits on a downed body use the normal standing attacks: the knocked-out body's hurtbox follows the ragdoll, so swinging at a body on the floor hits it. Stomps/ground punches come with the Mixamo clips. The knife reuses the punch clips for now.
  - **Deviation — after recovery the thug fights again** instead of fleeing or reporting (§7 Lethality, §8). Flee/report needs the M3b witness and crime systems.
  - **Player:** a knocked-out player stays down (no recovery timer) and a blade can kill the player ("You died"); both end the fight until F5. Hospital respawn with a cash cost (§7) is not built yet (it needs a world to respawn in). Thugs never attack a downed player, and the player's downed body can't be hit.
- **Looting (M3a.4):** `BodySearch` on every NPC exposes a "Search" `Interactable` on knocked-out and dead bodies (it follows the ragdoll). Searching is a **1.5 s hold** of E; the player stands still meanwhile, and releasing E, attacking or taking a hit cancels it. Cash and every item that fits move to the player; what doesn't fit (pockets full) stays and the body can be searched again. Emits `looted(victim, by)`. A searched body can't be searched again; a recovering thug resets it. Weapons still drop physically on knockout or death (and are not part of the search).
- **HUD (M3a.5):** cash (flashes green/red on change), health bar, held weapon ("Fists (Knife holstered)"), hold progress under the interaction prompt ("[E] Search (hold)"), and an inventory overlay (Tab) listing cash, melee (in hand / holstered), firearm (locked) and all pocket slots. The overlay is read-only.
- **Arena restart (F5)** takes the held weapon away but keeps the wallet and pockets.
- **Interactions:** `Interactable.hold_time` (0 = instant) makes any interactable a held one; generic item pickups go into the pockets (refused when full).
- **Tests:** `tests/m3a_tests.tscn` checks the M3a "Done when" criteria headless: bat pick up / holster / draw / drop and the knife swap, slot rules, loot table contents per type, punching a downed thug to death (and bat vs fists), knife kills without a knockout, knockout recovery (and the timer reset by hits), hold-to-search (tap does nothing, player held in place, cancel on release and on hit, pockets full), looting a dead body, the HUD, player death and restart. The M2 suite still passes.

### M3b — District & first crime [Proposal: details]

| Task | Content |
|---|---|
| M3b.1 District block-out | Small part of Brickhaven in gray-box: a few streets, a square, alleys, enough line-of-sight breakers |
| M3b.2 NPC walkers | `NavigationAgent3D` civilians following simple routines (walk between points, idle); builds on the M2.7 NPC controller |
| M3b.3 Crime events | `CrimeManager` + crime definitions as `.tres` (incl. assault and killing); pickpocketing as an interaction (built on M1.5) that rolls the victim's `LootTable`; looting becomes a crime event |
| M3b.4 Witnesses | `WitnessComponent`: field of view + line of sight; reactions: flee / call police; the report timer can be interrupted |
| M3b.5 Heat level 1 | `HeatManager`: heat level, last known position, search radius that shrinks over time; heat state on the HUD; minimap showing the search area |
| M3b.6 Police response | One patrol unit walks to the last known position and searches the area; minimal arrest = cash and pocket items confiscated + respawn |

**Done when:** the full chain plays out in the district: pickpocket → seen or unseen → report or prevented → patrol searches → escape or get arrested.

### M5 — First progression loop [Proposal: details]

| Task | Content |
|---|---|
| M5.1 WorldClock | Autoload clock, day counter, signals, "available again at" reset timestamps; HUD clock |
| M5.2 Waiting | Benches and sit spots as `Interactable`s with "wait until…"; interrupted by heat or attacks |
| M5.3 Interiors | First seamless interiors in the district: general store, melee shop, gun dealer back room |
| M5.4 Shops | Buy UI driven by shop stock resources; opening hours from the clock |
| M5.5 Shop robbery | Shopkeeper intimidation, register cash, witnesses inside; reset timer after a robbery |
| M5.6 Heat level 2 | Foot pursuit and search area around the last sighting |
| M5.7 First rank-up | Money/reputation threshold → first rank (depends on §6) |

### M6 — Nightlife [Proposal: details]

| Task | Content |
|---|---|
| M6.1 Day/night cycle | Lighting and environment driven by `WorldClock`; streetlights; NPC density by hour |
| M6.2 Fight club venue | Warehouse interior, ring as a sanctioned zone, crowd, open at night only |
| M6.3 Fighting | `FighterData` opponents, entry fee and purse, fights-per-night limit |
| M6.4 Watching & betting | NPC vs. NPC fights, spectator camera, odds from ratings, bet limits, daily reset at 06:00 |

## 20. Technical Risks (3D, over-the-shoulder)

- Camera collision and aiming feel
- Character animation volume (locomotion, combat, NPCs); melee feel depends heavily on clip quality, and Mixamo's melee/bat selection is limited
- NPC crowds and AI performance (incl. witness perception checks)
- World streaming / LOD once the map grows beyond one district
- Seamless interiors: occlusion/culling so enterable buildings don't cost performance outside
- Modular character customization: mesh/skeleton compatibility across clothing pieces
- Traffic AI and police vehicle pursuits (M8–M9)
