import SwiftUI

@main
struct KurageApp: App {
    @State private var model: AppModel

    init() {
        let client: any LodyClient = ProcessInfo.processInfo.arguments.contains("--fixture")
            ? FixtureLodyClient(records: ProcessInfo.processInfo.arguments.contains("--fixture-subtasks")
                ? SessionRecord.samplesWithSubtasks
                : ProcessInfo.processInfo.arguments.contains("--fixture-questions")
                    ? [SessionRecord.questionSample] + SessionRecord.samples
                    : ProcessInfo.processInfo.arguments.contains("--fixture-running-tab")
                        ? SessionRecord.samplesWithRunningTab : SessionRecord.samples,
                failingConversationIDsOnce:
                ProcessInfo.processInfo.arguments.contains("--fixture-search-failure") ? ["session-long"] : [],
                conversationDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-conversation") ? .seconds(3) : nil,
                failStartAndArchiveProjectOnce: ProcessInfo.processInfo.arguments.contains("--fixture-start-unconfirmed"),
                sendDelay: ProcessInfo.processInfo.arguments.contains("--fixture-tab-send") ? .seconds(15)
                    : ProcessInfo.processInfo.arguments.contains("--fixture-slow-send") ? .seconds(3) : nil,
                startDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-start") ? .seconds(8) : nil,
                failSendOnce: ProcessInfo.processInfo.arguments.contains("--fixture-send-unconfirmed"),
                rejectSendOnce: ProcessInfo.processInfo.arguments.contains("--fixture-send-rejected"),
                failTabStartOnce: ProcessInfo.processInfo.arguments.contains("--fixture-tab-start-unconfirmed"),
                skillRefreshDelay: ProcessInfo.processInfo.arguments.contains("--fixture-skill-refresh") ? .seconds(3) : nil,
                mentionDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-mentions") ? .seconds(6) : nil,
                failSkillRefreshOnce: ProcessInfo.processInfo.arguments.contains("--fixture-skill-refresh"),
                authorizationDelay: ProcessInfo.processInfo.arguments.contains("--fixture-browser")
                    ? ProcessInfo.processInfo.arguments.contains("--fixture-pending-authorization") ? .seconds(600) : .seconds(12)
                    : nil,
                streamsConversationUpdates: true,
                failFilePreviewOnce: ProcessInfo.processInfo.arguments.contains("--fixture-file-preview-failure"),
                filePreviewUnavailableReason: ProcessInfo.processInfo.arguments.contains("--fixture-file-preview-too-large")
                    ? "too_large" : nil,
                filePreviewDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-file-preview")
                    ? .seconds(3) : .milliseconds(200),
                filePreviewLargeRewrite: ProcessInfo.processInfo.arguments.contains("--fixture-file-preview-large-rewrite"),
                failBranchSwitchOnce: ProcessInfo.processInfo.arguments.contains("--fixture-branch-switch-failure"),
                dirtyProject: ProcessInfo.processInfo.arguments.contains("--fixture-dirty-project") ? "local:machine-1:prism" : nil)
            : HTTPLodyClient()
        _model = State(initialValue: AppModel(client: client))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
