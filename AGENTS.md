# Project Guidelines

## Project Scope and Collaboration

- Kurage is an independent third-party iOS and native macOS client for Lody, not an official Lody project.
- The backend is provided by the existing Lody project through its services, APIs, and synchronization protocols. This repository develops only the clients and does not build its own backend. Use Lody's implementation and protocols as the source of truth for backend behavior.
- This project will not be submitted to Lody. Do not proactively plan upstream code submissions, pull requests, contribution workflows, or related preparation.
- Focus on this client's functionality, user experience, and protocol compatibility. Consulting Lody's implementation is for understanding the protocol and does not imply contributing upstream.

## Project Structure

- `KurageApp/`: SwiftUI app targeting iPhone and iPad, with a minimum deployment target of iOS 26 and Swift 6 strict concurrency checking.
- `KurageApp/App/`: iOS root UI and platform presentation.
- `KurageApp/Features/`: Sign-in, session list, and conversation details.
- `KurageApp/Client/`: iOS OneSignal notification integration.
- `Packages/KurageCore/`: Shared `AppModel`, domain models, `LodyClient`, live/fixture clients, authentication storage, and WebKit synchronization bridge. Both apps depend on this local Swift package; do not duplicate business logic in platform UI.
- `KurageMac/`: Native macOS 26+ SwiftUI app (not Catalyst), with one main workspace window and a separate Settings window. Window navigation and drafts live in `MacWindowState`; Changes is a default-closed inspector. No terminal or local agent execution. macOS credentials, preferences and cache are independent of iOS. Shared `AppModel` still represents one selected workspace; multi-window workspace coordination is not implemented.
- `KurageApp/Features/Conversation/ConversationQuestionCard.swift` is compiled into both app targets through `project.yml`; preserve platform-specific styling within this shared question UI.
- `SessionBridge/`: JavaScript bridge for Loro/Flock/Streams and its Node tests.
- `Packages/KurageCore/Sources/KurageCore/Resources/session-bridge.js`: Generated bridge bundle. Rebuild after changing `SessionBridge/` sources; do not edit this artifact directly. Package resources load through `Bundle.module`.
- `KurageTests/` uses Swift Testing. `KurageUITests/` uses XCTest and launches with `--fixture` for isolated test data.
- `KurageMacTests/` and `KurageMacUITests/`: macOS integration and fixture UI tests. Run `./script/build_and_run.sh` for the live Mac app or `./script/build_and_run.sh run --fixture` for isolated demo data.
- `project.yml` contains the XcodeGen project configuration. Update it for project structure or build configuration changes, then regenerate `Kurage.xcodeproj`.
- `PLAN.md` tracks feature progress, protocol reference locations, and follow-up work. Keep it updated when these change.

## Implementation Constraints

- Access data through `AppModel` and `LodyClient` from the UI, keeping the live client and fixtures clearly separated.
- Session operations must explicitly carry a workspace ID to prevent caches or updates from crossing workspace boundaries. Capture the workspace generation before starting asynchronous UI actions and validate it on completion; Stop requires both the original workspace ID and generation, including when switching away and back to the same workspace.
- Preserve cancellation, subscription cleanup when entering the background, account switching, and isolation from stale updates.
- The live client supports conversation reading, live updates, idle-session sending, running-session steer, stop, session tabs, image/file uploads, question responses, and historical/Branch file previews. Sending and starting sessions require a signed-in account with a user ID. Running input uses `session/steer`; the machine owns fallback when steer cannot be applied. Ordinary tool permission responses remain fixture-only; question responses are a separate live capability. Do not treat fixture capabilities as implemented live-service capabilities.
- Preserve outbox delivery semantics: unconfirmed sends and starts retry with their original session/turn IDs; only definitely undelivered messages may be edited. Keep draft-replacement confirmation and pending-session recovery available even when the original project template is no longer active.
- Continue using the existing secure storage for authentication credentials. Do not persist short-lived Streams tokens in Keychain or write tokens to logs or documentation.
- Bridge dependencies use pinned versions. Check protocol compatibility and WASM bundling behavior when upgrading.

## Architecture and Data Flow

