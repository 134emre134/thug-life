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

_What does a typical 10-minute session look like?_ — **must be defined before M5a (Crime fundamentals).** M3b (district), M4a (combat update) and M4b (firearms) don't depend on it.

## 6. Progression & Criminal Hierarchy [Open]

- Rank structure (names, number of tiers)
- How rank is gained: reputation, money, respect, kills, territory?
- RPG elements: stats, skills, perks, gear?

## 7. Combat

### Direction [Decided]
- **Melee first.** Fists and melee weapons are the fundamental problem-solving verb in this non-dialogue-heavy game. They get built and tuned before firearms (see §19: M2 melee, M4a combat update, M4b firearms).

### Melee model [Proposal]
- **Readable, committal, physical** — closer to Sleeping Dogs than to a button-mashing brawler: every attack has a windup, active and recovery phase; hits land with hit stop, camera shake and a visible reaction.
- **Soft targeting, no hard lock-on:** attacks snap/lunge toward the best target in a cone in front of the camera (magnetism). The camera stays free.
- **Move set (player):** light attack combo (up to 3 hits) · heavy attack (hold) that breaks guard · guard (hold) · dodge/sidestep · weapon pickup and drop · **stomp** on a downed opponent (M4a) · **crouch** (M4a)
- **Guard stance replaces aim mode while unarmed or holding a melee weapon:** same strafing/facing behaviour as M1.4 (reuses the strafe blend space), but blocks instead of aiming
- **No stamina** in the first version; guard is limited by guard break (heavy attacks) instead
- **Hit reactions** by severity: flinch (light) → stagger (heavy / combo finisher) → knockdown → knockout (ragdoll)
- **Group fights:** attack tokens: only 1–2 enemies attack at the same time, the others circle and wait. Required for readability over the shoulder.
- **[Decided] Attack timing follows the animation:** hit windows come from the clips (markers / method tracks), not from hand-typed numbers (M4a)

### Lethality
- **[Decided]** Both knockouts and deaths exist. Outcome depends on the weapon: fists (and blunt weapons) knock out; continuing to hit a knocked-out person kills them. Multiple knife stabs or firearm hits kill.
- **[Proposal] Damage types:** `AttackData.damage_type` = `blunt` / `blade` / `firearm`
  - **Blunt:** health 0 → knockout. Hits on a knocked-out body deal downed damage; past a threshold → death. A bat reaches it faster than fists; a stomp is the dedicated downed attack.
  - **Blade:** no knockout stop; enough stabs → death.
  - **Firearm:** lethal (M4b).
- **[Proposal]** `HealthComponent` states: `active` → `knocked_out` → `dead`; knocked-out NPCs recover after a while and can then flee or (from M5a) report the crime (§8)
- **[Proposal]** Killing is a separate, more severe crime than assault (§8); dead bodies are lootable (§12)
- **[Proposal]** Player: arrest remains the default fail state; lethal damage can kill the player → hospital respawn with a cash cost
- **[Proposal]** First bladed weapon: a knife, together with the lethality implementation (M3a)

### Weapons [Proposal]
- First set: **fists** + **one blunt weapon** (bat/pipe) in M2; **knife** in M3a; **one firearm** in M4b.
- Weapons are items (`WeaponData` extends `ItemData`), picked up via the M1.5 interaction, dropped on knockout or death.

### Crouch & cover
- **[Decided]** Crouch exists (M4a) and cover exists (M4b)
- **[Proposal] Crouch:** toggle by default, hold as an option (M4a); lower collision shape, ceiling check before standing up, slower movement, crouch blend space; crouching behind low objects breaks line of sight (pays off with witnesses in M5a)
- **[Open] Crouched combat:** M4a stands the player up for any combat action (there are no crouched combat clips). Whether attacks, guard or a takedown from crouch should exist is open; must not be designed out.
- **[Proposal] Cover:** sticky cover on a button; cover edges detected via raycasts; peek and aim over/around; works from standing and crouched positions; built with firearms because ranged enemies are what make it testable

### Still open [Open]
- Melee vs. firearms balance (M4b).
- Stealth takedowns, finishers, environmental attacks (later; must not be designed out).

## 8. Police & Crime [Proposal]

Early-game focus: the individual player gets hunted for small crimes. **Crime and heat exist from M5a on;** before that, actions have no legal consequences.

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
- `WitnessComponent` — on NPCs, perception + reaction (builds on the M3b civilian panic reaction)
- `HeatManager` — heat level, search area, decay
- Crime definitions as `.tres` data (severity, base heat, witness radius)
- **Sanctioned zones** (e.g. the fight club ring, §16): `CrimeManager` ignores the matching crime types inside them

