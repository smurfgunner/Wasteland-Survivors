# Multiplayer Implementation Handoff

This document is the implementation handoff for the next AI session working on the multiplayer architecture in **Wasteland Survivors**.

It must be read together with:

- `MULTIPLAYER_TDD_PLAN.md`
- `AGENTS.md`
- `docs/conventions/domain-layer.md`
- `docs/conventions/concurrency.md`
- `docs/conventions/testing.md`

The original plan remains authoritative. This document records the actual implementation state, verified behavior, unfinished work, design rationale, and the exact order in which the next session should continue.

## Handoff rules

Before changing code:

1. Read this document completely.
2. Read the relevant section of `MULTIPLAYER_TDD_PLAN.md`.
3. Inspect the current source instead of relying on this document when a detail affects implementation.
4. Follow the repository architecture rules in `AGENTS.md`.
5. Use TDD: write a narrow failing behavior test, implement the smallest change, run focused tests, refactor, then run the full macOS suite.
6. Preserve unrelated work in the dirty worktree.
7. Do not change Xcode project/build configuration without asking for approval.

Use Xcode tools where possible:

- `XcodeRead` for source inspection.
- `XcodeWrite` for new Xcode project files.
- `XcodeUpdate` for targeted replacements.
- `XcodeRefreshCodeIssuesInFile` for diagnostics.
- `BuildProject(buildForTesting: true)` for compilation.
- `RunSomeTests` for focused tests.
- `RunAllTests` for the complete macOS test plan.

## Current verified baseline

At the time this handoff was written:

- The project builds successfully with tests enabled.
- The full macOS test plan passes: **132 tests passed, 0 failed**.
- The deterministic architecture suite passes: **22 tests passed**.
- No compiler diagnostics were reported in the recently changed simulation and replication files.
- The legacy `LocalMultiplayerNetworkSession` and delegate types have been removed.
- `GameScene` now depends on `MultiplayerTransport`, not the old session boundary.

The passing test count is not proof that the original plan is complete. It proves only that the currently implemented contracts and compatibility paths are green.

## What is implemented

### 1. Pure simulation foundation

Implemented under `Wasteland Survivors Shared/Simulation/`:

- `GameSimulation.swift`
- `DeterministicRandom.swift`
- `NPCDecisionSystem.swift`
- `NPCSpawnSystem.swift`
- `ProjectileResolutionSystem.swift`
- `PlayerDamageSystem.swift`
- `InteractionResolutionSystem.swift`

The simulation contains value-type state models:

- `GameState`
- `GamePlayerState`
- `GameZombieState`
- `GameChestState`
- `GamePowerUpState`
- `GameProjectileState`
- `PlayerInput`
- `GameplayEvent`
- `SimulationStep`

`GameSimulation.advance(state, inputs:, tick:)` currently supports:

- Player movement.
- Input movement normalization.
- Aim rotation updates.
- Seeded zombie spawning at deterministic ticks.
- Maximum zombie count enforcement.
- Stable NPC target selection.
- NPC movement toward the selected player.
- Melee attack damage.
- Attack cooldown tracking.
- Ranged projectile creation.
- Projectile movement.
- Projectile collision with zombies.
- Projectile expiration.
- Zombie damage and death.
- Score changes for kills.
- Zombie contact damage to players.
- Player elimination events.
- Match termination when all players are eliminated.
- Chest opening with proximity checks.
- Deterministic pistol/rifle chest reward behavior.
- Power-up collection with proximity checks.
- Duplicate power-up rejection.
- Gameplay event emission.

The simulation does not import SpriteKit. SpriteKit nodes remain presentation objects and are not authoritative state.

### 2. Deterministic seeding

`DeterministicRandom` provides stateless, entity-scoped deterministic values:

```swift
DeterministicRandom.value(
    seed: matchSeed,
    entityID: entityID,
    tick: simulationTick,
    purpose: "spawn-angle"
)
```

The value is derived from:

- Match seed.
- Stable entity ID.
- Simulation tick.
- Explicit decision purpose.

This avoids a single mutable random stream where adding one random call changes every later decision.

`NPCSpawnSystem` uses this mechanism to produce reproducible zombie IDs, angles, and spawn radii.

`NPCDecisionSystem` provides stable target selection and movement. Ties are resolved by stable player ID rather than array order.

### 3. Extracted reusable policies

