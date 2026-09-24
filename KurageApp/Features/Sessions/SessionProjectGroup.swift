import Foundation

struct SessionProjectGroup: Identifiable, Equatable {
    static let unassignedID = "unassigned"

    let id: String
    let name: String
    let sessions: [SessionSummary]

    static func make(from sessions: [SessionSummary]) -> [Self] {
        var grouped: [String: [SessionSummary]] = [:]
        var names: [String: String] = [:]
        var orderedIDs: [String] = []

        for session in sessions {
            let id = session.projectID ?? Self.unassignedID
            if grouped[id] == nil { orderedIDs.append(id) }
            grouped[id, default: []].append(session)
            if names[id] == nil, let name = session.projectName, !name.isEmpty {
                names[id] = name
            }
        }

        return orderedIDs.map { id in
            Self(
                id: id,
                name: names[id] ?? (id == Self.unassignedID ? "Chats" : "Project"),
                sessions: grouped[id] ?? []
            )
        }
    }
}