**First vertical slice:** pickpocketing + heat level 1 (M5a).

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
- **[Proposal] Slot-based, no grid:** 1 melee slot · 1 firearm slot (active from M4b) · a few pocket slots for small items. A spatial grid would slow down street crime.
- **[Proposal] Cash is a wallet value**, not an item; it is shown on the HUD
- **[Proposal]** `InventoryComponent` is shared by the player and NPCs (NPCs carry what can be stolen from them)
- **[Proposal]** `LootTable` resources per NPC type in `data/loot/` (cash range, item chances); used by looting **and** pickpocketing
- **[Proposal] Looting:** a knocked-out or dead body exposes a "Search" `Interactable`; searching is a hold action (the player is exposed while doing it); emits `looted(victim, by)` for the `CrimeManager`
- **[Proposal]** Weapons still drop physically on knockout or death (M2.6); cash and pocket items are taken by looting
- **[Decided, temporary]** The inventory overlay pauses the game (M4a). Searching a body stays real-time. Revisit once crime and pursuits exist (M5).
- Stash storage later, together with buyable places to stay (§15)

## 13. HUD [Proposal]

Minimal and readable; elements appear with the milestone that gives them meaning.

| Element | Milestone | Notes |
|---|---|---|
| Cash | M3a | Wallet value |
| Health | M3a | From `HealthComponent` |
| Equipped weapon | M3a / M4b | Ammo count from M4b |
| Minimap | M3b / M5a | M3b: basic navigation map of the district. M5a: adds the police **search area** around the last known position, **never live police positions** (§8) |
| Heat state | M5a | Named states (Suspicion / Pursuit / Manhunt), not stars |
| Clock | M5b | In-game time and day |

## 14. Shops & Interiors

- **[Decided]** Shops have interiors; regular stores exist and can be robbed; shops sell melee weapons and firearms
- **[Proposal] Seamless interiors:** the few enterable buildings live in the district scene, no loading screens, so fleeing into a shop during a pursuit works with the witness/search systems. All other buildings stay closed.
- **[Proposal]** Lots for the first shops and the fight club warehouse are reserved in the M3b block-out

### Shop types [Proposal]

| Shop | Sells | Milestone |
|---|---|---|
| General store | Consumables (stock open) | M5b, robbable |
| Melee weapon shop | Bats, pipes, knives | M5b (satire option: a sporting goods store selling bats in a city where nobody plays baseball) |
| Gun dealer | Firearms, ammo | M5b; black-market back room rather than a street shop (fits the European setting); may be rank-gated |
| Clothing store | Outfits | M7 (§17) |

### Shop robbery [Proposal]
- First job type of the progression loop (M5b)
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
- **[Proposal]** The fight club doubles as the in-game melee balancing test bed; the M3b district gym is its prototype
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

## 19. Milestones [Decided: order M0–M5b and the M3a/M3b, M4a/M4b, M5a/M5b splits · Proposal: M6+ content]

Rationale: build the gameplay skeleton (movement, aiming, interaction) first, then the core verb: fists and melee weapons are how problems get solved in this game, so their feel has to hit the mark before anything is built on top of them. Inventory, loot and lethality follow so fights have something to gain and lose. The district then replaces the gray-box levels, so all later work happens in a real street environment. A dedicated combat update polishes animations and feel before firearms are added as an escalation. Crime and heat come only once the district and both weapon types exist, so the police system has real crimes to react to. Vehicles come only once the world outgrows walking.

| # | Milestone | Content |
|---|-----------|---------|
| M0 | Setup | Godot, VS Code, GitHub, folder structure ✅ |
| M1 | Character skeleton | Locomotion, camera, aim mode, interaction, basic physics, placeholder animation — in a gray-box test level 🔧 (implemented; Mixamo model + playtest tuning pending) |
| M2 | Melee combat | Fists + one blunt weapon, guard/dodge, hit reactions, knockout ragdolls, one melee enemy type with group behaviour — in a combat arena 🔧 (implemented on placeholder clips; Mixamo swap + playtest tuning pending) |
| M3a | Inventory, loot & lethality | Slot inventory, wallet, loot tables, looting knocked-out/dead NPCs, damage types, death, knife, cash/health/weapon HUD — in the combat arena |
| M3b | District | Gray-box Brickhaven block-out with lots reserved for M5 buildings, combat gym inside the district, walking civilians that panic and can be fought/knocked out/looted, thug spawns, basic minimap — no police, no crime, no cars |
| M4a | Combat update | Animation pass, attack timing driven by clips, combat feel tuning, crouch, stomp on downed opponents, inventory pauses the game |
| M4b | Firearms | One firearm, firearm slot, ammo as item, weapon switching, sticky cover, ranged enemy behaviour |
| — | _Gate_ | _Define Core Loop (§5) before M5a_ |
| M5a | Crime fundamentals | `CrimeManager`, pickpocketing, witnesses, report, heat level 1, police patrol, arrest, firearm use → heat, heat HUD + search area on the minimap |
| M5b | First progression loop | Shop robbery as the job type, heat level 2, first seamless interiors, general store + melee shop + gun dealer, `WorldClock` with reset timers, HUD clock and bench waiting, first rank-up |
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