The following responsibilities were extracted from `GameSimulation`:

- NPC decisions: `NPCDecisionSystem`.
- NPC spawning: `NPCSpawnSystem`.
- Projectile movement, collision, damage, kill, and expiration: `ProjectileResolutionSystem`.
- Player contact damage, elimination, and event creation: `PlayerDamageSystem`.
- Chest and power-up interactions: `InteractionResolutionSystem`.

These extractions are intentional SOLID boundaries. `GameSimulation` should coordinate policies and state transitions rather than become one large gameplay method.

### 4. Replication and snapshots

Implemented under `Wasteland Survivors Shared/Replication/`:

- `SharedReplication.swift`
- `MultiplayerSessionCoordinator.swift`
- `GameStateMultiplayerMapper.swift`
- `GameSceneStateAdapter.swift`
- `MultiplayerEntityReconciler.swift`

Implemented behavior includes:

- Versioned replication envelope.
- Explicit owner identity.
- Snapshot sequence validation.
- Snapshot history.
- Applied event deduplication.
- Explicit handshake messages.
- Host announcement.
- Join request.
- Join acceptance.
- Monotonic input sequence filtering.
- Sender identity validation.
- Stable-ID entity reconciliation.
- Mapping from `GameState` to current `MultiplayerBoardState`.
- Mapping from current SpriteKit scene caches to `GameState`.

The compatibility mapper exists so the scene can migrate incrementally while `GameState` becomes authoritative.

### 5. Transport boundary

Implemented under `Wasteland Survivors Shared/Transport/`:

- `MultiplayerTransport.swift`

The current contract exposes:

```swift
var localPeerID: String { get }
var connectedPeerIDs: Set<String> { get }
var delegate: MultiplayerTransportDelegate? { get set }
var state: MultiplayerTransportState { get }

func connect()
func disconnect()
func send(_ data: Data, to peerID: String) throws
func broadcast(_ data: Data) throws
```

`OfflineTransport` provides deterministic loopback behavior.

The MultipeerConnectivity adapter in `LocalMultiplayer.swift` now conforms to `MultiplayerTransport` and keeps MultipeerConnectivity behind the transport boundary.

The old types have been removed:

- `LocalMultiplayerNetworkSession`
- `LocalMultiplayerNetworkSessionDelegate`

`GameScene` no longer depends on those legacy types.

### 6. Current scene integration

`GameScene` currently has:

- `authoritativeGameState`.
- `GameSimulation`.
- `MultiplayerTransport` injection.
- `MultiplayerSessionCoordinator` integration.
- State adapter and mapper usage for board snapshots.
- Stable entity reconciliation for remote state.
- Host/client role gating for some simulation paths.

The migration is intentionally incomplete. Some local gameplay is still node-driven and must be moved into `GameSimulation` before the scene can be considered presentation-only.

## Test coverage currently present

### `MultiplayerArchitectureTests.swift`

Tests currently cover:

- Stateless seeded randomness.
- Entity-scoped random isolation.
- Input-order independence.
- Reproducible and bounded zombie spawning.
- Stable NPC target selection.
- Deterministic player movement.
- Invalid player input not moving another player.
- Attack cooldown behavior.
- Deterministic ranged projectile creation.
- Projectile collision and kill behavior.
- Projectile expiration.
- Melee damage and score.
- Zombie contact damage.
- Player elimination.
- Match-ended behavior.
- Living-player survival.
- Replication envelope validation.
- Snapshot history bounds.
- Exactly-once event-store insertion.
- Offline transport loopback.

### Other relevant test files

- `LocalMultiplayerTests.swift`
  - Local multiplayer menu behavior.
  - Scene integration.
  - Board snapshots.
  - Interpolation helpers.
  - Stable entity IDs.
  - Transport-backed scene behavior.

- `MultiplayerSessionCoordinatorTests.swift`
  - Handshake.
  - Host election.
  - Join acceptance.
  - Directed acceptance.
  - Transport sender validation.
  - Monotonic input sequences.

- `GameStateMultiplayerMapperTests.swift`
  - State-to-wire mapping.
  - Stable sorting.
  - Scene adapter conversion.

- `MultiplayerEntityReconcilerTests.swift`
  - Stable node reuse.
  - Creation.
  - Removal.
  - Update behavior.

## What remains, mapped to the original plan

### Original Phase 1: Extract pure simulation

