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
        var isLoadingAttachments = false
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
}
