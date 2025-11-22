# Implementing Accurate Melee Weapon Hitboxes in Roblox (with Deepwoken-Style Behavior)

This document combines two pieces of research:

- **General best practices** for melee hit detection in Roblox (precision vs simple hitboxes, client vs server, performance, environment, etc.).
- A **Deepwoken-style** case study: animation-driven, moving hit volumes that feel like the weapon itself is hitting.

The goal is to give you a practical design + implementation guide for building fair, responsive melee hitboxes in a Roblox combat game (e.g. Remnath).

---

## 1. Design Goals

Melee hit detection in a PvP-heavy game needs to:

- **Feel fair**: players should be hit when the weapon visibly connects, and whiff when it clearly misses.
- **Be responsive**: hits should register quickly on the attacker’s client without “laggy” feedback.
- **Be consistent**: the same swing in the same situation should produce the same outcome.
- **Be secure enough**: don’t fully trust client reports; server must validate.
- **Be performant**: hit checks happen every swing, often every frame, with multiple players and mobs.

Deepwoken and similar games hit these goals with:

- Animation-driven, **moving hit volumes** (not static boxes).
- Per-swing **active windows**.
- Client-predicted hits, validated by the server.
- Carefully tuned radius/volume, slightly generous to cover latency and small desyncs.

---

## 2. Precision vs Simple Hitboxes

### 2.1 Precision Hitboxes (Per-Limb / Per-Weapon)

**Concept:**  
You detect hits using the actual weapon/limb geometry or a close approximation (e.g. box aligned to the sword, sphere at the blade tip, small capsule along the swing arc).

**Pros:**

- Very **accurate visually** – hits line up with what players see.
- Supports skill-based play: narrow windows for spacing, dodging, etc.
- Better for games where *weapon spacing and timing matter* (Souls-like, Rogue/Deepwoken style).

**Cons:**

- Slightly more complex to implement.
- More CPU-heavy if done naively (many raycasts / overlaps per frame).
- Requires careful tuning to avoid “near-miss but no hit” frustration.

### 2.2 Simple Bounding Volumes (Box/Sphere Around Attacker)

**Concept:**  
You use a single large box or sphere in front of the character (or around them) to detect hits, often triggered once per swing.

**Pros:**

- Very easy to implement.
- Cheap to compute (one `GetPartBoundsInBox` or `Magnitude` check per tick).
- Good enough for casual or arcade-y combat.

**Cons:**

- Can feel **sloppy** or unfair:
  - You “hit” someone even though the weapon visibly missed.
  - You “miss” when the blade looked like it clipped them.
- Harder to convey precise spacing/skill like Deepwoken or Rogue Lineage.
- Players may feel like they’re fighting the hitbox, not the animation.

### 2.3 Practical Takeaway

For a game like Remnath, you want:

- **Per-weapon, shape-based hitboxes**, tuned per swing.
- For Fists: small boxes/spheres in front of the character.
- For weapons: capsules/boxes aligned with the blade / swing arc.

You can still be **slightly generous** with size to compensate for latency and animation desync, but avoid giant cubes.

---

## 3. Client vs Server Hit Detection

A key decision is where to actually run the hit detection.

### 3.1 Fully Server-Side Detection

**Pros:**

- Harder to cheat: server never trusts the client.
- Single source of truth.

**Cons:**

- Feels laggier: client has to wait for the server to confirm.
- Visual desync is more likely (animation on client vs hitbox on server).
- With many players, naive per-frame server checks can be heavy.

### 3.2 Fully Client-Side Detection (Not Recommended Alone)

**Pros:**

- Very responsive – hits register instantly.
- Easy to align hitchecks with local animation.

**Cons:**

- Extremely easy to exploit if you trust it blindly (teleport hits, extended range).
- Server must still trust client reports or re-check everything anyway.

### 3.3 Hybrid: Client-Predicted, Server-Validated (Recommended)

**Pattern:**

