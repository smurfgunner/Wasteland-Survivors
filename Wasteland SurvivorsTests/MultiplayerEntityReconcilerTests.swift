import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Entity Reconciliation")
struct MultiplayerEntityReconcilerTests {
    @Test("Reconciliation creates updates and removes by stable ID")
    func reconciliationUsesStableIDs() {
        // Given one existing entity and an incoming snapshot with one update and one new entity.
        let existing = TestEntity(id: "keep", value: 1)
        var entities = ["keep": existing]

        // When the collection is reconciled.
        MultiplayerEntityReconciler.reconcile(
            states: [
                TestState(id: "keep", value: 2),
                TestState(id: "new", value: 3)
            ],
            entities: &entities,
            id: { $0.id },
            create: { TestEntity(id: $0.id, value: $0.value) },
            update: { entity, state in entity.value = state.value }
        )

        // Then the existing object is reused, the new one is created, and absent IDs are removed.
        #expect(entities["keep"] === existing)
        #expect(entities["keep"]?.value == 2)
        #expect(entities["new"]?.value == 3)
        #expect(entities.count == 2)
    }

    @Test("Reconciliation removes entities absent from the authoritative snapshot")
    func reconciliationRemovesMissingEntities() {
        // Given a local entity that is absent from the incoming snapshot.
        let removed = TestEntity(id: "removed", value: 1)
        var entities = ["removed": removed]
        var removedEntities: [TestEntity] = []

        // When the authoritative collection is reconciled.
        MultiplayerEntityReconciler.reconcile(
            states: [TestState(id: "new", value: 2)],
            entities: &entities,
            id: { $0.id },
            create: { TestEntity(id: $0.id, value: $0.value) },
            update: { entity, state in entity.value = state.value },
            remove: { removedEntities.append($0) }
        )

        // Then the stale entity is removed and the removal hook is called once.
        #expect(entities["removed"] == nil)
        #expect(removedEntities.count == 1)
        #expect(removedEntities.first === removed)
    }

    @Test("Reconciliation preserves incoming order independently of storage order")
    func reconciliationDoesNotDependOnArrayOrder() {
        // Given entities stored in an arbitrary dictionary order.
        var entities = [
            "a": TestEntity(id: "a", value: 1),
            "b": TestEntity(id: "b", value: 2)
        ]

        // When the same states arrive in reverse order.
        MultiplayerEntityReconciler.reconcile(
            states: [
                TestState(id: "b", value: 20),
                TestState(id: "a", value: 10)
            ],
            entities: &entities,
            id: { $0.id },
            create: { TestEntity(id: $0.id, value: $0.value) },
            update: { entity, state in entity.value = state.value }
        )

        // Then both stable IDs receive their matching state.
        #expect(entities["a"]?.value == 10)
        #expect(entities["b"]?.value == 20)
    }
}

private struct TestState {
    let id: String
    let value: Int
}

private final class TestEntity {
    let id: String
    var value: Int

    init(id: String, value: Int) {
        self.id = id
        self.value = value
    }
}
