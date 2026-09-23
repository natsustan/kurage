import Foundation
import WebKit

/// Runs Lody's Flock/Streams reader in an isolated bundled WebKit page.
/// Native URLSession owns network access; the page only projects session metadata.
@MainActor
final class SessionSyncBridge: NSObject, WKNavigationDelegate {
    private let fetchHandler = StreamFetchHandler()
    private let webView: WKWebView
    private var loadTask: Task<Void, Error>?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var isLoaded = false

    override init() {
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
    }

    func sessions(workspaceID: String, access: StreamsAccess) async throws -> [SessionSummary] {
        guard let gatewayBaseURL = access.gatewayBaseURL else { throw LodyClientError.notConnected }
        try await ensureLoaded()
        let result = try await webView.callAsyncJavaScript(
            "return await window.kurageBridgeReady.then(() => window.kurageSessions(workspaceID, token, baseURL))",
            arguments: [
                "workspaceID": workspaceID,
                "token": access.token,
                "baseURL": gatewayBaseURL.absoluteString,
            ],
            in: nil,
            contentWorld: .page
        )
        guard let json = result as? String, let data = json.data(using: .utf8) else {
            throw LodyClientError.notConnected
        }
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
                    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                }
            }
        }
        do {
            try await loadTask?.value
            isLoaded = true
        } catch {
            loadTask = nil
            throw error
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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

@MainActor
private final class StreamFetchHandler: NSObject, WKScriptMessageHandlerWithReply {
    private let session = URLSession(configuration: .ephemeral)

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let input = message.body as? [String: Any],
              let rawURL = input["url"] as? String,
              let url = URL(string: rawURL),
              url.scheme == "https",
              url.path.hasPrefix("/ds/lody/"),
              let method = input["method"] as? String,
              method == "GET" || method == "HEAD",
              let headers = input["headers"] as? [String: String],
              headers["authorization"]?.hasPrefix("Bearer ") == true
        else {
            return (nil, "Invalid Streams request")
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 45
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (nil, "Invalid Streams response")
            }
            let responseHeaders: [String: String] = Dictionary(
                uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value in
                    guard let name = key as? String, let text = value as? String else { return nil }
                    return (name, text)
                }
            )
            return ([
                "status": http.statusCode,
                "headers": responseHeaders,
                "body": data.base64EncodedString(),
            ], nil)
        } catch {
            return (nil, "Streams request failed")
        }
    }
}
