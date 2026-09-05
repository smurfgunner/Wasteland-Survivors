# Multiplayer Unfinished Work Handoff

This document is intentionally limited to work explicitly marked unfinished in
`MULTIPLAYER_AI_HANDOFF.md`. It does not restate completed work and does not
expand the multiplayer roadmap.

## Rules for the next agent

- Work test-first: add a narrow failing test, implement the smallest behavior,
  run focused tests, refactor, then run the full macOS test plan.
- Tests must use controlled fakes for time, randomness, transport, and packet
  delivery. Do not rely on real network timing for deterministic behavior.
- Do not change Xcode project or build configuration without approval.
- Preserve unrelated dirty-worktree changes.
- Do not mark an item complete because a type or helper exists. Mark it
  complete only when its observable behavior is tested at the lowest practical
  layer and, where applicable, through a real scene integration test.
- Every test failure must be investigated as either a missing behavior or a
  test defect; do not weaken an expectation to make the suite green.

## Phase 1 — Complete deterministic simulation

Implement and test the following remaining behavior:

1. Complete projectile collision behavior, including:
   - tunneling/high-speed crossing;
   - collision with multiple zombies in one step;
   - deterministic single-hit semantics;
   - collision at boundary distances;
   - expired projectiles;
   - projectile ordering independence.
2. Replace the single general attack cooldown with explicit weapon-configured
   cooldown rules and test each weapon category/configuration.
3. Define deterministic chest reward selection for every supported weapon and
   reward edge case; test repeated runs and collection-order independence.
4. Apply power-up effects inside simulation calculations, not only in scene/UI
   code; test damage, range, fire-rate, duplicate, and mixed-power-up behavior.
5. Move every gameplay rule still implemented in `GameScene` into the pure
   simulation/policy layer and add contract tests for each moved rule.
6. Integrate fixed-tick accumulation into the authoritative game loop. A render
   frame must never directly determine authoritative simulation advancement.
   Test equivalent elapsed time partitioned into 30 FPS, 60 FPS, irregular,
   and multi-tick frames.
7. Add deterministic state normalization/quantization only where required by
   demonstrated cross-platform floating-point divergence; test that it is
   deterministic and does not alter valid gameplay outcomes.

Completion criteria:

- The authoritative host advances through fixed simulation ticks.
- No authoritative gameplay rule depends on SpriteKit nodes or render-frame
  arrival timing.
- The complete simulation contract is covered by deterministic tests.

## Phase 2 — Complete transport behavior

Implement and test:

1. Platform-specific MultipeerConnectivity integration seams, using an
   injectable adapter or fake around platform callbacks.
2. Connection transitions: idle, connecting, connected, failed, and
   disconnected.
3. Peer loss and connected-peer identity updates.
4. Directed-send failures and broadcast failures, with callers observing or
   handling typed transport errors.
5. Replaceable high-frequency delivery versus reliable gameplay-event delivery.
   The delivery policy must be observable in tests.
6. Held-message transport tests that deliver messages in delayed, duplicated,
   reordered, and dropped sequences.

Completion criteria:

- Transport exposes no SpriteKit or gameplay-specific types.
- Every transport failure path is deterministic and tested.
- Reliable and replaceable delivery semantics are distinct and tested.

## Phase 3 — Complete authority and session lifecycle

Implement and test:

1. Real session identity lifecycle instead of the temporary hard-coded
   `GameScene` session ID.
2. Deterministic host-loss behavior, including the resulting role, host ID,
   queued inputs, and accepted membership.
3. Simultaneous discovery/hello callbacks in every arrival order.
4. Prevent a peer from becoming active before explicit host acceptance.
5. Complete duplicate-join and player-membership lifecycle behavior.
6. Late-join state transfer from the authoritative host.
7. Reconnect behavior and deterministic rejection of incompatible or expired
   sessions.

Required adversarial tests include:

- simultaneous hello messages with equal start times;
- duplicate hello, join request, and join acceptance messages;
- foreign session and protocol version messages;
- host disconnect before and after acceptance;
- reconnect with the same peer identity;
- reconnect with an invalid session identity;
- late join while gameplay is active.

## Phase 4 — Complete input replication

