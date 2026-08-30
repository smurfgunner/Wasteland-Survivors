import Foundation

enum ReplicationError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidIdentity
    case unauthorizedOwner
    case staleSequence
    case malformedPayload
    case inconsistentState
}

struct AppliedEventStore: Sendable {
    private var ids: Set<String> = []
    private var insertionOrder: [String] = []
    let capacity: Int

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    mutating func insertIfNew(_ event: GameplayEvent, key: String? = nil) -> Bool {
        let eventKey = key ?? event.id
        guard !ids.contains(eventKey) else { return false }
        if insertionOrder.count >= capacity, let oldestID = insertionOrder.first {
            ids.remove(oldestID)
            insertionOrder.removeFirst()
        }
        ids.insert(eventKey)
        insertionOrder.append(eventKey)
        return true
    }
}