Status: **partially complete**.

Completed:

- Pure state types.
- Pure simulation API.
- Player movement.
- Initial NPC behavior.
- Spawning.
- Combat basics.
- Interactions.
- Damage and game-over basics.

Remaining:

- Complete deterministic projectile behavior, including all collision edge cases.
- Add explicit weapon cooldown rules based on weapon configuration rather than relying on one general cooldown value.
- Add deterministic chest reward selection beyond the current compatibility behavior.
- Add deterministic power-up effects to simulation calculations.
- Add all gameplay rules currently still implemented in `GameScene`.
- Add fixed-tick accumulation rather than merely accepting a tick argument.
- Add deterministic state normalization/quantization if cross-device floating-point divergence appears.
- Add tests proving long-running seeded simulations remain identical.
- Add tests proving entity collection order does not affect all gameplay outcomes, not only selected cases.

### Original Phase 2: Define transport contract

Status: **mostly complete**.

Completed:

- Transport protocol.
- Connection state.
- Local peer identity.
- Connected peer identity set.
- Directed sends.
- Broadcast sends.
- Offline transport.
- MultipeerConnectivity adapter migration.
- Transport sender callbacks.

Remaining:

- Complete platform-specific MultipeerConnectivity integration tests.
- Test actual connection transitions and peer loss.
- Test transport send failures rather than ignoring them in scene code.
- Separate reliable event delivery from replaceable high-frequency state delivery.
- Decide whether MultipeerConnectivity should use separate policies/channels for events and snapshots.

### Original Phase 3: Establish authority and sessions

Status: **partially complete**.

Completed:

- Handshake.
- Protocol version.
- Session ID.
- Explicit host ID.
- Host announcement.
- Join request and acceptance.
- Directed join acceptance.
- Sender identity validation.

Remaining:

- Replace the temporary hard-coded GameScene session ID with a real session identity lifecycle.
- Define host-loss behavior.
- Define simultaneous discovery behavior across actual transport callbacks.
- Prevent a peer from becoming active before host acceptance.
- Handle duplicate joins and player membership lifecycle fully.
- Support late join state transfer.
- Support reconnect and session rejection.

### Original Phase 4: Implement input replication

Status: **not complete**.

The coordinator can validate `MultiplayerPlayerInput`, but the scene still sends legacy-style player state updates in parts of its path.

Remaining:

- Remove client-authoritative position updates from gameplay.
- Capture movement, aim, attack, chest, and power-up intent as `PlayerInput`.
- Send intent through the coordinator/transport.
- Queue inputs on the host.
- Consume inputs only at simulation tick boundaries.
- Reject invalid ownership and impossible movement.
- Handle duplicate and out-of-order inputs.
- Test dropped, delayed, duplicated, and reordered input messages.

### Original Phase 5: Implement authoritative snapshots

Status: **partially complete**.

Completed:

- Board snapshot compatibility path.
- Sequence validation.
- Host identity checks.
- Stable entity IDs.
- Mapping between scene state and multiplayer board state.

Remaining:

- Snapshot representation must carry the complete authoritative `GameState`.
- Include simulation tick, server time, input acknowledgements, and state hash.
- Include game-over state.
- Include all simulation fields needed for replay/reconciliation.
- Define full versus delta snapshot behavior.
- Publish snapshots from the authoritative host simulation rather than the current scene cache.
- Reject malformed and semantically invalid state.

### Original Phase 6: Reconcile entities

Status: **partially complete**.

Completed:

- Stable-ID entity reconciliation.
- Node reuse.
- Creation and removal.
- Zombie, chest, and power-up reconciliation helpers.

Remaining:

- Render complete `GameState`, not only the current board compatibility model.
- Preserve animation and physics presentation state during updates.
- Reconcile projectiles through authoritative state without deleting/recreating the entire projectile set.
- Add integration tests for out-of-order entity arrays and unchanged-node identity.

### Original Phase 7: Snapshot buffering and interpolation

Status: **not complete**.

Current code has interpolation helpers and stale snapshot rejection, but not the required authoritative simulation-time buffer.

Remaining:

- Store multiple snapshots by simulation tick/time.
- Define interpolation delay.
- Interpolate remote players and NPCs between snapshots.
- Handle missing snapshots.
- Handle out-of-order snapshots.
- Bound extrapolation.
- Interpolate rotation correctly.
- Smooth small corrections and recover large divergence deterministically.
- Make behavior frame-rate independent.

