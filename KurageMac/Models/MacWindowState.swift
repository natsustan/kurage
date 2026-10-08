import Foundation
import Observation
import KurageCore

/// Navigation and drafts belong to this window, never to the shared account service.
@MainActor
@Observable
final class MacWindowState {
    struct Draft {
        var text = ""
        var attachments: [ComposerAttachment] = []
        var choice: RunConfigChoice?
        var pendingAttachments: [MacAttachmentSource] = []
        var isLoadingAttachments: Bool { !pendingAttachments.isEmpty }
    }

    var selectedRootID: String?
    var search = ""
    var showsChanges = false
    var newSession: NewSessionDestination?
    private var tabs: [String: String] = [:]
    private var drafts: [String: Draft] = [:]

    subscript(draft sessionID: String) -> Draft {
        get { drafts[sessionID] ?? Draft() }
        set { drafts[sessionID] = newValue }
    }

    func selectedTab(rootID: String) -> String { tabs[rootID] ?? rootID }

    func selectTab(_ id: String, rootID: String) {
        tabs[rootID] = id
    }

    func open(_ id: String, rootID: String? = nil) {
        selectedRootID = rootID ?? id
        tabs[rootID ?? id] = id
    }
}

struct NewSessionDestination: Identifiable {
    let template: SessionSummary
    let isTab: Bool
    var id: String { "\(template.id):\(isTab)" }

    static func projectTemplates(in sessions: [SessionSummary]) -> [SessionSummary] {
        var seen = Set<String>()
        return sessions.sorted {
            ($0.lastMessageAt ?? $0.lastActivityAt ?? 0) > ($1.lastMessageAt ?? $1.lastActivityAt ?? 0)
        }.filter {
            guard $0.parentSessionID == nil, let projectID = $0.projectID,
                  projectID.hasPrefix("local:") else { return false }
            return seen.insert(projectID).inserted
        }
    }
}