**Out of scope for M1:** firing weapons, melee, ragdolls, hit reactions, crouch (M4a), cover (M4b), vehicles.

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
- Combat emits signals (`hit_landed(attacker, victim, attack)`, `knocked_out(victim, by)`) so the M5a `CrimeManager` can turn them into assault crime events without changing combat code
- Player, enemies and later civilians/police share the same health, hurtbox and combat components
- The character keeps a standard humanoid skeleton (Mixamo rig) so modular customization (§17) works later without redoing animations
- `HealthComponent` uses a state field (not a bool) and `AttackData` gets a `damage_type` field (default `blunt`), so death and blades (M3a) can be added without refactoring

**Out of scope for M2:** firearms, death/lethal outcomes (implemented in M3a, §7), crime/heat integration (M5a), inventory/looting (M3a), stealth takedowns, finishers, stamina, skills/perks, bladed weapons, more than one enemy type.

#### M2 implementation notes [Proposal: awaiting playtest]

What was built, and where it deviates from the table above. All numbers are starting values in `.tres`/`@export`s, to be tuned in playtest.

- **M2.1 — Mixamo character and locomotion in; combat clips still placeholders.** Player and thugs use the Mixamo model (`assets/models/player.fbx`) and Mixamo locomotion clips, retargeted on import to Godot's standard humanoid skeleton (`SkeletonProfileHumanoid`), so later characters and clips from other sources share it (§17). No Mixamo combat clips exist yet: all combat clips (light combo ×3, heavy, guard, dodge, flinch, stagger, knockdown, get-up; unarmed and bat) are procedural placeholders generated for the real skeleton with IK, and play from a debug key (F4). **Deviation:** the bat is held two-handed in every bat pose, plus a two-handed "bat ready" upper-body pose outside attacks.
- **Clip speeds:** measured ground speeds: walk 1.53, run 3.91, sprint 5.63 m/s; strafe forward 2.26, back 1.32, left 2.06, right 2.18 m/s. The blend points sit at these speeds; movement speeds stay at the M1 values, and the clips play faster when the character moves faster than the fastest clip (up to 1.5×), so feet don't slide. `sprint` and `aim_left` were downloaded without "In Place"; the import removes their drift.
- **Ragdoll:** physical bones (`PhysicalBoneSimulator3D`, 12 bodies) on the character skeleton.
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
- **Tests:** `tests/combat_tests.tscn` checks the "Done when" criteria headless (combo, buffering, heavy, guard/break, dodge, targeting out of three, bat, knockdown, knockout/drop/ragdoll, max 2 attackers over 25 s of 1 vs 3, navigation, restart, M1 regression). Feel and readability still need a human playtest.

### M3a — Inventory, loot & lethality [Proposal: details]

Built and tested in the combat arena; moves into the district with M3b.

| Task | Content | Done when |
|---|---|---|
| M3a.1 Inventory | `InventoryComponent` on player and NPCs: melee slot, firearm slot (inactive until M4b), pocket slots, wallet; equip/drop; the M2.6 bat goes into the melee slot | Bat can be picked up, equipped, unequipped and dropped through the inventory, no special-case code |
| M3a.2 Loot tables | `LootTable` resources in `data/loot/` (cash range, item chances); assigned per NPC type; rolled into the NPC's inventory on spawn | Two NPC types carry different loot, defined only in `.tres` files |
| M3a.3 Lethality | `dead` state in `HealthComponent`; damage types; downed damage on knocked-out bodies; knockout recovery timer; knife as `WeaponData` with blade `AttackData`; `killed(victim, by)` signal | Punching a downed thug long enough kills him; a few knife stabs kill; an untouched knocked-out thug gets back up |
| M3a.4 Looting | Knocked-out or dead body exposes a "Search" `Interactable` (hold action); transfers cash and items; emits `looted(victim, by)` | KO or kill a thug, search the body, cash and items move to the player |
| M3a.5 HUD & inventory UI | HUD: cash, health, equipped weapon; simple inventory overlay | Cash on the HUD updates when looting; inventory overlay shows all slots |

#### M3a implementation notes [Proposal: awaiting playtest]

What was built, and where it deviates from the table above. All numbers are starting values in `.tres`/`@export`s, to be tuned in playtest.

