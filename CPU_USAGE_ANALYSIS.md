# CPU Usage Analysis

## Executive summary

The current game is small enough to remain playable, but it performs avoidable work every rendered frame and relies heavily on `SKShapeNode`, transient node allocation, and SpriteKit physics. The largest likely CPU cost is not a single algorithm; it is the combination of a 120 FPS update rate, per-frame enemy and targeting scans, vector-path rendering, physics contacts, and frequent creation/destruction of effect and projectile nodes.

This is a static code analysis, not an Instruments trace. The priorities below are based on code-path frequency, allocation behavior, and known SpriteKit cost characteristics. Actual percentages and millisecond savings must be established with Time Profiler, Core Animation, and SpriteKit instrumentation on representative devices.

## Scope reviewed

The review covers the gameplay loop and its direct CPU consumers:

- `GameScene.update(_:)`, spawning, cleanup, and contact handling
- Enemy movement and attack evaluation
- Combat target selection, melee hit resolution, and projectile creation
- Zombie, projectile, terrain, HUD, and effect nodes
- SpriteKit view configuration
- The separate `MetalGameRenderer` frame path

## Current frame workload

At up to 120 frames per second, `GameScene.update(_:)` performs the following while the game is active:

1. Resolves player movement and moves the camera.
2. Evaluates health regeneration.
3. Iterates every living zombie, updates its movement, calculates distance to the player, and checks attack timing.
4. Checks the weapon cooldown and, when ready, scans zombies to select a target.
5. Creates attack nodes and effects when firing or hitting.
6. Checks both spawn timers.
7. Scans the zombie and chest arrays for cleanup.

With the current cap of 18 zombies, the algorithmic load is bounded. However, requesting 120 FPS approximately doubles frame-loop invocations compared with 60 FPS, including frames where the additional simulation frequency may not produce a visible gameplay benefit.

## Findings and recommendations

### P0 — Establish a measured baseline

No reliable CPU percentage can be assigned from source inspection alone. Profile a Release build on the oldest supported physical device and capture at least these scenarios:

- Idle immediately after launch
- Moving with the maximum zombie count
- Sustained pistol fire
- Sustained shotgun fire
- Repeated melee attacks into a group
- Multiple simultaneous hit/death effects
- Game-over state

Record average CPU, peak CPU, frame time, dropped frames, live node count, physics time, and allocation rate. Add signposts around enemy update, combat, spawning/cleanup, and effects if the profiler cannot separate them cleanly. Use the measurements to validate each optimization independently.

### P1 — Reconsider the unconditional 120 FPS target

The iOS controller sets `preferredFramesPerSecond` to `120`. This causes the scene update, enemy scans, combat checks, cleanup predicates, SpriteKit evaluation, and display submission to run at up to twice the frequency of a 60 FPS configuration.

Recommended action:

- Measure 60, 80, and 120 FPS on ProMotion hardware.
- Default to 60 FPS unless testing shows a meaningful user-visible benefit at higher rates within the CPU and energy budget.
- If high refresh rate is retained, decouple expensive AI/targeting work from rendering and run it at a lower fixed frequency.
- Pause or reduce rendering when the app is inactive and avoid continuous simulation after game over where possible.

Expected impact: high, because it reduces the frequency of nearly every recurring CPU cost.

### P1 — Replace persistent `SKShapeNode` content with cached textures or sprites

Terrain decorations, zombie bodies and health bars, projectiles, muzzle flashes, hit flashes, chest sparks, overlays, joystick controls, and much of the HUD are constructed with `SKShapeNode`. Shape nodes retain vector geometry and can be substantially more CPU-expensive than textured sprites, especially when many remain visible or animate simultaneously.

The terrain setup creates a large static grid across a radius of 3,000 points. Although construction occurs once, those shape nodes remain in the scene graph for traversal and rendering. Zombies also contain several shape children each, multiplying node count at the busiest point in play.

Recommended action:

- Rasterize reusable visuals once and render them as `SKSpriteNode` instances.
- Use a small texture atlas for zombies, projectiles, terrain marks, muzzle flashes, hit effects, and particles.
- Precompose static terrain into tiles or a small number of cached textures rather than hundreds of individual nodes.
- Keep vector nodes only where their geometry must change dynamically and profiling shows the cost is acceptable.

Expected impact: high for render preparation, scene traversal, and energy use.

