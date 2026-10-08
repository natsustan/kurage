import Foundation

/// The explicit projection of Lody's system_notice / chat_failed metadata.
public struct ConversationError: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var reason: String? = nil
    public var code: String? = nil
    public var message: String? = nil

    public var title: LocalizedStringResource {
        if code == "git_executable_not_found" { return "Git executable was not found on the target machine" }
        switch reason {
        case "session_archived": return "Session is archived"
        case "agent_type_mismatch": return "Agent type mismatch"
        case "session_init_failed": return "Session initialization failed"
        case "session_restore_failed": return "Failed to restore session"
        case "session_not_found": return "Session not found"
        case "memory_pressure": return "The machine is low on memory"
        case "acp_not_ready": return "Agent session was not ready"
        case "agent_disconnected": return "Agent disconnected unexpectedly"
        case "agent_no_output": return "The agent ended the turn without producing any output"
        case "turn_pre_prompt_failed": return "Failed before the agent could start"
        case "message_delivery_failed": return "Message delivery failed"
        case "machine_access_denied": return "Machine access denied"
        case "acp_auth_required": return "Authentication required"
        case "acp_internal_error": return "Agent internal error"
        case "acp_upstream_api_error": return "Upstream API error"
        case "acp_provider_overloaded": return "Selected model is at capacity"
        case "acp_session_storage_incompatible": return "Agent session storage is incompatible"
        case "acp_resource_not_found": return "Agent resource not found"
        case "acp_request_cancelled": return "Request was cancelled"
        case "acp_method_not_found": return "Agent protocol method not found"
        case "acp_invalid_params": return "Invalid request parameters"
        case "acp_invalid_request": return "Invalid request"
        case "acp_parse_error": return "Failed to parse request"
        case "acp_unknown_error": return "Agent error"
        default: return "Failed to process message"
        }
    }

    /// Mirrors Lody's readable-message extraction while keeping `message` intact.
    public var readableMessage: String? {
        guard let raw = message?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let start = raw.firstIndex(of: "{"),
           let object = try? JSONSerialization.jsonObject(with: Data(raw[start...].utf8)) as? [String: Any] {
            let inner = object["error"] as? [String: Any] ?? object
            if let message = inner["message"] as? String, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
        }
        let stripped = raw.replacingOccurrences(of: #"^(?:Internal error:\s*)?(?:API Error:\s*\d+\s*)?"#,
                                               with: "", options: .regularExpression)
        return stripped.isEmpty ? raw : stripped
    }

    public var report: String {
        var fields = ["Error: \(String(localized: title))"]
        if let reason, !reason.isEmpty { fields.append("Reason: \(reason)") }
        if let code, !code.isEmpty { fields.append("Code: \(code)") }
        let header = fields.joined(separator: "\n")
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return header }
        return header + "\n\n" + message
    }
}