- **Inventory (M3a.1):** `InventoryComponent` on player and NPCs: melee slot, firearm slot (present but locked until M4b), 4 pocket slots, wallet. The inventory owns weapons; `MeleeCombat` only fights with what is put in hand. The melee weapon is **drawn** (in hand) or **holstered** (carried, fists in use). Picking up a weapon while carrying one drops the old one (swap). Weapons only go in the melee slot, everything else in pockets. **Added bindings:** H = holster/draw, Tab = inventory overlay. G still drops (also a holstered weapon).
- **Loot tables (M3a.2):** `LootTable` (cash range, cash chance, entries with a chance each, optional item cap) rolled into the NPC's inventory on spawn. Two types: **thug** ($5–30, lighter 60%, phone 30%) and **collector** (a loan shark's debt collector: $80–160, collection ledger 100%, wristwatch 70%, phone 50%, 120 HP, blue tint). The 1 vs 3 fight is two thugs and a collector.
  - **Deviation — NPC types are scene variants, not Resources** (`scenes/npc/collector.tscn` inherits `thug.tscn` and overrides the loot table, health and tint). CLAUDE.md rule 5 asks for NPC types as Resources; an `NpcTypeData` resource can replace the variants once NPC types carry more than loot and stats (M3b civilians).
- **Lethality (M3a.3):** `HealthComponent` states `ACTIVE` → `KNOCKED_OUT` → `DEAD`. Blunt damage at 0 HP knocks out; blade (and later firearm) damage at 0 HP kills straight away. A knocked-out body has 40 points of **downed health**; downed damage is scaled by type (blunt ×1, blade ×2, firearm ×4), so fists need about 5 hits and the bat 3. An untouched knocked-out thug gets up after **12 s** with 30% health (every downed hit restarts the timer) and fights again. `killed(victim, by)` on `HealthComponent`; downed hits are still reported as `hit_landed`.
  - **Knife:** `WeaponData` with blade attacks: 2-hit combo 30/30, heavy 45 (breaks guard, staggers), reach 0.85 m. Four light stabs kill a thug. One knife lies in the arena.
  - **Deviation — no ground attacks.** Hits on a downed body use the normal standing attacks: the knocked-out body's hurtbox follows the ragdoll, so swinging at a body on the floor hits it. Stomps come with the M4a combat update (M4a.5). The knife reuses the punch clips for now.
  - **Deviation — after recovery the thug fights again** instead of fleeing or reporting (§7 Lethality, §8). Civilians flee after recovery since M3b; reporting needs the M5a witness and crime systems.
  - **Player:** a knocked-out player stays down (no recovery timer) and a blade can kill the player ("You died"); both end the fight until F5. Hospital respawn with a cash cost (§7) is not built yet (it needs a world to respawn in). Thugs never attack a downed player, and the player's downed body can't be hit.
- **Looting (M3a.4):** `BodySearch` on every NPC exposes a "Search" `Interactable` on knocked-out and dead bodies (it follows the ragdoll). Searching is a **1.5 s hold** of E; the player stands still meanwhile, and releasing E, attacking or taking a hit cancels it. Cash and every item that fits move to the player; what doesn't fit (pockets full) stays and the body can be searched again. Emits `looted(victim, by)`. A searched body can't be searched again; a recovering thug resets it. Weapons still drop physically on knockout or death (and are not part of the search).
- **HUD (M3a.5):** cash (flashes green/red on change), health bar, held weapon ("Fists (Knife holstered)"), hold progress under the interaction prompt ("[E] Search (hold)"), and an inventory overlay (Tab) listing cash, melee (in hand / holstered), firearm (locked) and all pocket slots. The overlay is read-only.
- **Arena restart (F5)** takes the held weapon away but keeps the wallet and pockets.
- **Interactions:** `Interactable.hold_time` (0 = instant) makes any interactable a held one; generic item pickups go into the pockets (refused when full).
- **Tests:** `tests/m3a_tests.tscn` checks the M3a "Done when" criteria headless: bat pick up / holster / draw / drop and the knife swap, slot rules, loot table contents per type, punching a downed thug to death (and bat vs fists), knife kills without a knockout, knockout recovery (and the timer reset by hits), hold-to-search (tap does nothing, player held in place, cancel on release and on hit, pockets full), looting a dead body, the HUD, player death and restart. The M2 suite still passes.

### M3b — District [Proposal: details]

Goal: leave the gray-box levels. All further work happens in a small street environment. No police, no crime, no cars.