### P1 — Reduce transient allocations with pooling and particle reuse

Every shot can allocate a projectile node, physics body, shape child, action graph, and—for muzzle flash—another shape node and action graph. Every zombie hit creates a new hit node. Every death creates a label. Opening a chest creates 12 individual shape nodes and action sequences.

At sustained fire rates these short-lived objects increase allocation/deallocation traffic and scene graph mutation. Shotgun fire amplifies the projectile cost by creating three projectiles per attack.

Recommended action:

- Pool projectile nodes and reset their position, physics state, appearance, and lifetime before reuse.
- Pool common hit and muzzle-flash sprites.
- Replace the 12-node chest burst with an `SKEmitterNode` using a cached texture, or use a bounded particle pool.
- Cache reusable `SKAction` instances where their parameters are constant.
- Verify that pooled objects are fully reset and cannot preserve stale actions, contacts, alpha, scale, or physics velocity.

Expected impact: medium to high during combat bursts; it should also reduce frame-time spikes.

### P1 — Avoid redundant distance and trigonometric calculations

Enemy behavior calculates `atan2`, `hypot`, `cos`, and `sin` for every living zombie on every frame. The use case then calculates the player distance a second time to decide whether the same zombie can attack. Target selection and melee resolution are also likely to calculate distances or angles during attack events.

Recommended action:

- Calculate `dx`, `dy`, and squared distance once per zombie update and reuse them for movement and attack range checks.
- Compare squared distances against squared ranges when an exact distance is unnecessary.
- Normalize only when movement is actually required.
- Derive movement directly from a normalized delta vector, avoiding an angle followed by `cos` and `sin`.
- Pass computed spatial data to attack evaluation rather than recalculating it in another layer.

Expected impact: medium. The enemy cap limits total work today, but this becomes more important if enemy counts increase.

### P1 — Throttle AI and target acquisition independently of display refresh

Zombie steering currently runs once per rendered frame. Target acquisition scans the zombie collection whenever the weapon cooldown permits firing. Neither task generally needs 120 Hz evaluation.

Recommended action:

- Use a fixed simulation cadence for AI, such as 20–30 Hz, while interpolating or continuing simple movement each frame.
- Cache the current combat target until it dies, leaves range, or a short retarget interval expires.
- Consider a simple spatial grid only if profiling or a larger enemy cap demonstrates that linear scans are a bottleneck. With 18 zombies, a spatial index may add more complexity than value.

Expected impact: medium to high at high refresh rates.

### P2 — Tighten physics work

Each zombie and projectile has an active physics body. Zombies collide with other zombies and request contacts with projectiles and the player. The game also moves zombie node positions manually while their bodies are dynamic, which makes SpriteKit reconcile user-driven transforms with physics simulation. Player damage is already determined by an explicit distance check, so player/zombie physics contacts appear unnecessary unless another behavior depends on them.

Recommended action:

- Remove contact-test pairs that are not handled.
- If zombies are fully kinematic under game logic, evaluate using non-dynamic bodies or a non-physics collision/separation approach.
- If zombie-to-zombie collision is required, measure its cost at the maximum population and consider cheaper local separation logic.
- Keep projectile contact masks as narrow as possible.
- Enable precise collision detection only if tunneling is observed and the measured cost is acceptable.

Expected impact: medium, with the largest benefit at maximum enemy/projectile counts.

### P2 — Make cleanup event-driven

The frame loop runs `removeAll(where:)` over both zombie and chest arrays on every active frame, even though removal is infrequent. At current caps this is small, but it is unnecessary recurring work and copies/mutates array storage when removals occur.

Recommended action:

- Remove model references when death/open animations complete, or mark collections dirty and compact them at a low frequency.
- If callbacks complicate ownership, compact only when a death or chest opening has occurred.

Expected impact: low at current caps, but straightforward and predictable.

### P2 — Avoid duplicate or always-on diagnostic rendering

The iOS view enables `showsFPS` and `showsNodeCount`. These overlays are useful during development but should not be enabled in production builds.

Recommended action:

- Gate SpriteKit diagnostic overlays behind `#if DEBUG` or a runtime diagnostics flag.

Expected impact: low, with a cleaner production rendering path.

### P2 — Review HUD update frequency and text rasterization

