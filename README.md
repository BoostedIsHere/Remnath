# Remnath

## High-Level Concept

Remnath is a Rogue/Deepwoken-style permadeath action RPG set in a decaying world where **faith literally becomes power**. Players choose a “religion” tied to an instinctual drive, and their devotion fuels supernatural strength—while unseen “gods” (actually powerful ancient mortals) exploit belief to maintain control. The vibe is harsh, grounded, and unforgiving: tight, skill-based combat, meaningful wipes, and a creeping realization that the divine order is a lie.

---

## Lore Summary

Remnath is a fractured world clinging to myth. Most people believe that distant gods shape fate, grant miracles, and bless their chosen “divine soldiers.” In reality, these gods are **just extremely powerful remnants of the old world**—people who survived and learned to weaponize belief itself.

### Religions & Faith

- **Faith as a mechanic and story pillar**
  - Every player starts by choosing a religion (an instinct).
  - That religion defines how their character interprets the world and what kind of “blessings” they can eventually unlock.
  - The more you devote your character to a religion across wipes, the more “divine” you appear in the eyes of that faith.

- **The Lie of Divinity**
  - Followers think: *“My god is an all-powerful, distant being.”*
  - Reality: these gods are powerful people from the old times who:
    - Feed on worship to strengthen their influence.
    - Manipulate doctrine to create obedient “divine soldiers.”
    - Use faith as a tool to control the weak and desperate.

### Wipes, Faith & Banishment

- **Wipes**
  - Death is expected, and characters *wipe* frequently.
  - Wipes are baked into the story: each death is framed as the gods “reclaiming” their soldier—or casting them out.

- **Post-Death Choice**
  - After you die, you can:
    - **Stay with your religion**: become a more “divine soldier,” gaining stronger ties to that faith over multiple lives.
    - **Reject your religion**: lose that faith, get **banished**, and choose a new religion for that slot.

- **Becoming More Divine**
  - Staying loyal over many wipes slowly transforms you from a mortal follower into a quasi-mythic figure for that religion.
  - From the outside, you look like a chosen champion.
  - Under the hood, you’re just being reshaped by someone who’s been doing this for centuries.

---

## Religions (Current Draft)

> **Note:** Religions are currently defined at the **concept level**. Each “religion” is an **instinct**; explicit names and full pantheons are **TBD**.

### Shared Structure

All religions share the same meta-structure:

- **Player-Facing Belief**
  - “Our god is the true divine.”
  - “If I am loyal through life and death, I will ascend / be saved / be rewarded.”

- **Hidden Truth**
  - The “god” is a powerful elder being from the old world.
  - They are using faith to:
    - Recruit disposable soldiers.
    - Extend their reach across Remnath.
    - Filter out strong, obedient followers from weak ones.

- **Gameplay Identity (Global)**
  - Religions are:
    - **Class-adjacent**: they shape playstyle and perks but don’t fully replace builds.
    - **Progression paths**: loyalty across wipes unlocks stronger, more “divine” perks.
    - **Narrative levers**: your religion affects how NPCs react, what secrets you’re exposed to, and which lies you’re told.

### Current Draft: Instinct-Based Religions

Right now, the design basis is:

- **Each instinct = a religion.**
  - Players choose an instinctual path at the start (exact set and names **TBD**).

Conceptual examples (not final names):

- An **aggressive, martial instinct**
  - Offensive “divine soldier” identity.
  - Rewarded for pressure and risk.
- A **defensive / stalwart instinct**
  - Only group that uses posture mechanics.
  - Focused on blocking, countering, and outlasting enemies.
- A **cunning / deceptive instinct**
  - Feints, tricks, mobility perks.
  - Specializes in mindgames and repositioning.

For now, treat religions as **broad instinct archetypes** with:

- **Belief:** “My instinct is sacred, my god embodies it.”
- **Hidden Truth:** “Your instinct is being exploited by someone who learned how to turn that drive into a leash.”
- **Gameplay:** unique passive flavors, different risk/reward curves, and different trajectories as you become more “divine” across wipes.

---

## Core Gameplay Pillars

### Combat

- Fast, read-based, Rogue/Deepwoken-style melee combat.
- **Parry system** as the core interaction; timing and intent matter more than spam.
- **Perfect parries**:
  - Very tight timing window.
  - Intended to be hard enough to prevent extreme, unhealthy skill gaps from nolifers.
  - On success:
    - Punishes the attacker.
    - Pushes them away.
    - Grants i-frames to the defender to avoid getting dogpiled.