1. **Client:**
   - Drives animation.
   - Runs hit detection (shape casts / overlap checks) every frame during the active swing window.
   - On each detected hit, sends a RemoteEvent to the server:
     - Attacker,
     - Target,
     - Attack type / ID,
     - Optional hit position.

2. **Server:**
   - Receives hit report.
   - Validates:
     - Target is still alive / in the game.
     - Target is within the allowed range from attacker (from weapon config).
     - Optional: re-run a **smaller** shape/range check.
   - If valid, applies damage/knockback using shared config.
   - If invalid, ignore or clamp (e.g. cap extra distance).

**Benefits:**

- Great feel (client sees immediate feedback).
- Server maintains authority over *what actually counts*.
- Can mitigate lag with slightly generous hit volumes but still punish obvious cheating.

---

## 4. Deepwoken-Style Hit Detection

Deepwoken doesn’t appear to use one static cube for the entire swing. Instead, players report:

- The **blade** feels like it’s actually hitting in the animation space.
- Multiple enemies in the swing arc are damaged simultaneously (AoE).
- Dev communication mentions “standard spherical hitboxes” and shape casting.

### 4.1 Animation-Driven, Moving Hit Volumes

For each swing:

1. The weapon enters an **active window** (HitStart → HitStop).
2. During this window, every frame:
   - A **volume** (sphere, box, or capsule) is placed relative to the weapon/character.
   - The volume **moves with the weapon** as the animation plays.
   - The game checks which characters are inside that volume.

If multiple enemies are inside, they’re all hit at once (no “only the first hit” logic unless designed that way).

For swords:

- A **capsule** or multiple spheres along the blade.
- Or a single sphere at the tip with radius matched to the blade length.

For punches:

- Small sphere/box in front of the fists, following the arm movement.

### 4.2 ShapeCast vs Raycast vs Overlap

Deepwoken likely uses Roblox’s advanced **ShapeCast / BlockCast / SphereCast** APIs or `GetPartBoundsInBox`-style queries:

- **ShapeCast / BlockCast / SphereCast:**
  - Casts an entire volume at once.
  - Great for “hit everything the blade moves through.”
- **Overlap (GetPartBoundsInBox / GetPartBoundsInRadius):**
  - Check all parts inside a region.
  - Also effective for per-frame volume checks.
- **Raycast:**
  - You *can* use many rays, but it’s more complex and heavier if you want full coverage.

For Deepwoken-like feel, a **volume-based method** (sphere/block/capsule per frame) is the closest match.

### 4.3 Hit Windows and Per-Swing State

Typical per-swing lifecycle:

1. **Attack start:**
   - Animation begins.
   - Damage is not active yet.

2. **HitStart frame:**
   - The swing reaches the contact portion.
   - Hitbox for that attack is “armed” – detection begins.

3. **Active frames:**
   - Each frame:
     - Compute volume position/rotation from weapon or HumanoidRootPart CFrame.
     - Run ShapeCast / overlap to find targets.
     - For each target not in `alreadyHit`:
       - Add to `alreadyHit`.
       - Fire hit event to server.
   - Very short window for a fast, snappy feel.

4. **HitStop frame:**
   - Disable hit detection for that swing.
   - Clear `alreadyHit`.

5. **Recovery:**
   - Animation finishes, no more hit checks.

---

## 5. Practical Roblox Implementation Pattern

Below is a generic approach you can plug into your game.

### 5.1 Shared Configuration (Per Weapon)

For each weapon (including Fists), keep all tuning in a module, e.g.:

```lua
-- src/weapons/fists/Config.luau
local FistsConfig = {
    Range = 8,                         -- max distance from attacker root
    HitboxSize = Vector3.new(4, 5, 4), -- box size for GetPartBoundsInBox or BlockCast
    HitboxOffset = CFrame.new(0, 0, -4), -- local space offset in front of root
    ActiveTime = 0.15,                 -- how long hitbox is active for M1
    WindupTime = 0.1,                  -- pre-hit delay
    RecoveryTime = 0.2,                -- post-hit delay
    Damage = 10,
    KnockbackForce = 35,
}
return FistsConfig