SpriteKit label text changes trigger text work. The health HUD is updated only when health changes or regenerates, which is directionally correct, but regeneration may cause repeated updates at frame frequency depending on `PlayerNode.updateHealth`. Each update also rebuilds the displayed string and adjusts shape geometry.

Recommended action:

- Update the label only when the displayed integer health value changes.
- Update the bar only when its visual ratio changes beyond a small threshold.
- Prefer sprite-based bar elements over shape nodes after measuring.

Expected impact: low to medium if regeneration currently updates continuously.

### P2 — Bound delta time

The scene uses the raw interval since the previous update. After a pause, debugger stop, or scheduling stall, a large delta can produce a large movement step and increase physics/contact work for the recovery frame.

Recommended action:

- Clamp simulation delta time to a safe maximum or use a fixed-step accumulator with a maximum number of catch-up steps.

Expected impact: primarily frame stability and correctness rather than average CPU.

## Metal renderer analysis

`MetalGameRenderer.draw(in:)` calls its frame callback, creates a new Swift vertex array, appends six vertices per renderable, copies the entire array through `setVertexBytes`, then creates and commits a command buffer every frame.

Likely CPU costs include:

- Rebuilding identical quad topology each frame
- Repeated Swift array growth/initialization despite `reserveCapacity`
- Per-renderable `append(contentsOf:)` temporary construction
- Copying all vertex data through `setVertexBytes`
- Requesting a drawable and encoding a pass even if scene state did not change

Recommended action if this renderer is active in the shipping path:

- Use persistent, ring-buffered `MTLBuffer` storage sized for the maximum renderable count.
- Write vertices directly into mapped buffer memory or use instanced rendering with one static unit quad plus per-instance position, size, and color.
- Reuse immutable geometry and update only instance data.
- Establish whether CPU or GPU is limiting before increasing batching complexity.
- Avoid running both SpriteKit and a separate Metal display loop for the same content unless the architecture requires it and profiling justifies the cost.

The reviewed platform controllers currently present a SpriteKit scene; the actual integration and runtime use of `MetalGameRenderer` should be confirmed before prioritizing changes to it.

## What is already bounded or reasonable

- Zombie and chest counts are capped at 18 and 8 respectively.
- Spawn checks are constant-time and inexpensive.
- Combat targeting is gated by the weapon cooldown rather than executed unconditionally every frame.
- Dead zombies disable their physics bodies before their removal animation.
- Projectile lifetime is bounded.
- Most effects remove themselves after short animations.
- Arrays are passed by value but use Swift copy-on-write storage, so read-only parameter passing does not inherently copy their elements.

These choices prevent unbounded growth, but they do not eliminate high-frequency rendering and allocation costs.

## Recommended implementation order

1. Capture an Instruments baseline and save reproducible scenarios.
2. Compare 60 FPS with 120 FPS and choose an explicit frame/energy budget.
3. Disable production debug overlays.
4. Throttle enemy AI and target acquisition; reuse spatial calculations.
5. Convert persistent shape-heavy scene content, beginning with terrain and zombies, to cached sprites.
6. Pool projectiles and frequent combat effects; replace chest sparks with a bounded emitter or pool.
7. Reduce physics masks and reconcile manual movement with physics-body configuration.
8. Make collection cleanup event-driven and coalesce HUD updates.
9. Optimize the Metal path only after confirming that it is active and appears in measured CPU stacks.
10. Re-profile after each isolated change and retain only changes with measurable improvement and no gameplay regression.

## Verification criteria

An optimization should be considered successful only when all of the following hold:

- Affected unit tests pass and deterministic gameplay behavior remains unchanged.
- Maximum-zombie combat has equal or lower average CPU and improved or unchanged frame pacing.
- Allocation rate and live node count do not grow over repeated combat/restart cycles.
- Projectile hits, melee arcs, chest rewards, health regeneration, enemy attacks, and death cleanup remain correct.
- Visual regression snapshots remain acceptable where intentional sprite substitutions occur.
- Results are verified on physical hardware in a non-Debug build.

## Conclusion

The strongest initial opportunities are to lower unnecessary frame frequency, reduce `SKShapeNode` usage, eliminate transient combat allocations, and run AI/spatial work less often with reused calculations. These changes attack recurring costs across the whole frame rather than micro-optimizing the already bounded array loops. Instruments measurements should determine the final order and quantify the benefit.