- `KurageApp` creates and owns `AppModel`, injecting `HTTPLodyClient` by default or `FixtureLodyClient` when launched with `--fixture`.
- `RootView` switches between sign-in and the session list based on authentication state and initiates account restoration. Feature views should reuse existing model entry points instead of maintaining separate authentication or workspace state.
- `HTTPLodyClient` handles device authorization, account restoration, workspace requests, and Streams access tokens. Keep service addresses in `LodyEndpoints` instead of scattering endpoints through views.
- Synchronization flows from the native client through `SessionSyncBridge` to Loro/Flock/Streams in a local WebKit page. Native `URLSession` proxies network requests; JavaScript handles document synchronization and projection.
- The bridge sends conversation patches to Swift, which reconstructs complete snapshots before publishing to the UI. Preserve ordering, deletions, and growth within a turn; do not drop intermediate patches directly.
- The disk session cache stores account, workspace, and session-list display data. `AppModel` caches conversation content by workspace and session. Preserve credential association checks and sign-out cleanup to prevent displaying another account's data.
- `ConversationRunConfigState` in `KurageCore` owns shared configuration selection and consumption rules. Mac drafts hold this state per session; completion after navigation must consume the original session's selection without writing into a new account or workspace.

## Native macOS Behavior

- Losing keyboard focus must not stop synchronization. `MacRootView` keeps the model active while the scene is not backgrounded and the machine is awake; sleep/background cancels subscriptions, and wake resumes them. Workspace generation changes replace the window's scoped navigation and drafts.
- Settings opens from the sidebar gear or Command-, and does not open automatically at launch. General controls Light/Dark/System through Mac's `appTheme`; Account owns sign-out. Apply the same preference to both windows. Fixture preferences use a separate UserDefaults suite.
- Sidebar project groups are collapsible. Command-F opens a separate search panel; an empty query shows no results. Search uses title, preview, project and indexed message content; opening a result expands its project. Keep the workspace/settings footer opaque above scrolling rows and use `MacChrome` for consistent sidebar, titlebar and conversation backgrounds.
- The conversation toolbar names the project and machine; session titles belong on the always-visible tab bar. Keep tabs inside the Changes inspector boundary and aligned with the transcript column. Running/unread indicators retain accessibility values. New Tab (Command-T) requires both tab and session-creation capabilities.
- Preserve bottom-follow intent across asynchronous image loading, expanded activity groups and viewport changes, while respecting users who scroll upward. Moving the tab bar into transcript safe-area bars/insets changes scroll geometry; validate delayed-image following and read receipts when changing this layout.
- New Session (Command-N) and New Tab share the composer. Project changes preserve text and attachments while reloading configuration; New Tab keeps its parent's project. Command-Return creates, Return inserts a newline, and Escape or clicking the surrounding scrim dismisses. A failed explicit Agent selection offers an intentional fallback to the default Agent.
- Attachment imports run off the main actor, preserve security-scoped access and cancellation, and remain in memory. Clipboard file URLs take precedence over image representations. Reuse shared attachment limits and upload/outbox behavior.

## Swift and UI Conventions

- Follow existing naming and formatting: four-space indentation in Swift, UpperCamelCase for types, and lowerCamelCase for properties and methods. Follow the existing ESM and file conventions in JavaScript.
- Continue using Observation for shared application state and local `@State` for transient view state. Reuse existing feature components and avoid adding frameworks or general-purpose abstractions for small features.
- Keep Swift 6 strict concurrency checking enabled. Make main-actor isolation for UI state explicit; do not hide issues by disabling checks or casually adding `@unchecked Sendable`.
- Make asynchronous work cancellable and handle `CancellationError` correctly. Do not block the main thread during networking, retries, or view subscriptions.
- Use stable domain IDs for lists and conversation turns. Preserve row identity during streaming updates instead of rebuilding the entire conversation UI on each update.
- Use native SwiftUI navigation, menus, confirmation dialogs, and accessibility semantics. When changing layouts, check safe areas, keyboard interaction, dark mode, and usability at larger text sizes.
- Preserve conversation reading behavior: open at the latest message, follow output while at the bottom, and stop forced scrolling when the user scrolls upward.
- Communicate with the user in Chinese by default. Existing app copy is in English; keep it consistent when making changes unless the task calls for changing languages or adding localization.
- Preserve accessibility identifiers used by UI tests and update affected tests when interactions change.

## Protocols and Feature Extensions

