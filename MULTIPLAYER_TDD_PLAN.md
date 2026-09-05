# Multiplayer TDD Implementation Plan

## Goal

Build one multiplayer architecture that supports:

- Offline single-player.
- Local multiplayer over Apple devices.
- Future internet multiplayer.

The gameplay simulation and replication protocol must be shared across all modes. Only the transport and location of the authoritative simulation should change.

## Why we are doing this

The current implementation couples gameplay simulation, SpriteKit rendering, and network synchronization inside `GameScene`. That is acceptable for a prototype, but it makes each new multiplayer transport a second implementation of the game. It also makes clients vulnerable to flicker, stale packets, duplicated events, and divergent gameplay decisions.

We are separating these responsibilities because each mode has a different connection mechanism but the same game rules:

- Offline mode has no network and must remain responsive.
- Local multiplayer needs peer discovery and a nearby host.
- Internet multiplayer needs authentication, matchmaking, reconnection, and a server.

The shared simulation is the source of reusable gameplay rules. The shared replication layer is the source of reusable network behavior. The transport only moves encoded messages. SpriteKit only displays state and gathers player input.

This prevents the following failure modes:

- A client inventing its own zombie, score, or damage result.
- Different transports producing different gameplay behavior.
- A delayed packet moving an entity backward in time.
- Rebuilding nodes every snapshot and causing visual flicker.
- A future internet server requiring a rewrite of local multiplayer.

## How the architecture should be used

The direction of dependencies must remain one-way:

```text
GameScene -> ReplicationClient -> Transport
GameScene -> SimulationRenderer
HostSession -> GameSimulation
ServerSession -> GameSimulation
```

`GameScene` may read input and render state, but it must not decide authoritative gameplay outcomes. `GameSimulation` must never import SpriteKit. `Transport` must never know about zombies, players, scores, or scene nodes.

Every message must have a version, a message type, and an explicit owner. Messages should be validated before they affect state. Every replicated entity must have a persistent ID created when the entity is spawned, not an array index or frame number.

The host/server should run a fixed simulation tick. Network messages may arrive at any time, so they are queued and consumed at tick boundaries. Rendering may run at 60 FPS, but it must interpolate between simulation snapshots rather than assume that network delivery is synchronized with rendering.

The authoritative flow is:

```text
Input from client
    -> validate identity and sequence
    -> enqueue for host/server tick
    -> advance GameSimulation
    -> emit gameplay events and snapshot
    -> replicate to clients
    -> buffer and interpolate for rendering
```

## Implementation rules

### Keep state and rendering separate

Use immutable or value-type state for the simulation and wire protocol. Use SpriteKit nodes only as a presentation cache. A node should be created, updated, or removed based on a state diff; it should not be the source of truth.

### Treat messages according to their meaning

Use replaceable messages for frequently changing values such as positions. Use reliable messages for events that must happen once. Do not force every message through the same delivery policy.

### Make time explicit

Snapshots need a sequence number and simulation tick. Clients must discard older snapshots. Interpolation should use simulation time, not the arrival time of a packet. This ensures that a delayed packet cannot cause an entity to move backward.

### Make authority explicit

The host/server must be identified during the session handshake. A client must accept authoritative state only from that identity. The first advertiser rule must be established by the session protocol, not inferred later from arbitrary player UUIDs.

### Test with deterministic fakes

Unit tests must use a fake clock, deterministic random source, fake transport, and controlled packet delivery. Tests should be able to delay, duplicate, reorder, and drop messages. Real Bonjour, MultipeerConnectivity, and WebSocket services belong in a smaller integration-test layer.

## Target architecture

```text
Offline:
GameScene -> local GameSimulation

Local multiplayer:
Client GameScene <-> local transport <-> host GameSimulation

Internet multiplayer:
Client GameScene <-> internet transport <-> dedicated GameSimulation server
```

### Shared modules

`GameSimulation` owns platform-independent gameplay rules:

- Player movement.
- Zombie AI and spawning.
- Combat and damage.
- Chests and powerups.
- Score and game-over state.

`GameSimulation` must not depend on SpriteKit, scene nodes, physics bodies, textures, or UI.

`SharedReplication` owns:

- `PlayerInput`.
- `AuthoritativeSnapshot`.
- `GameplayEvent`.
- Message encoding and decoding.
- Sequence validation.
- Snapshot buffering.
- Entity reconciliation.
- Interpolation.
- Local prediction and reconciliation.

`MultiplayerTransport` is a protocol implemented by:

- `OfflineTransport`.
- `MultipeerConnectivityTransport` for Apple local multiplayer.
- `WebSocketTransport` for the first internet implementation.
- A future QUIC or datagram transport if required by performance testing.

## Networking rules

The host or server is authoritative for:

- Player positions after input validation.
- Zombie spawning and movement.
- Attacks, hits, and damage.
- Projectiles.
- Chest opening and powerup collection.
- Score and game-over state.

Clients send intent, not outcomes:

- Movement direction.
- Aim direction.
- Attack intent.
- Pickup or chest interaction intent.
- Monotonic input sequence number.