Suggested starting values, subject to tests and profiling:

```text
simulation tick: 60 Hz
snapshot publication: 10–20 Hz
interpolation delay: 100 ms
maximum extrapolation: 100–150 ms
```

### Original Phase 8: Local-player prediction and reconciliation

Status: **not complete**.

Remaining:

- Client-side predicted state.
- Local input history.
- Input acknowledgement in snapshots.
- Restore authoritative local state.
- Replay unacknowledged inputs.
- Smooth small corrections.
- Snap or controlled-recover large corrections.
- Tests for delay, loss, acknowledgement, and replay.

Initially implement prediction for local movement only. Keep combat outcomes and interactions host-authoritative until their deterministic simulation is complete.

### Original Phase 9: Replicate gameplay events

Status: **foundational event types exist; transport integration is incomplete**.

Remaining:

- Add reliable event messages to the replication protocol.
- Replicate projectile spawn.
- Replicate melee attack.
- Replicate zombie damage and death.
- Replicate chest opening.
- Replicate power-up collection.
- Replicate player damage and elimination.
- Replicate match end.
- Use stable event IDs.
- Apply each event exactly once.
- Ensure later snapshots contain durable event results.

### Original Phase 10: End-to-end mode tests

Status: **not complete**.

Remaining:

- Offline mode using the same simulation contract.
- Local host/client using the same simulation contract.
- Internet transport using a server stub.
- Shared fixtures for the same seed and input sequence.
- Packet manipulation tests across modes.
- Manual local multiplayer verification.

## ANR: authoritative notes and rationale for seeding

The acronym “ANR” is preserved here as the requested seeding handoff record. In this document it means the **AI Navigation Record**: the assumptions, non-negotiable rules, risks, and continuation instructions needed for another AI session to implement seeded deterministic simulation safely.

### A — Assumptions

1. The host/server is the only authority allowed to commit gameplay state.
2. Every client may predict and render locally, but predicted state is provisional.
3. Every simulation tick is deterministic and uses explicit inputs.
4. The match seed is part of the authoritative match setup.
5. Every replicated entity has a stable ID created at spawn time.
6. Random decisions are derived from seed, entity ID, tick, and purpose.
7. Entity and input collections must be processed in stable order.
8. SpriteKit is a presentation layer and must not decide authoritative outcomes.
9. A seed alone is insufficient for synchronization; clients also need the initial state, inputs, join/leave events, and periodic correction snapshots.
10. The code must remain usable for offline, local multiplayer, and future internet multiplayer.

### N — Non-negotiable rules

#### Fixed time

Do not use render-frame arrival timing as authoritative simulation time.

Use a fixed simulation tick:

```text
tick 0, tick 1, tick 2, ...
```

The next implementation should add an accumulator around `GameSimulation.advance` so variable render frame rates cannot change gameplay outcomes.

#### Stateless randomness

Do not add gameplay randomness through a shared mutable random stream.

Use:

```text
random(matchSeed, stableEntityID, simulationTick, decisionPurpose)
```

The decision purpose must be explicit, for example:

- `spawn-angle`
- `spawn-radius`
- `npc-target`
- `loot-selection`
- `power-up-drop`

Changing one decision should not shift all later random decisions.

#### Stable ordering

Sort by stable IDs before resolving operations where order matters.

Do not rely on:

- Dictionary iteration order.
- SpriteKit child order.
- Packet arrival order.
- Array order supplied by a remote peer.
- UUID generation order as an implicit gameplay rule.

#### No authoritative SpriteKit physics

SpriteKit physics may assist presentation, but authoritative collision and damage rules must be mathematical and live in the simulation layer. Physics solver timing is not a safe cross-device deterministic contract.

#### Seed plus checkpoints

A client can reconstruct deterministic NPC behavior only if it has the same:

- Match seed.
- Initial `GameState`.
- Player inputs.
- Tick progression.
- Join/leave events.
- Simulation rules.
- Random algorithm.

Periodic authoritative snapshots and state hashes are still required.

### R — Risks and continuation strategy

#### Floating-point divergence

Swift and platform math may diverge over long runs. Mitigate with:

- Simple deterministic formulas.
- Fixed ticks.
- Stable operation order.
- Position/velocity quantization where necessary.
- State hashes.
- Periodic authoritative correction.

