import Foundation
import WebKit

/// Runs Lody's Flock/Streams client in an isolated bundled WebKit page.
/// Native URLSession owns network access.
@MainActor
final class SessionSyncBridge: NSObject, WKNavigationDelegate {
    private let fetchHandler: StreamFetchHandler
    private var observers: [String: AsyncThrowingStream<ConversationUpdate, Error>.Continuation] = [:]
    private var snapshots: [String: Conversation] = [:]
    private let webView: WKWebView
    private var loadTask: Task<Void, Error>?
    private var pageNavigation: WKNavigation?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var isLoaded = false
    private var loadGeneration = 0

    init(accessProvider: @escaping @MainActor (String, Bool) async throws -> StreamsAccess) {
        fetchHandler = StreamFetchHandler(accessProvider: accessProvider)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addScriptMessageHandler(
            fetchHandler,
            contentWorld: .page,
            name: "streamFetch"
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        fetchHandler.webView = webView
        fetchHandler.onUpdate = { [weak self] id, value in self?.receive(id: id, value: value) }
    }

    func sessions(workspaceID: String, access: StreamsAccess) async throws -> [SessionSummary] {
        let operationID = UUID().uuidString
        let json = try await withTaskCancellationHandler {
            try await callBridge(
                "return await window.kurageBridgeReady.then(() => window.kurageSessions(workspaceID, baseURL, operationID))",
                workspaceID: workspaceID,
                access: access,
                arguments: ["operationID": operationID]
            )
        } onCancel: {
            Task { @MainActor [weak self] in await self?.cancelSessionRefresh(operationID) }
        }
        guard let data = json.data(using: .utf8) else { throw LodyClientError.notConnected }
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        return snapshot.sessions.map { metadata in
            SessionSummary(
                id: metadata.id,
                title: metadata.title,
                agentName: metadata.agentName,
                activity: metadata.activity == "running" ? .running : .idle,
                preview: metadata.preview,
                projectID: metadata.projectID,
                projectName: metadata.projectName
            )
        }
    }

    func conversation(
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID,
        access: StreamsAccess
    ) async throws -> Conversation {
        let json = try await callBridge(
            "return await window.kurageBridgeReady.then(() => window.kurageConversation(workspaceID, sessionID, baseURL))",
            workspaceID: workspaceID,
            access: access,
            arguments: ["sessionID": sessionID]
        )
        guard let data = json.data(using: .utf8) else { throw LodyClientError.notConnected }
        return try JSONDecoder().decode(Conversation.self, from: data)
    }

    func sendText(_ text: String, turnID: String, userID: String, sessionID: String,
                  workspaceID: String, access: StreamsAccess) async throws -> String {
        try await callBridge(
            "return await window.kurageBridgeReady.then(() => window.kurageSendText(workspaceID, sessionID, baseURL, turnID, userID, text, timestamp))",
            workspaceID: workspaceID,
            access: access,
            arguments: ["sessionID": sessionID, "turnID": turnID, "userID": userID,
                        "text": text, "timestamp": ISO8601DateFormatter().string(from: Date())]
        )
    }

    func observeConversation(sessionID: String, workspaceID: String, access: StreamsAccess) -> AsyncThrowingStream<ConversationUpdate, Error> {
        let id = UUID().uuidString
        let (stream, continuation) = AsyncThrowingStream<ConversationUpdate, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        snapshots[id] = Conversation(sessionID: sessionID, turns: [], permission: nil)
        let setup = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await callBridge(
                    "return await window.kurageBridgeReady.then(() => window.kurageObserveConversation(workspaceID, sessionID, baseURL, observationID))",
                    workspaceID: workspaceID, access: access,
                    arguments: ["sessionID": sessionID, "observationID": id]
                )
            } catch {
                observers[id]?.finish(throwing: error)
                // Cancellation may have raced the page's asynchronous module setup.
                await stopObservation(id)
            }
        }
        continuation.onTermination = { [weak self] _ in
            setup.cancel()
            Task { @MainActor in await self?.stopObservation(id) }
        }
        return stream
    }

    private func receive(id: String, value: [String: Any]) {
        guard let continuation = observers[id], let previous = snapshots[id] else { return }
        do {
            if value["error"] != nil { throw LodyClientError.notConnected }
            let data = try JSONSerialization.data(withJSONObject: value)
            let patch = try JSONDecoder().decode(ConversationPatch.self, from: data)
            let update = try patch.applying(to: previous)
            snapshots[id] = update.conversation
            continuation.yield(update)
        } catch { continuation.finish(throwing: error) }
    }

    private func stopObservation(_ id: String) async {
        observers.removeValue(forKey: id)
        snapshots.removeValue(forKey: id)
        guard isLoaded else { return }
        _ = try? await webView.callAsyncJavaScript(
            "window.kurageStopConversation(id)", arguments: ["id": id], in: nil, contentWorld: .page
        )
    }

    private func cancelSessionRefresh(_ operationID: String) async {
        guard isLoaded else { return }
        _ = try? await webView.callAsyncJavaScript(
            "window.kurageCancel(operationID)", arguments: ["operationID": operationID],
            in: nil, contentWorld: .page
        )
    }

    func close() {
        invalidatePage(with: CancellationError())
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    private func callBridge(
        _ script: String,
        workspaceID: String,
        access: StreamsAccess,
        arguments additionalArguments: [String: Any] = [:]
    ) async throws -> String {
        guard let gatewayBaseURL = access.gatewayBaseURL else { throw LodyClientError.notConnected }
        try Task.checkCancellation()
        try await ensureLoaded()
        try Task.checkCancellation()
        var arguments: [String: Any] = [
            "workspaceID": workspaceID,
            "baseURL": gatewayBaseURL.absoluteString,
        ]
        arguments.merge(additionalArguments) { _, value in value }
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
        try Task.checkCancellation()
        guard let json = result as? String else { throw LodyClientError.notConnected }
        return json
    }

    private func ensureLoaded() async throws {
        if isLoaded { return }
        if loadTask == nil {
            loadTask = Task {
                try await withCheckedThrowingContinuation { continuation in
                    guard let url = Bundle.main.url(forResource: "session-bridge", withExtension: "html") else {
                        continuation.resume(throwing: LodyClientError.notConnected)
                        return
                    }
                    navigationContinuation = continuation
                    guard let navigation = webView.loadFileURL(
                        url,
                        allowingReadAccessTo: url.deletingLastPathComponent()
                    ) else {
                        navigationContinuation = nil
                        continuation.resume(throwing: LodyClientError.notConnected)
                        return
                    }
                    pageNavigation = navigation
                }
            }
        }
        let generation = loadGeneration
        let task = loadTask
        do {
            try await task?.value
            guard generation == loadGeneration, isLoaded else {
                throw LodyClientError.notConnected
            }
        } catch {
            if generation == loadGeneration {
                loadTask = nil
            }
            throw error
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === pageNavigation, let continuation = navigationContinuation else { return }
        isLoaded = true
        navigationContinuation = nil
        continuation.resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === pageNavigation else { return }
        invalidatePage(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === pageNavigation else { return }
        invalidatePage(with: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        invalidatePage(with: LodyClientError.notConnected)
    }

    private func invalidatePage(with error: Error) {
        fetchHandler.cancelAll()
        let pending = observers.values
        observers = [:]
        snapshots = [:]
        for continuation in pending { continuation.finish(throwing: error) }
        loadGeneration += 1
        isLoaded = false
        loadTask = nil
        pageNavigation = nil
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

private struct SessionMetadata: Decodable {
    let id: String
    let title: String
    let agentName: String
    let activity: String
    let preview: String
    let projectID: String?
    let projectName: String?
}

private struct SessionSnapshot: Decodable {
    let sessions: [SessionMetadata]
}

struct StreamsHostPolicy {
    let gatewayBaseURL: URL
    let shardHostSuffix: String?

    func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.path.hasPrefix("/ds/lody/"),
              let host = url.host?.lowercased(), let gatewayHost = gatewayBaseURL.host?.lowercased()
        else { return false }
        if host == gatewayHost { return true }
        guard let suffix = shardHostSuffix?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !suffix.isEmpty else { return false }
        return host == suffix || host.hasSuffix("." + suffix)
    }
}

private final class StreamRedirectValidator: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let policy: StreamsHostPolicy
    let token: String

    init(policy: StreamsHostPolicy, token: String) {
        self.policy = policy
        self.token = token
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url.map(policy.allows) == true else {
            completionHandler(nil)
            return
        }
        var authorizedRequest = request
        authorizedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        completionHandler(authorizedRequest)
    }
}

@MainActor
final class StreamFetchHandler: NSObject, WKScriptMessageHandlerWithReply {
    private let session: URLSession
    private let accessProvider: @MainActor (String, Bool) async throws -> StreamsAccess
    private var accessByToken: [String: StreamsAccess] = [:]
    private var requests: [String: Task<Void, Never>] = [:]
    weak var webView: WKWebView?
    var onUpdate: ((String, [String: Any]) -> Void)?

    init(session: URLSession = URLSession(configuration: .ephemeral),
         accessProvider: @escaping @MainActor (String, Bool) async throws -> StreamsAccess) {
        self.session = session
        self.accessProvider = accessProvider
    }

    func cancelAll() {
        for task in requests.values { task.cancel() }
        requests = [:]
        accessByToken = [:]
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let input = message.body as? [String: Any], let command = input["command"] as? String else {
            return (nil, "Invalid Streams command")
        }
        if command == "auth", let workspaceID = input["workspaceID"] as? String {
            do {
                let access = try await accessProvider(workspaceID, input["refresh"] as? Bool ?? false)
                accessByToken[access.token] = access
                return (["token": access.token], nil)
            }
            catch { return (nil, "Streams authorization failed") }
        }
        guard let id = input["id"] as? String else { return (nil, "Missing request ID") }
        if command == "conversation", let update = input["update"] as? [String: Any] {
            onUpdate?(id, update)
            return (true, nil)
        }
        if command == "cancel" {
            requests.removeValue(forKey: id)?.cancel()
            return (true, nil)
        }
        guard command == "start", requests[id] == nil,
              let rawURL = input["url"] as? String, let url = URL(string: rawURL),
              let method = input["method"] as? String,
              ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"].contains(method),
              let headers = input["headers"] as? [String: String] else {
            return (nil, "Invalid Streams request")
        }
        guard let authorization = headers.first(where: { $0.key.lowercased() == "authorization" })?.value,
              authorization.hasPrefix("Bearer ") else { return (nil, "Invalid Streams request") }
        // Streams may redirect to a shard host. Restrict requests and redirects to
        // the configured gateway and its advertised shard suffix.
        let token = String(authorization.dropFirst("Bearer ".count))
        guard let access = accessByToken[token],
              let gatewayBaseURL = access.gatewayBaseURL,
              StreamsHostPolicy(gatewayBaseURL: gatewayBaseURL, shardHostSuffix: access.shardHostSuffix).allows(url)
        else { return (nil, "Invalid Streams request") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let encodedBody = input["body"] as? String {
            guard method != "GET", method != "HEAD", let body = Data(base64Encoded: encodedBody) else {
                return (nil, "Invalid Streams request body")
            }
            request.httpBody = body
        }
        // The Streams library owns inactivity deadlines through AbortSignal.
        request.timeoutInterval = 300
        for (name, value) in headers where name.lowercased() != "authorization" {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("Bearer \(access.token)", forHTTPHeaderField: "Authorization")
        let policy = StreamsHostPolicy(gatewayBaseURL: gatewayBaseURL, shardHostSuffix: access.shardHostSuffix)
        requests[id] = Task { [weak self] in
            guard let self else { return }
            defer { requests.removeValue(forKey: id) }
            do {
                try await Self.readResponse(session: session, request: request, policy: policy, token: access.token) { event in
                    try await self.emit(event, id: id)
                }
            } catch {
                if !Task.isCancelled { try? await emit(.error, id: id) }
            }
        }
        return (true, nil)
    }

    private enum FetchEvent: Sendable {
        case headers(status: Int, fields: [String: String])
        case chunk(String)
        case end
        case error
    }

    // Keep byte aggregation and encoding off the UI executor. Awaiting each
    // delivery preserves WebKit backpressure and the request task's cancellation.
    @concurrent
    nonisolated private static func readResponse(
        session: URLSession,
        request: URLRequest,
        policy: StreamsHostPolicy,
        token: String,
        deliver: @MainActor @Sendable (FetchEvent) async throws -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(
            for: request, delegate: StreamRedirectValidator(policy: policy, token: token)
        )
        guard let http = response as? HTTPURLResponse else { throw LodyClientError.notConnected }
        let responseHeaders = http.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let name = field.key as? String, let value = field.value as? String { result[name] = value }
        }
        try await deliver(.headers(status: http.statusCode, fields: responseHeaders))
        let isSSE = http.mimeType == "text/event-stream"
        var chunk = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if chunk.count >= 16_384 || (isSSE && byte == 10) {
                try await deliver(.chunk(chunk.base64EncodedString()))
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            try await deliver(.chunk(chunk.base64EncodedString()))
        }
        try await deliver(.end)
    }

    private func emit(_ event: FetchEvent, id: String) async throws {
        try Task.checkCancellation()
        guard let webView else { throw CancellationError() }
        var payload: [String: Any] = ["id": id]
        switch event {
        case let .headers(status, fields):
            payload["type"] = "headers"
            payload["status"] = status
            payload["headers"] = fields
        case let .chunk(body):
            payload["type"] = "chunk"
            payload["body"] = body
        case .end: payload["type"] = "end"
        case .error: payload["type"] = "error"
        }
        _ = try await webView.callAsyncJavaScript(
            "await window.kurageFetchEvent(event)", arguments: ["event": payload], in: nil, contentWorld: .page
        )
    }
}