Clients must never send authoritative zombie health, kills, score, or final gameplay outcomes.

High-frequency state is replaceable and may use an unreliable transport:

- Player movement targets.
- Aim direction.
- Zombie positions.
- Projectile positions.

Gameplay outcomes use reliable, deduplicated events:

- Projectile spawned.
- Melee attack performed.
- Zombie damaged or killed.
- Chest opened.
- Powerup collected.
- Player damaged or eliminated.
- Match ended.

## TDD workflow

Every phase follows:

```text
Red test -> smallest implementation -> focused macOS tests -> refactor -> full macOS suite
```

The macOS test plan is the primary automated validation target. iOS test-plan work is out of scope unless explicitly requested.

For every behavior, write the observable contract before writing the implementation. A test should describe what a player or session can observe, not how a specific class happens to implement it. Keep the first failing test narrow, implement only enough production code to pass it, and then refactor while the test remains green.

Each phase is complete only when:

1. The focused tests pass.
2. The affected source has no compiler diagnostics.
3. The full macOS test plan passes.
4. The behavior is covered at the lowest practical layer and at least one real-scene integration layer where rendering or networking is involved.

## Phase 1: Extract the pure simulation

### Red

Add tests for a pure simulation that can run without SpriteKit:

- Identical initial state and inputs produce identical results.
- Fixed simulation ticks advance deterministically.
- Player movement follows input.
- Zombie spawning is bounded and deterministic.
- Combat applies the correct damage.
- Chests and powerups update state correctly.
- Score and game-over rules are deterministic.

### Green

Create `GameState`, `PlayerInput`, and `GameSimulation` as platform-independent types. Move gameplay decisions out of `GameScene` and node classes.

The simulation should expose a small API such as:

```text
initialState(seed)
advance(state, inputs, tick)
```

It should return a new or controlled state plus gameplay events. Randomness, time, and input must be injected so tests can reproduce the same match exactly. SpriteKit nodes should be built from the returned state by a separate renderer.

### Acceptance

- Simulation tests pass without constructing `SKScene`.
- Existing single-player behavior remains unchanged.

## Phase 2: Define the transport contract

### Red

Add fake-transport tests for:

- Connecting and disconnecting peers.
- Sending directed messages.
- Broadcasting messages.
- Delivery ordering.
- Delivery failure.
- Transport state changes.

### Green

Define `MultiplayerTransport` and implement `OfflineTransport` using an in-memory connection.

The transport API should expose connection state, peer identity, send-to-peer, broadcast, and received-message callbacks. It should not expose sockets, `MCSession`, URL requests, or SpriteKit types to the rest of the game. The fake transport must allow tests to hold messages and deliver them later in any order.

Keep MultipeerConnectivity behind its adapter; do not expose it to `GameScene` or `GameSimulation`.

## Phase 3: Establish authority and sessions

### Red

Test that:

- The first advertiser becomes the host.
- Later peers become clients.
- Host identity is negotiated explicitly.
- Clients reject snapshots from non-host peers.
- UUID ordering does not determine authority.
- Repeated join messages do not create duplicate players.
- Host disconnect behavior is deterministic.

### Green

Implement:

- Session handshake.
- Host announcement.
- Join request and acceptance.
- Explicit host ID.
- Connection identity.
- Host-loss behavior.

The handshake should proceed as follows:

1. A new session creates a local session ID and starts advertising or connecting.
2. The first advertiser announces a host ID and protocol version.
3. A joining peer sends a join request containing its session ID and supported version.
4. The host accepts or rejects the request.
5. The host sends an initial authoritative snapshot.
6. The client becomes a renderer/input sender only after accepting the host identity.

The protocol must define what happens when two sessions start nearly simultaneously. Use an explicit discovery timestamp or host token and deterministic tie-breaking only for that race; do not use ordinary player IDs as the normal host election mechanism.

## Phase 4: Implement input replication

### Red

Test encoding and handling of:

- Movement input.
- Aim input.
- Attack input.
- Pickup input.
- Input sequence numbers.
- Duplicate inputs.
- Out-of-order inputs.
- Invalid player IDs.

### Green

Clients send input messages. The host validates and applies them to `GameSimulation`.

Inputs should be small and frequent. A client may send its latest movement and aim input more than once, but the host must ignore duplicate sequence numbers. Attack and interaction intent should carry their own sequence or event ID so they cannot be applied twice.

Remove client-authoritative position updates from the gameplay path.

## Phase 5: Implement authoritative snapshots

### Red

Test snapshots containing:

- Simulation tick.
- Sequence number.
- Server timestamp.
- Player state.
- Zombie state.
- Chest state.
- Powerup state.
- Projectile state.
- Score.
- Game-over state.

Test that stale, duplicate, malformed, and non-host snapshots are rejected.

### Green

Implement versioned snapshot encoding, validation, and host publication at a fixed network rate.

Snapshots should contain simulation state, not presentation instructions. They should include entity IDs, positions, rotations, health, ownership where relevant, and the simulation tick. They should not contain SpriteKit actions or animation objects.

Use stable UUIDs for every replicated entity.