| Task | Content | Done when |
|---|---|---|
| M3b.1 District block-out | Small part of Brickhaven in gray-box: a few streets, a square, alleys, houses (closed), enough line-of-sight breakers and low objects for crouch/cover later; lots reserved for the M5b shops and the M6 warehouse; navigation mesh baked | The player can walk the whole district without snagging; reserved lots are marked |
| M3b.2 District gym | Combat test area inside the district (boxing gym or fenced yard) with the M2.8 enemy spawner and debug overlay; `combat_gym.tscn` stays as a debug scene | Fights can be started and restarted in the district gym without reloading |
| M3b.3 Thug spawns | Thugs placed in alleys and around the gym, using the existing NPC controller and `CombatDirector` | Thugs engage the player in the streets as they do in the arena |
| M3b.4 Civilian walkers | `NavigationAgent3D` civilians with simple routines (walk between points, idle); new civilian NPC type with its own `LootTable`; same health, hurtbox and inventory components as thugs | Civilians walk their routes; a civilian can be hit, knocked out and looted |
| M3b.5 Civilian panic | Civilians near combat or a knocked-out/dead body flee; no reporting (that becomes the `WitnessComponent` in M5a) | Starting a fight on a street makes nearby civilians scatter |
| M3b.6 Basic minimap | District map with the player position and orientation; no police data | The minimap matches the district layout while moving |

**Done when:** spawn in the district, walk the streets among civilians, start a fight in the gym or an alley, civilians nearby scatter, and knocked-out civilians and thugs can be looted.

#### M3b implementation notes [Proposal: awaiting playtest]

What was built, and where it deviates from the table above. All numbers are starting values in `.tscn`/`.tres`/`@export`s, to be tuned in playtest.

- **District (M3b.1):** `scenes/levels/district.tscn` is now the main scene. Brickhaven is about 128 × 104 m: **Harbour Road** (east–west) and **Dock Street** (north–south) cross in the middle and split it into four blocks:
  - north-west: **Brix Square** (fountain, benches, kiosk, planters, a low wall);
  - north-east: the **boxing club yard** (district gym);
  - south-west: housing, **St. Brix Clinic** and a back alley;
  - south-east: shops-to-be and the harbour.

  The **Old Quay** promenade runs along the south edge, behind a 1.3 m railing. Every block has a back alley. Parked cars, a van, a bus shelter, dumpsters, bollards and a crane block line of sight, and there are low objects (0.45–0.9 m) for M4a crouch/M4b cover. Houses are closed boxes; tall boundary buildings close off the district. Roads, sidewalks and the plaza are flat markings without collision (no curbs to snag on). Light satire: a "BRIX · The Creative Quarter · lofts from 1.2M" sign on the new-build lofts.
  - **Reserved lots** (yellow ground marking + "RESERVED" sign): general store (on Harbour Road), melee shop (Dock Street/Harbour Road corner), gun dealer (in the south-east back alley), warehouse/fight club (by the quay).
  - **Deviation — generated layout.** The block-out was written by a one-off generator script (not committed) as plain `CSGBox3D` nodes, so it is edited in the Godot editor like any hand-made scene.
- **District gym (M3b.2):** a **fenced yard** (3 m fence, gates west and south) rather than a building, so fights stay visible from the street and civilians react to them. It is a `FightArena` (the M2.8 arena logic, now shared with `combat_gym.tscn`): a **Start fight** button by the south gate starts the current mode without moving the player; F5 restarts (player back at the yard spawn, weapons and enemies reset) and F6 switches mode, **only while the player is inside the yard**. Unlike the arena, a restart doesn't take the held weapon away. `combat_gym.tscn` stays as a debug scene.
- **Thug spawns (M3b.3):** street thugs (`street_thug.tscn`) loiter in the back alleys, 1–2 per alley, 7 in total.
  - **Added — aggro range.** In the arena a thug hunts the player anywhere; in the streets that would pull every thug in the district to the player. A street thug only picks up the player within **9 m and in sight**, drops the target beyond **22 m**, and then walks back to where it spawned. Hitting a thug always provokes it.
  - Gym thugs keep the arena behaviour. All thugs share one `CombatDirector`, so token limits apply across the district.
- **NPC populations:** spawners keep a set number of NPCs standing. A lost NPC is replaced after **20 s** at a spawn point at least **25 m** from the player. Dead bodies stay **45 s** and are then removed once the player is 25 m away. Knocked-out NPCs count as standing (they get back up).
- **Civilian walkers (M3b.4):** 10 civilians (`civilian.tscn`: 60 HP, walk 1.5 m/s, sprint 5.6 m/s, so the player can catch them) walk six `WalkRoute`s along the sidewalks, the square and the quay, and idle at some route points (35% chance, 2–6 s).
  - They use the same health, hurtbox, combat, ragdoll, inventory and search components as thugs, on their own team (`civilians`), and never fight back.
  - **Loot** (`data/loot/civilian.tres`): $10–60 (90%), phone 60%, wristwatch 15%, and a worthless "BRIX loyalty card" 40% (satire).
  - **Deviation — NPC types are still scene variants.** `civilian.tscn` inherits `thug.tscn` and swaps the AI script; the M3a note expected a possible `NpcTypeData` resource here. Variants are still enough, since a type is only loot, stats, team, tint and controller. Revisit when NPC types grow (M5a witnesses, M6 fighters).
