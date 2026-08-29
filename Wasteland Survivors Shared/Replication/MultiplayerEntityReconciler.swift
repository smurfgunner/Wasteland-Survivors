import Foundation

enum MultiplayerEntityReconciler {
    static func reconcile<State, Entity: AnyObject>(
        states: [State],
        entities: inout [String: Entity],
        id: (State) -> String,
        create: (State) -> Entity,
        update: (Entity, State) -> Void,
        remove: (Entity) -> Void = { _ in }
    ) {
        let incomingIDs = Set(states.map(id))

        let removedIDs = entities.keys.filter { !incomingIDs.contains($0) }
        for entityID in removedIDs {
            if let entity = entities.removeValue(forKey: entityID) {
                remove(entity)
            }
        }

        for state in states {
            let stateID = id(state)
            if let entity = entities[stateID] {
                update(entity, state)
                continue
            }

            let entity = create(state)
            entities[stateID] = entity
            update(entity, state)
        }
    }
}