## Phase 6: Reconcile entities without rebuilding the board

### Red

Using real `GameScene` instances and a fake transport, test that:

- Existing nodes are reused by stable ID.
- New entities are created.
- Removed entities are deleted.
- Entity ordering does not matter.
- Zombie health updates without node replacement.
- Chests and powerups do not flicker.
- Projectiles are created and removed exactly once.

### Green

Implement ID-based entity stores and snapshot diffs. Snapshot application must not recreate unchanged nodes.

For each entity collection, build an incoming ID set and compare it with the client’s existing ID map:

```text
incoming ID absent locally -> create
incoming ID already present -> update
local ID absent from snapshot -> remove
```

Keep node identity separate from its current position. A position update must not reset an entity’s animation, physics state, or visual identity unless the authoritative state explicitly requires it.

## Phase 7: Add snapshot buffering and interpolation

### Red

Test a pure interpolation component for:

- Two-snapshot interpolation.
- Delayed snapshots.
- Missing snapshots.
- Out-of-order snapshots.
- Rotation interpolation.
- Small corrections.
- Large divergence recovery.
- Frame-rate independence.

### Green

Clients render slightly behind the newest server tick using a snapshot buffer. Interpolate remote players and world entities between snapshots.

Maintain at least two usable snapshots. Choose a render time slightly behind the newest received simulation time, then interpolate the two snapshots surrounding that render time. If only one snapshot is available, hold or extrapolate briefly with a strict limit. If a large correction is required, correct over a controlled duration instead of repeatedly teleporting.

Do not assign network positions directly during normal operation.

## Phase 8: Add local-player prediction and reconciliation

### Red

Test that:

- Local input is applied immediately.
- Inputs remain buffered until acknowledged.
- Host acknowledgements remove confirmed inputs.
- Unacknowledged inputs are replayed.
- Small corrections are smoothed.
- Large corrections recover deterministically.

### Green

Implement client prediction only for the local player. Remote players and world entities remain interpolated from authoritative snapshots.

The client keeps a short list of locally applied but unacknowledged inputs. When an authoritative player state arrives, it applies that state and replays only inputs newer than the host acknowledgement. This prevents input delay without allowing the client to become authoritative.

## Phase 9: Replicate gameplay events

### Red

Test exactly-once handling for:

- Projectile spawn.
- Melee attack.
- Zombie damage.
- Zombie death.
- Chest opening.
- Powerup collection.
- Player damage.
- Game-over transition.

Duplicate event IDs must be ignored.

### Green

Add reliable event replication separate from high-frequency snapshots. Apply events through `GameSimulation` and render the resulting state.

Events must be idempotent. Store recently applied event IDs for the current match and discard duplicates. Events should describe a gameplay fact, while the resulting durable state should also appear in a later authoritative snapshot so a reconnecting client can recover.

## Phase 10: End-to-end mode tests

### Red

Create tests for the same simulation contract in all modes:

- Offline game progresses without a transport.
- Local host and client share one board.
- Internet transport can connect clients to an authoritative server stub.
- Client movement reaches the host as input.
- Host-generated zombie, combat, chest, powerup, score, and game-over changes reach all clients.

### Green

Wire the existing SpriteKit scene to the shared simulation and replication layers.

Use the same `GameSimulation` test fixture for offline, local-host, local-client, and server-stub tests. Only substitute the transport and session owner. This proves that the modes differ in connection plumbing, not in gameplay rules.

Add `MultipeerConnectivityTransport` first, then `WebSocketTransport`.

## Internet transport roadmap

### Initial internet implementation

Use secure WebSockets for:

- Authentication.
- Lobby and matchmaking.
- Session setup.
- Reliable gameplay events.
- Initial snapshot transfer.

WebSocket state messages must still include sequence numbers and stale-message rejection. WebSockets do not remove the need for interpolation or prediction.

### Future performance option

If profiling demonstrates that WebSockets are insufficient, add a Network-framework transport using separate reliable and datagram-capable channels. This must be driven by measured packet rate, latency, bandwidth, and CPU data—not assumed performance.

## Final acceptance criteria

- One deterministic simulation supports offline, local, and internet modes.
- Host/server is the only gameplay authority.
- Clients send input intent rather than outcomes.
- Clients interpolate buffered snapshots without flicker.
- Local player movement is predicted and reconciled.
- All replicated entities use stable IDs.
- Reliable events are applied exactly once.
- Delayed, duplicated, and reordered packets do not corrupt gameplay.
- Full macOS test plan passes.
- Manual local multiplayer testing shows smooth host and client gameplay.
- Internet transport can be introduced without changing gameplay rules or SpriteKit rendering contracts.

## Definition of done for each transport

An adapter is complete only when it passes the shared transport contract tests and its platform-specific integration tests:

- Offline transport passes deterministic loopback tests.
- Local transport passes peer discovery, invitation, disconnect, and permission-path tests.
- Internet transport passes secure connection, authentication handoff, reconnect, timeout, and server rejection tests.

No transport may bypass message validation, authority checks, sequence handling, or the shared replication client.