Do not introduce fixed-point arithmetic everywhere prematurely. First measure divergence and isolate critical calculations.

#### GameScene remains partially authoritative

The largest current risk is architectural: some gameplay still occurs in `GameScene`, including legacy spawning/combat paths. Continue migrating one responsibility at a time:

1. Player movement.
2. Zombie movement.
3. Spawning.
4. Combat.
5. Projectile handling.
6. Chest interactions.
7. Power-ups.
8. Damage and game-over.

For each migration:

```text
red simulation test
→ green simulation implementation
→ scene integration test
→ remove old scene path
→ focused tests
→ full macOS suite
```

#### Compatibility mapper drift

`GameStateMultiplayerMapper` and `GameSceneStateAdapter` are temporary compatibility seams. They must not become a second source of truth. When `MultiplayerBoardState` is replaced or expanded, update the mapper tests and remove duplicate scene-specific mapping logic.

#### Transport reliability

The current transport contract supports directed and broadcast delivery, but high-frequency snapshots and reliable gameplay events are not yet separated. Do not silently treat all traffic as equivalent. Define message semantics before adding prediction.

## Recommended next implementation sequence

### Next slice 1: deterministic combat policy cleanup

Before prediction, finish simulation correctness:

1. Add weapon-specific cooldown calculation using weapon fire rate and tick rate.
2. Add explicit projectile owner and lifetime handling to wire snapshots.
3. Add projectile collision edge-case tests.
4. Add deterministic power-up effect calculations.
5. Add long-running simulation reproducibility tests.
6. Refactor duplicate nearest-target and damage logic if new cases expose it.

### Next slice 2: fixed-tick host session

Add a pure host-session object that:

- Owns authoritative `GameState`.
- Queues inputs by player ID and sequence.
- Consumes one deterministic input set per tick.
- Calls `GameSimulation.advance`.
- Emits authoritative snapshots and events.
- Records processed input sequences.

Do not connect this directly to SpriteKit first. Test it using a fake clock and fake transport.

### Next slice 3: complete snapshot contract

Add:

- Simulation tick.
- Snapshot sequence.
- Server timestamp.
- Host ID.
- Processed input acknowledgements.
- State hash.
- Complete authoritative `GameState`.
- Version compatibility.

Write malformed/stale/unauthorized snapshot tests before modifying scene application.

### Next slice 4: client prediction and reconciliation

Implement local movement prediction only:

1. Client captures input.
2. Client applies input locally.
3. Client stores input history.
4. Host acknowledges processed input sequence.
5. Client restores authoritative state.
6. Client replays inputs newer than the acknowledgement.
7. Client smooths small corrections.

Keep remote entities snapshot-interpolated rather than predicted initially.

### Next slice 5: complete scene renderer migration

Move `GameScene` toward:

```text
input capture → command submission
state receipt → state rendering
```

Delete node-driven authoritative gameplay only after equivalent simulation and integration tests pass.

## Important implementation cautions

- Do not reintroduce legacy transport protocols.
- Do not let clients send authoritative positions, health, score, kills, or pickup outcomes.
- Do not use SpriteKit physics contacts as the authoritative source of damage.
- Do not use packet arrival time as simulation time.
- Do not rebuild all nodes for every snapshot.
- Do not use a mutable global random source for deterministic NPC logic.
- Do not claim the plan is complete merely because the current test suite passes.
- Do not change project configuration without explicit user approval.
- Do not ignore compiler or test failures; investigate them with evidence.

## Final definition of done

The original plan is complete only when all of the following are true:

- One deterministic simulation supports offline, local, and internet modes.
- Host/server is the only gameplay authority.
- Clients send intent, not outcomes.
- Seeded NPC decisions are reproducible.
- Fixed ticks are used for authoritative simulation.
- Snapshots carry complete authoritative state, tick, acknowledgements, and hash.
- Clients buffer and interpolate snapshots.
- Local movement is predicted and reconciled.
- Stable IDs are used for every replicated entity.
- Gameplay events are reliable and exactly-once.
- Delayed, duplicated, reordered, and dropped packets do not corrupt state.
- Host loss, reconnect, and late join are deterministic.
- Full macOS tests pass.
- Manual local multiplayer testing shows smooth and synchronized gameplay.
- Internet transport can be added without changing simulation or SpriteKit rendering contracts.