Implement and test the full intent path:

1. Remove client-authoritative position updates from gameplay paths.
2. Capture movement, aim, attack, chest, and power-up intent as `PlayerInput`.
3. Send intent through the coordinator and transport.
4. Queue host inputs and consume them only at simulation tick boundaries.
5. Validate ownership, impossible movement, invalid values, and unknown player
   IDs.
6. Handle duplicate, stale, out-of-order, delayed, and wrapped sequence
   numbers.
7. Define dropped-input behavior and test it.

Required integration tests must prove that a client sends intent and that only
the authoritative host changes gameplay state. They must fail if a client can
directly commit position, health, score, zombie, projectile, chest, or
power-up outcomes.

## Phase 5 — Complete authoritative snapshots

Implement and test snapshots that carry the complete authoritative state:

- simulation tick;
- server time;
- input acknowledgements;
- state hash;
- game-over state;
- all players and player fields;
- all zombies and NPC fields;
- all chests and opened state;
- all power-ups and effects;
- all projectiles and ownership/lifetime fields;
- score and other replay/reconciliation fields.

Also implement and test:

1. Full versus delta snapshot semantics, if both are supported.
2. Host publication from the authoritative simulation state, not a scene cache.
3. Rejection of malformed, semantically invalid, foreign-owner, stale, and
   inconsistent snapshots.
4. State-hash calculation and mismatch detection.
5. Input acknowledgement validation.

## Phase 6 — Complete entity reconciliation

Implement and test:

1. Rendering of the complete authoritative `GameState`.
2. Preservation of animation and presentation physics state during updates.
3. Projectile reconciliation by stable ID without clearing and recreating the
   entire projectile collection.
4. Out-of-order entity-array handling for every entity type.
5. Unchanged-node identity preservation for players, zombies, chests,
   power-ups, and projectiles.
6. Correct creation, update, and removal diffs when entities appear or vanish.

## Phase 7 — Complete snapshot buffering and interpolation

Implement and test an authoritative simulation-time buffer that:

1. Stores multiple snapshots by simulation tick/time.
2. Uses an explicit interpolation delay.
3. Interpolates remote players and NPCs between snapshots.
4. Handles missing snapshots without corrupting state.
5. Handles out-of-order snapshots deterministically.
6. Bounds extrapolation.
7. Interpolates rotation through the shortest angle.
8. Smooths small corrections and deterministically recovers from large
   divergence.
9. Produces equivalent results regardless of render frame rate.
10. Bounds memory/history size.

Tests must cover empty, one-snapshot, exact-tick, between-tick, before-history,
after-history, duplicate, stale, delayed, and reordered inputs.

## Phase 8 — Complete local prediction and reconciliation

Implement and test:

1. Client-predicted local movement.
2. Local input history.
3. Snapshot input acknowledgements.
4. Restoration of authoritative local state.
5. Replay of unacknowledged inputs.
6. Smooth small corrections.
7. Snap or controlled recovery for large corrections.
8. Delay, loss, duplicate, reorder, and acknowledgement edge cases.

Prediction must remain limited to explicitly supported behavior. Combat and
interactions remain host-authoritative until their deterministic simulation and
replication contracts are complete.

## Phase 9 — Complete reliable gameplay-event replication

Add reliable protocol messages and tests for:

- projectile spawn;
- melee attack;
- zombie damage;
- zombie death;
- chest opening;
- power-up collection;
- player damage;
- player elimination;
- match end.

Every event must:

1. Have a stable event ID.
2. Encode and decode without loss of fields.
3. Be applied exactly once under duplicate delivery.
4. Be ignored or rejected when unauthorized or semantically invalid.
5. Leave durable results represented in later authoritative snapshots.

## Phase 10 — Complete end-to-end mode coverage

Build deterministic shared fixtures proving that the same seed, initial state,
and input sequence produce equivalent gameplay contracts in:

1. Offline mode using the shared simulation.
2. Local host/client mode using the shared simulation and fake transport.
3. Internet-mode architecture using a server transport stub.
4. Packet manipulation scenarios across all supported modes.

Add manual local-multiplayer verification for the Apple transport separately;
do not substitute a fake transport for that manual/device check.

## Final completion gate