- **No universal posture bar**:
  - Only tanks/classes designed around posture use it.
- **Heavy/M2 attacks**:
  - Block-breaking, Rogue Lineage-like heavies that punish lazy turtling.
- **Dodges**:
  - Baseline dodge/roll for everyone.
  - Certain classes get **unique dodge variants** as perks.
- **Feinting**:
  - Intentional mindgames and delayed commits are a core part of high-level combat.

### Progression & Wipes

- Permadeath (wipes) is expected, not a failure state.
- Religions hook into wipes: loyalty and betrayal matter *over many lives*.
- Becoming more “divine” is both a power fantasy and a narrative trap.

### Exploration

- Dangerous, atmospheric world design—hostile traversal, hidden shrines, forbidden zones.
- Religious structures, relics, and cult activity act as world signposts.

### Atmosphere

- Bleak, low-trust world.
- Mistrust toward institutions, especially religious ones.
- Players slowly realize: the gods are just people with better PR and more corpses behind them.

---

## Current Implementation Status

> Snapshot of what’s already built or in active development.

### Combat Foundation

- **Fists as the prototype weapon**
  - A `Fists` Tool exists and is recognized by the combat system.
  - Used as the baseline to prototype inputs, hit detection, and animation flow.

- **Local combat handling**
  - `LocalCombatHandler` on the client:
    - Detects equipped `Fists`.
    - Handles local input events (`M1`, `M2`, etc.).
    - Bridges player input to combat logic (e.g. firing remotes / invoking combat modules).

- **Hitboxes (WIP)**
  - Initial hitbox system has been worked on (not fully polished yet).
  - Goal: tight, reliable detection for parries, perfect parries, and feints.

### Character & Animation

- **Idle animation pipeline**
  - An unarmed idle animation is stored in ReplicatedStorage (e.g. `ReplicatedStorage.Animations.UnarmedIdle`).
  - `UnarmedIdleController` (in `StarterCharacterScripts`) manages:
    - Humanoid retrieval.
    - Playing the unarmed idle anim when appropriate.
  - Known fix: idle now correctly updates body part positions according to the Animator setup.

- **StarterCharacterScripts usage**
  - Combat and animation controllers are attached via `StarterCharacterScripts`.
  - This provides a clean place for per-character systems like:
    - Unarmed idle.
    - Future dodge/parry handlers.
    - Religion/faith VFX hooks.

### Systems Planned / Design-Ready (Not Fully Implemented Yet)

- Parry & **perfect parry** logic (with i-frames and pushback on success).
- Heavy/M2 attacks that block break (Rogue Lineage-inspired).
- Class-specific dodges and feinting tools.
- Religion hooks into death/wipe flow:
  - Choosing to stay vs. renounce.
  - Tracking divinity progression per religion slot.

---

## Technical Layout

The project is organized for Rojo with a clear separation of concerns:

```text
src/
  server/           # Server-side scripts (game rules, authoritative logic)
  client/           # Client-side scripts (input, UI, client prediction, VFX)
  character/        # StarterCharacterScripts (per-character controllers)
  shared/           # Shared modules (types, configs, utility)
  modules/          # Core game systems (combat, religions, progression, etc.)
  weapons/
    fists/          # Fists weapon logic and configuration (references animations in Studio)


### Folder Roles

#### `src/server`

Server-only logic:

- Combat validation and damage application.
- Religion/wipe progression updates.
- NPC AI and world events.
- Owns the “truth” for anything that can’t be trusted to the client.

#### `src/client`

Client-side logic:

- Local input handling (clicks, keybinds, parry attempts, dodge).
- Minor client-side prediction for combat feel (e.g. local hit feedback).
- UI elements:
  - HP, stamina (if used).
  - Religious status indicators.
  - Death/wipe choice UI.

#### `src/character` (StarterCharacterScripts)

Scripts that live directly on the player’s character:

- Idle animation controllers (`UnarmedIdleController`).
- Local movement modifiers (dodges, rolls, class-specific movement).
- Cosmetic hooks (religious auras, visual changes as divinity increases).

#### `src/shared`

Shared modules accessible from both client and server:

- Config tables (damage values, timing windows, religion definitions).
- Utility modules (math, hitbox helpers, etc.).
- Type definitions and enums (weapon types, religion IDs, etc.).

#### `src/modules`

Core systems with clear APIs, for example:

- `CombatController` / combat modules:
  - Parries, perfect parries, hit resolution.
- `ReligionService` (planned):
  - Tracks faith, divinity level, banishments.
- `WipeService` (planned):
  - Handles character resets and post-death choices.

These modules should be server-driven with client proxies where needed.

#### `src/weapons/fists`

All Fists-specific content:

- Weapon config (damage, range, timings).
- References to animations by ID or path  
  *(actual Animation instances live in Studio under the Fists tool)*.
- Any Fists-specific logic (unique windups, combo rules, special effects).

This serves as the template for future weapons.

---

## Roadmap

### Short Term (Next Few Features)

#### Combat polish & reliability

- Tighten hit detection:
  - Clean up hitbox logic for Fists.
  - Ensure consistent behavior with latency and multiple players.
- Finish a basic light attack chain:
  - At least a stable M1 combo that feels responsive.
- Integrate block behavior:
  - Simple hold/block with correct interaction against M1 and M2.

#### Parry baseline

- Implement standard parry:
  - Timing window that is forgiving enough to be usable, but still skill-based.
- Scaffold perfect parry:
  - Very tight timing window.
  - On success:
    - Staggers / hits the attacker.
    - Pushes them away.
    - Grants brief i-frames to the defender to avoid getting dogpiled.

#### Movement tools

- Implement basic dodge/roll:
  - Shared baseline dodge with i-frames tuned for fairness.
- Set up hooks for class-specific dodges:
  - Data-driven approach so future classes can plug in unique dodges.

#### Religion hooks (early tech)

- Add religion data fields to player profiles.
- Implement basic on-spawn religion selection (placeholder UI is fine).
- Implement basic death/wipe flow:
  - On death → prompt: **“Remain loyal”** vs **“Renounce and be banished”**  
    (even if effects are minimal at first).

---

### Mid Term

#### Religion & Divinity Systems

- Build out `ReligionService`:
  - Track religion per character slot.
  - Track loyalty streak across wipes for each religion.
  - Track banishments and allowed re-conversions.
- Implement early divinity perks:
  - Low-tier passive bonuses for staying loyal across a few wipes.
  - Simple visual cues:
    - Minor aura.
    - Eye glow.
    - Subtle cosmetic changes.

#### Combat Depth

- Finish perfect parry behavior:
  - Camera feedback, VFX, and distinct sound cues.
  - Clear difference between normal parry vs perfect parry outcomes.
- Add feinting:
  - Cancel windows for specific attacks.
  - Intentional FP/stamina cost or timing risk so it can’t be spammed.
- Add more weapon archetypes using the Fists template:
  - At least one heavier weapon (for tanks/posture-focused builds).
  - At least one faster / trickier weapon (for feint-heavy builds).

#### Builds & Classes

- Define initial set of class archetypes:
  - **Tank:**
    - Has a posture bar.
    - Heavy emphasis on block & M2s.
  - **Non-tank builds:**
    - Lean into dodges, parries, or feints instead of posture.
- Hook classes into:
  - Unique dodge types.
  - Differing access to feints or perfect parry rewards.

---

### Long Term

#### Full Remnath Experience

##### Worldbuilding & exploration

- Multiple regions with distinct religious presence and propaganda.
- Shrines, reliquaries, and heretical hubs that reveal the truth about the “gods.”
- Events or encounters that hint at the old-world origins of these “divine” beings.

##### Religion expansion

- Fully defined set of instinct-based religions with finalized:
  - Names.
  - Doctrines.
  - Visual identities.
- Unique, high-tier divinity paths per religion that dramatically alter gameplay.
- Complex banishment/defection consequences:
  - Enemies and ex-allies reacting to your religious history.
  - Long-term narrative repercussions of loyalty vs betrayal.

##### Deeper lore reveals

- Questlines and secrets that:
  - Expose the gods as powerful mortals abusing faith.
  - Let the player directly confront or serve these beings.
- Endgame loops where the player can:
  - Become a myth within a religion.
  - Help dismantle a religion from within.
  - Or repeat the cycle—becoming the kind of monster they were fighting.

##### Systems polish

- Full refinement of combat, netcode, and feel.
- Expanded arsenal of weapons and classes.
- Richer integration of religion into every part of the experience:
  - NPC dialogue.
  - Factions.
  - Shops.
  - Dungeons.
  - PvP incentives.