- **Civilian panic (M3b.5):** a civilian panics on seeing, within **14 m** and with line of sight:
  - someone attacking or being hit;
  - a knocked-out or dead body (each body scares a civilian only once, so bodies don't create permanent no-go zones).

  Being hit also causes panic, and so does a panicking civilian within **6 m** (contagion). Panicking civilians sprint away along the navigation mesh until they are **22 m** from the danger (at least 4 s, at most 14 s), catch their breath for 3 s and walk back to their route. A knocked-out civilian who gets back up flees. No reporting (M5a).
- **Basic minimap (M3b.6):** top-right on the HUD; it draws footprints of buildings, obstacles, roads, sidewalks, the plaza, water, reserved lots and the gym yard, with the player arrow in the centre. It **turns with the camera** (an N marker shows north); there is an export for north-up. No NPCs or police data. It is hidden in levels without map data (the arena).
- **Added — clinic respawn (§7).** A downed or dead player wakes up at St. Brix Clinic after **4 s**, fully healed, and pays **$50** (or whatever cash they have). There is no time skip yet (needs `WorldClock`, M5b). This replaces "fight over until F5" from M3a, which doesn't work in an open district.
- **Tests:** `tests/m3b_tests.tscn` checks the M3b "Done when" criteria headless in the real district:
  - layout: navigation mesh, lots marked, populations filled;
  - the player walks real-input routes to 13 places across the district without snagging;
  - gym: the button starts the fight, F5/F6 only work inside the yard, a restart gives fresh enemies without a reload;
  - street thugs: aggro range, attacking, giving up and walking home;
  - civilians: walking their routes, being knocked out and looted, scattering from a fight (while distant civilians stay calm), fleeing from a body and after recovering;
  - minimap scale and rotation, clinic respawn and fee, population respawn.

  The M2 and M3a suites still pass.

### M4a — Combat update [Proposal: details]

Goal: combat feels weighty and readable. Animations are final enough that timing and feel can be tuned on top of them. Tasks are listed in implementation order.

| Task | Content | Done when |
|---|---|---|
| M4a.1 Animation pass | Review every clip; replace the generated placeholder combat clips and add new ones (Mixamo or other humanoid sources, retargeted via the humanoid bone map); clips include crouch locomotion and stomp; naming convention + a clip manifest (purpose, loop, approximate contact time) | All clips play on the character from a debug key; locomotion still meets the M1.7 criterion |
| M4a.2 Clip-driven attack timing | Windup/active/recovery derived from animation markers or method tracks instead of hand-typed times; fixes the current attack speed | Every hit lands on the visible contact frame; no attack plays faster than its clip |
| M4a.3 Combat feel tuning | Rebalance combos, hit stop, reactions and enemy telegraphs on the new clips | 1 vs. 1 and 1 vs. 3 in the district gym pass a playtest for weight and readability |
| M4a.4 Crouch | Hold/toggle crouch; lower collision shape; ceiling check before standing up; crouch blend space; slower movement | Crouch-walking under low obstacles works; standing up under a ceiling is blocked |
| M4a.5 Stomp | Context attack when a `knocked_out` target is in range; own `AttackData` with downed damage; soft targeting picks ground targets | A stomp hits the intended downed body and kills past the downed-damage threshold |
| M4a.6 Inventory pause | Inventory overlay pauses the game (UI processes while paused); searching a body stays real-time; marked as temporary | Opening the inventory freezes enemies and civilians; closing it resumes cleanly |

**Out of scope for M4a:** firearms and cover (M4b), crime/heat (M5a), stamina, finishers, stealth takedowns.

#### M4a implementation notes [Proposal: awaiting playtest]

What was built, and where it deviates from the table above. All numbers are starting values in `.tres`/`@export`s/`clip_data.json`, to be tuned in playtest. The clip list is in [`assets/animations/CLIPS.md`](../assets/animations/CLIPS.md).

- **M4a.1 — Animation pass.**
  - **Naming convention:** every clip is `assets/animations/mixamo/<clip>.fbx` in snake_case, named after what it does (`hit_react_face`, `knife_stab_straight`, `getup_from_back`), with family prefixes (`punch_`, `knife_`, `hit_react_`, `getup_`, `jump_`, `crouch_`, `rifle_`). The user's downloads were renamed (uids kept) and the clips from `assets/animations/` moved in with the standard import settings. Their bone prefix is `mixamorig12_`, so they have their own bone map. Two Mixamo names were misleading and are named by what the clip shows: "StabbingRightArm" thrusts with the **left** hand (`knife_stab_left_hand`, unused), "StabbingLeftArm" is a right-hand hooking stab (`knife_stab_hook`).
  - **Manifest:** `assets/animations/CLIPS.md` (source, purpose, loop, length, contact markers, placeholder or not, missing clips).
  - **Real clips now:** jab (left lead straight), uppercut (fists heavy and thug heavy), knife straight stab (light) and hooking stab (heavy), knife ready pose, hit reactions (flinch: face / body, stagger: stomach / uppercut, guard break: dazed head hit), knockdown, get-up from the back and from the front, crouch idle/walk and transitions, standing and running jumps, landings.
  - **Still placeholders:** right cross and hook (fists light 2 and 3), all bat swings and bat poses, guard, dodge, and the new stomp. No fitting downloads exist for them yet.
  - **Clip data on import:** `assets/animations/clip_data.json` trims clips (e.g. the 2 s of lying still before `getup_from_back`), adds animation markers and cuts segments (a jump's airborne and landing parts) in the Mixamo post-import step. The AnimationTree is generated by `scripts/tools/build_humanoid_tree.gd`; clip speeds and contact frames are measured with `scripts/tools/analyze_clips.gd`.
  - **Debug key:** F4 plays every non-firearm clip on the character (46), not only the combat clips; single-frame poses are shown for a second. Locomotion blend points are unchanged (M1.7); the crouch walk point sits at its measured 1.28 m/s.
- **Jumps (added, user request):** the single `fall` pose is replaced by a jump start (standing, or running from 2.5 m/s), the M1 fall loop once the jump clip has played out (or when walking off an edge), and a landing one-shot (standing, running from 1.5 m/s, or a heavy landing when falling faster than 7.5 m/s).
- **M4a.2 — Clip-driven timing.** Attack phases come from animation markers in the clip: windup = time to `hit`, active = `hit` → `hit_end`, recovery = `hit_end` → `end` (or the clip's end), all divided by `AttackData.speed`, which is capped at 1, so **no attack plays faster than its clip**. The real clips' contact frames were measured on the skeleton (the frame where the striking hand reaches furthest out); placeholders get markers from the generator. The old windup/active/recovery fields are only a fallback for a clip without markers (with a warning). Reaction lengths also come from the clips: a reaction gives control back at its `recover` marker, a knockdown lies from its `down` marker, a get-up lasts its length (each at a tunable speed).
- **Slower attacks (user request).** The real clips are longer than the M2 placeholders, and the remaining placeholders play slower (`speed` 0.6–0.8). Starting totals (windup + active + recovery): jab 0.75 s (M2: 0.42 s), cross 0.77 s, hook 1.07 s, uppercut heavy 1.29 s (M2: 1.04 s); bat swings 0.86–1.26 s, bat heavy 1.61 s; knife stab 1.00 s and 1.11 s, knife heavy 1.55 s. Thug windups: jab 0.49 s, hook 0.44 s, heavy 0.74 s.
  - **Deviation — input buffer.** A press during an attack's windup or active phase now waits until that attack's recovery (where the next one can start) instead of expiring after 0.3 s, so the combo doesn't drop inputs now that windups are longer.
- **M4a.3 — Feel, first pass (needs the playtest).** Flinch locks for about 0.5 s (clip at 1.6×), stagger 0.8–1.1 s, guard break 0.9 s, knockdown 0.8 s fall + 0.6 s down + 2.25 s get-up. **[Decided] No knockdown i-frames:** hits during a knockdown or get-up deal damage and knockback but start no new reaction (`MeleeCombat.invulnerable_when_down` = false). Reaction clips are picked at random per severity. A knocked-out NPC that recovers gets up from its back or its front, whichever way its ragdoll lies, and is turned and placed so the get-up starts where the ragdoll lies. Hit stop and camera shake values are unchanged.
- **M4a.4 — Crouch.** `crouch` action, **C**. **Toggle by default** (the proposal said "hold/toggle"; `Player.crouch_toggle = false` switches to hold). The capsule drops from 1.8 m to 1.15 m; standing up waits until there is room overhead (`PlayerMovement.can_stand()`), so a player who releases crouch under a ceiling stands up by themselves once clear. Crouched speed 1.3 m/s. Stand/crouch transition clips play when standing still; moving cancels them and the layers blend. A **low scaffold** (1.3 m clearance) in the north-east corner of the district gym yard is the test spot.
  - **Added — combat stands up first.** There are no crouched combat clips, so sprinting, jumping, guarding, attacking, dodging or being hit stands the player up (when there is room); the attack is buffered and follows. Under a ceiling, combat input waits. Crouched strafing / guard and crouching behind cover to break line of sight (M5a witnesses) are not built.
- **M4a.5 — Stomp.** The attack button (light or heavy) stomps when a knocked-out enemy lies within 1.8 m in a ±75° cone of the camera direction and no standing enemy is within 2 m (that one is attacked instead). `SoftTargeting.find_downed()` picks the body, measured to where the ragdoll lies (the hurtbox follows it). Own `AttackData` (`data/attacks/stomp.tres`) with the new `downed_damage` field: 18 downed damage, so 3 stomps kill (fists need 5 hits). Only knocked-out bodies, never dead ones; only the player stomps (`MeleeCombat.stomp_attack` is empty on NPCs). The clip is a generated placeholder.
- **M4a.6 — Inventory pause.** The Tab overlay pauses the game tree; the HUD keeps processing. Searching a body is a world action and stays real-time. Marked temporary (§12, `HUD.inventory_pauses_game`).
- **Tests:** `tests/m4a_tests.tscn` checks the "Done when" criteria headless: every clip on the combat layer and played by F4, real clips in place, tree animations resolve on player and thug; timing from markers, never faster than the clip, slower than M2; every hit window opens on the contact frame of the clip actually playing (within one frame); reaction, knockdown and get-up clips; jumps, fall loop and landings; crouch-walking under the scaffold, blocked stand-up, hold mode, standing up for combat; stomps on the intended body until it dies; the inventory pause. The M2, M3a and M3b suites still pass (their timing expectations now wait on phases instead of fixed frame counts).
- **Not decided here:** the right get-up speed is a playtest question. The new character models (`Female1.fbx`, `MaleModel1.fbx`, `MaleModel2.fbx`) were not wired up (§17, later).

### M4b — Firearms [Proposal: details]

| Task | Content | Done when |
|---|---|---|
| M4b.1 Firearm & ammo | One firearm as `WeaponData` with firearm `AttackData`; fires along the M1.4 aim raycast; ammo as a pocket item; reload | Shots hit where the crosshair points; ammo is used up and reloaded from the inventory |
| M4b.2 Weapon switching | Switch between unarmed, melee slot and firearm slot; holster/draw | Switching works mid-fight without breaking guard or aim states |
| M4b.3 Cover | Sticky cover on a button; cover edges via raycasts; peek and aim over/around; works with crouch | The player can move along, peek from and leave cover without snagging or camera clipping |
| M4b.4 Ranged enemy | Thug variant with a firearm; keeps distance and uses cover; `CombatDirector` limits simultaneous shooters | A mixed melee + ranged fight stays readable |
| M4b.5 Balance pass | Melee vs. firearm damage, range and reward (§7) | Melee stays a valid choice against a mixed group |

**Out of scope for M4b:** firearm use → heat (M5a).

### M5a — Crime fundamentals [Proposal: details]

| Task | Content |
|---|---|
| M5a.1 Crime events | `CrimeManager` + crime definitions as `.tres` (incl. assault, killing and firearm use); pickpocketing as an interaction (built on M1.5) that rolls the victim's `LootTable`; looting becomes a crime event |
| M5a.2 Witnesses | `WitnessComponent` (replaces the M3b panic reaction): field of view + line of sight; reactions: flee / call police; the report timer can be interrupted |
| M5a.3 Heat level 1 | `HeatManager`: heat level, last known position, search radius that shrinks over time; heat state on the HUD; search area on the minimap |
| M5a.4 Police response | One patrol unit walks to the last known position and searches the area; minimal arrest = cash and pocket items confiscated + respawn |

**Done when:** the full chain plays out in the district: pickpocket → seen or unseen → report or prevented → patrol searches → escape or get arrested.

### M5b — First progression loop [Proposal: details]

| Task | Content |
|---|---|
| M5b.1 WorldClock | Autoload clock, day counter, signals, "available again at" reset timestamps; HUD clock |
| M5b.2 Waiting | Benches and sit spots as `Interactable`s with "wait until…"; interrupted by heat or attacks |
| M5b.3 Interiors | First seamless interiors on the reserved lots: general store, melee shop, gun dealer back room |
| M5b.4 Shops | Buy UI driven by shop stock resources; opening hours from the clock |
| M5b.5 Shop robbery | Shopkeeper intimidation, register cash, witnesses inside; reset timer after a robbery |
| M5b.6 Heat level 2 | Foot pursuit and search area around the last sighting |
| M5b.7 First rank-up | Money/reputation threshold → first rank (depends on §6) |

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
