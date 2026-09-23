import Testing
@testable import Kurage

struct SessionProjectGroupTests {
    @Test func groupsByProjectIdentityAndKeepsTimeOrderWithinEachProject() {
        let sessions = [
            SessionSummary(id: "recent-prism", title: "Recent", agentName: "codex", activity: .idle,
                           preview: "", projectID: "local:machine-a:prism", projectName: "prism"),
            SessionSummary(id: "kurage-a", title: "First", agentName: "codex", activity: .idle,
                           preview: "", projectID: "local:machine-a:kurage", projectName: "kurage"),
            SessionSummary(id: "kurage-b", title: "Second", agentName: "codex", activity: .idle,
                           preview: "", projectID: "local:machine-a:kurage", projectName: "kurage"),
            SessionSummary(id: "other-prism", title: "Other clone", agentName: "codex", activity: .idle,
                           preview: "", projectID: "local:machine-b:prism", projectName: "prism"),
            SessionSummary(id: "chat", title: "Chat", agentName: "codex", activity: .idle,
                           preview: ""),
        ]

        let groups = SessionProjectGroup.make(from: sessions)

        #expect(groups.map(\.name) == ["prism", "kurage", "prism", "Chats"])
        #expect(groups[1].sessions.map(\.id) == ["kurage-a", "kurage-b"])
        #expect(groups[0].id != groups[2].id)
        #expect(groups[3].sessions.map(\.id) == ["chat"])
    }
}
