import Foundation

/// Authenticated download of one Lody session image.
///
/// Bytes live at `/api/workspaces/{workspace}/session-images/{session}/{image}`.
/// `session` is the blob namespace, which is the conversation id unless the
/// payload names a `storageSessionId` from a fork. Thumbnails use Lody's
/// `/thumbnail` query and fall back to the original object.
enum SessionImageTransport {
    static let maxBytes = 5 * 1024 * 1024

    static func load(
        session: URLSession,
        baseURL: URL,
        workspaceID: String,
        sessionID: String,
        imageID: String,
        variant: SessionImageVariant,
        token: String
    ) async throws -> Data {
        guard Self.isResourceID(workspaceID),
              Self.isResourceID(sessionID),
              ConversationImage.isReference(imageID),
              !token.isEmpty else { throw LodyClientError.notConnected }
        do {
            return try await fetch(
                session: session, baseURL: baseURL, workspaceID: workspaceID, sessionID: sessionID,
                imageID: imageID, variant: variant, token: token
            )
        } catch let error as LodyClientError where error == .signedOut || error == .accessDenied {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard variant != .original, !Task.isCancelled else { throw error }
            return try await fetch(
                session: session, baseURL: baseURL, workspaceID: workspaceID, sessionID: sessionID,
                imageID: imageID, variant: .original, token: token
            )
        }
    }

    static func url(
        baseURL: URL,
        workspaceID: String,
        sessionID: String,
        imageID: String,
        variant: SessionImageVariant
    ) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let workspace = encode(workspaceID),
              let session = encode(sessionID),
              let image = encode(imageID) else { return nil }
        components.percentEncodedPath = "/api/workspaces/\(workspace)/session-images/\(session)/\(image)"
        switch variant {
        case .original:
            components.queryItems = nil
        case .inline:
            components.percentEncodedPath += "/thumbnail"
            components.queryItems = [
                URLQueryItem(name: "width", value: "768"),
                URLQueryItem(name: "fit", value: "scale-down"),
                URLQueryItem(name: "quality", value: "85"),
            ]
        case .square:
            components.percentEncodedPath += "/thumbnail"
            components.queryItems = [
                URLQueryItem(name: "width", value: "320"),
                URLQueryItem(name: "height", value: "320"),
                URLQueryItem(name: "fit", value: "cover"),
                URLQueryItem(name: "quality", value: "85"),
            ]
        }
        return components.url
    }

    /// Accepts only PNG, JPEG, GIF, and WebP payloads, regardless of a mismatched label.
    static func validatedImage(_ data: Data, contentType: String?) -> Data? {
        guard data.count > 0, data.count <= maxBytes else { return nil }
        let header = contentType?.split(separator: ";", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let header, header.hasPrefix("text/") || header == "application/json" || header == "application/xml" {
            return nil
        }
        guard let sniffed = sniffedMIMEType(data) else { return nil }
        if let header, ConversationImage.displayableMIMETypes.contains(header), header != sniffed {
            return nil
        }
        return data
    }

    @concurrent
    private static func fetch(
        session: URLSession,
        baseURL: URL,
        workspaceID: String,
        sessionID: String,
        imageID: String,
        variant: SessionImageVariant,
        token: String
    ) async throws -> Data {
        guard let url = url(
            baseURL: baseURL, workspaceID: workspaceID, sessionID: sessionID, imageID: imageID, variant: variant
        ), let host = baseURL.host?.lowercased(), url.host?.lowercased() == host else {
            throw LodyClientError.notConnected
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/png, image/jpeg, image/webp, image/gif", forHTTPHeaderField: "Accept")
        request.setValue(LodyEndpoints.webOrigin, forHTTPHeaderField: "Origin")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(
                for: request,
                delegate: SessionImageRedirectGuard(allowedHost: host)
            )
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            // A refused cross-host redirect also surfaces as cancellation.
            if (error as? URLError)?.code == .cancelled {
                throw LodyClientError.notConnected
            }
            throw LodyClientError.unreachable
        }
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw LodyClientError.notConnected }
        switch http.statusCode {
        case 200..<300:
            if let length = http.value(forHTTPHeaderField: "Content-Length"),
               let declared = Int(length), declared > maxBytes {
                throw LodyClientError.notConnected
            }
            var data = Data()
            do {
                for try await byte in bytes {
                    guard data.count < maxBytes else { throw LodyClientError.notConnected }
                    data.append(byte)
                }
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                if let error = error as? LodyClientError { throw error }
                throw LodyClientError.unreachable
            }
            try Task.checkCancellation()
            guard let image = validatedImage(data, contentType: http.value(forHTTPHeaderField: "Content-Type")) else {
                throw LodyClientError.notConnected
            }
            return image
        case 401:
            throw LodyClientError.signedOut
        case 403:
            throw LodyClientError.accessDenied
        default:
            throw LodyClientError.unreachable
        }
    }

    private static func isResourceID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256 && !value.contains("\0") && !value.contains("..")
            && !value.contains("/") && !value.contains("\\")
    }

    private static func encode(_ value: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed)
        return encoded?.isEmpty == false ? encoded : nil
    }

    private static func sniffedMIMEType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if bytes.count >= 12,
           bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
           bytes[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50]) {
            return "image/webp"
        }
        return nil
    }
}

final class SessionImageRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allowedHost: String

    init(allowedHost: String) {
        self.allowedHost = allowedHost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let authorization = task.originalRequest?.value(forHTTPHeaderField: "Authorization")
        completionHandler(SessionImageRedirect.request(request, allowedHost: allowedHost, authorization: authorization))
    }
}

enum SessionImageRedirect {
    /// Keeps the bearer token on same-host HTTPS redirects and drops every other target.
    static func request(_ request: URLRequest, allowedHost: String, authorization: String?) -> URLRequest? {
        guard let url = request.url,
              url.scheme == "https",
              url.host?.lowercased() == allowedHost,
              !allowedHost.isEmpty,
              url.user == nil,
              url.password == nil else { return nil }
        var authorized = request
        if let authorization {
            authorized.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        return authorized
    }
}