- Device sign-in, account restoration, sign-out, workspace switching, session lists, project grouping, live conversation updates, idle-session sending, running-session steer, and new sessions in local projects are currently integrated.
- A new session copies machine, agent config, and local project from the project's most recent root session and works in the project directory (no worktree or branch). Its first turn is synced before the metadata that carries `latestUserMsgId`; only the short-lived replica that authors it may create streams. Both model and reasoning are editable for its first turn, validated again by the bridge at write time.
- Per-session model/reasoning selection applies only to the next new turn's `inputConfig`. When the agent's capability exposes a reasoning option, only reasoning is editable (switching models mid-session can invalidate provider context caches); otherwise the model is editable. Without a capability record, values are read-only.
- Conversation content projects plain text and session images (`image` and `image_group`) from users and agents. Agent tool calls are summarized as activity groups (counts and titles, never output), and a finished turn with a visible answer folds earlier work behind "Worked for …" following Lody's rules; thought text is not projected. Other structured events are not displayed. Model new content types explicitly instead of converting arbitrary events directly into prose.
- When extending live send behavior or implementing permission actions, verify request IDs, retries, deduplication, and permission semantics. Then update the protocol, live implementation, fixtures, and capability flags together; do not merely enable UI buttons. Text-send retry IDs and steer target IDs are held only in process memory.
- Prefer verified implementations or documentation as protocol references; see `PLAN.md` for reference locations. Do not guess APIs or assume paths from another repository exist in this one.
- Preserve Streams proxy host and redirect validation, backpressure, chunked UTF-8 handling, cancellation, and token refresh mechanisms.
- Maintain `SessionBridge/pnpm-lock.yaml` or SwiftPM's `Package.resolved` when changing dependencies. Do not bypass the source build by editing minified JavaScript.

## Build and Validation

- After changing project configuration, run `xcodegen generate` from the repository root.
- For the JavaScript bridge, run `pnpm install --frozen-lockfile` and `pnpm test` in `SessionBridge/`. After changing bridge code, run `pnpm build` to update the app resource.
- Example iOS build: `xcodebuild -project Kurage.xcodeproj -scheme Kurage -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build`.
- For iOS tests, first find an available simulator with `xcrun simctl list devices available`, then run `xcodebuild -project Kurage.xcodeproj -scheme Kurage -destination 'platform=iOS Simulator,id=<simulator UUID>' -derivedDataPath DerivedData test`.
- For Mac tests, use `xcodebuild -project Kurage.xcodeproj -scheme KurageMac -destination 'platform=macOS' -derivedDataPath build/Mac test`, narrowing with `-only-testing:KurageMacTests` or `-only-testing:KurageMacUITests` as appropriate.
- `script/build_and_run.sh` quits an existing KurageMac process before building, and UI tests relaunch the app. Check for a running user session before choosing these workflows; when preserving it, build directly and launch a separate fixture instance with `open -n <app-path> --args --fixture`. Report any UI tests omitted for this reason.
- Mac visual checks can add `--fixture-dark` or `--fixture-signed-out` alongside `--fixture`. Regression fixtures also cover questions, running tabs, delayed/failed images, read-receipt retries and failed/unconfirmed sends; consult `KurageMacApp` and `MacFlowTests` for current flags.
- Match validation to the change. Documentation-only changes do not require app tests. Do not report historical validation results as results from the current run.
- Fixture tests do not replace validation with a real account for continuous output, network recovery, or returning from the background. Clearly state what remains unverified.

## Choosing Validation by Change

- Model, cache, authentication, or HTTP behavior: run the relevant `KurageTests`. Prefer injected network sessions, in-memory credential stores, and isolated temporary caches over real accounts.
- JavaScript synchronization, projection, or networking bridge: run the `SessionBridge` tests and rebuild the bundle. Also validate the native bridge when changing the Swift/JavaScript message contract.
- Sign-in, session lists, or conversation interactions: run affected `KurageUITests` with `--fixture`. Inspect the app in a simulator when changing layout or scrolling.
- Mac state, attachment handling or bridge integration: run relevant `KurageMacTests`. Mac interactions/layout: run affected `KurageMacUITests` with fixtures and inspect light/dark windows, including Changes, tab-count changes and asynchronous image growth when relevant. Shared-core changes need validation on affected platforms.
- Narrow `xcodebuild test` using `-only-testing:KurageTests`, `-only-testing:KurageUITests`, or a more specific test path.
- Prioritize behavior and regression risks such as account/workspace isolation, stale updates, cancellation, disconnections, and message growth or deletion. Avoid adding unnecessary tests for simple styling or documentation changes.

## Workflow and Delivery

- Inspect relevant files and `git status` before editing, and preserve existing user changes. Keep changes focused on the task without unrelated refactoring or dependency upgrades.
- Make small, reversible implementation decisions autonomously. Explain and ask when missing information affects feature scope or data semantics.
- Do not add real credentials, private conversation content, build caches, `node_modules`, or local Xcode user state to project documentation or source files.
- After changes, describe what actually changed, validation results, and any remaining unverified behavior. Report environment limitations accurately instead of claiming checks passed.
- Treat code as the source of truth for feature status and maintain `PLAN.md` as features evolve. Historical test counts and results do not establish the current validation status.