The unfinished work is complete only when all of the following are true:

- Every item above has an implementation and a corresponding test.
- Every newly added test has first been observed failing for the intended
  missing behavior.
- Focused macOS tests pass for each slice.
- Affected source files have no compiler diagnostics.
- The full macOS test plan passes with zero failures, skips, or unexpected
  failures.
- The handoff is updated with evidence for each item, and no unfinished item
  is marked complete based only on compilation or an indirect test.

## TDD evidence log

This section records verified work completed during the current red-green-refactor
pass. It is deliberately not a declaration that the final completion gate has
been reached; the remaining items below still require explicit implementation or
manual verification.

Verified red-green slices:

- deterministic fixed-tick simulation, swept projectile collision, collision
  ordering, cooldown configuration, deterministic rewards, power-up effects,
  input intent, and frame-partition independence;
- host-only authority, client prediction/reconciliation, input ownership,
  sequence wrap/ordering, dropped-input behavior, and rejection of legacy
  client `playerUpdate` authority;
- explicit peer-join state-transfer notification and scene integration for
  late joins;
- held transport delivery with delayed, reordered, duplicated, and dropped
  packets;
- complete board wire state including seed, cooldown bookkeeping, server time,
  acknowledgements, game-over state, entity fields, and canonical content hash;
- rejection of forged hashes, malformed entities, foreign hosts/sessions,
  unknown acknowledgement players, and backwards acknowledgement values;
- stable-ID entity reconciliation, bounded snapshot history, delayed sampling,
  bounded extrapolation, shortest-angle interpolation, and large-correction
  recovery;
- reliable gameplay-event encoding, authorization, deduplication, and match-end
  scene behavior.
- timed, seeded, capped chest spawning in the pure simulation, plus removal of
  the obsolete duplicate GameScene spawner/AI authority path;
- cross-mode deterministic fixture: direct offline inputs, local wire-message
  inputs, and server-stub JSON transport inputs all converge to the same final
  `GameState` for the same seed and input sequence.
- injectable Apple MultipeerConnectivity adapter coverage for lifecycle,
  callbacks, delivery forwarding, and typed transport errors;
- cross-mode packet manipulation coverage for held, duplicated, dropped,
  reordered, and retransmitted input packets.
- full-snapshot replacement semantics: a client removes omitted authoritative
  entities rather than retaining stale zombie or projectile nodes.

Latest verified macOS evidence:

- Build-for-testing: successful, zero reported errors.
- Full active macOS test plan: 253 passed, 0 failed, 0 skipped, 0 expected
  failures, 0 not run.
- Focused tests were run after each red-green slice, including the new chest,
  adapter, and packet-manipulation slices; affected production files reported
  zero live diagnostics.

Still explicitly open before this handoff can be marked complete:

- two-peer manual verification of actual MultipeerConnectivity gameplay
  payload exchange. The iOS scheme was launched on both iPhone 17 and iPhone
  17 Pro simulators and the Local Multiplayer flow entered gameplay. One
  earlier run exposed a connected peer state, but no received gameplay payload
  was captured. The latest controlled sequential run captured reliable
  broadcasts (`bytes=175`) from both peers, but no connected/peer-state/send/
  receive line; Peer A then terminated during the observation window. The
  captured logs contain simulator accessibility warnings and no app stack
  trace, so this remains an evidence gap rather than an inferred pass;
  the alternate iOS 26.5 simulator pair was unavailable because Xcode marked
  both destinations incompatible (`mismatched platform`) while the active SDK
  was iOS 27.0;
- any additional normalization/quantization justified by measured
  cross-platform divergence rather than assumption. No such divergence has
  been observed in the deterministic macOS fixtures, so no normalization was
  added.

Manual runtime verification was performed with the iOS scheme on iPhone 17 and
iPhone 17 Pro simulators. Both apps launched, exposed the `Local Multiplayer`
control, and entered gameplay. The hierarchy and logs are recorded in the
Xcode device-interaction artifacts. A prior run showed a connected peer; the
latest controlled run showed reliable broadcast attempts but did not establish
captured payload receipt. Actual two-peer packet exchange therefore remains an
explicit verification item rather than an inferred pass.
