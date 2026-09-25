import Foundation

enum LodyEndpoints {
    /// Public better-auth host from the Lody web client (`VITE_CONVEX_SITE_URL`).
    static let authBaseURL = URL(string: "https://backend.lody.ai")!
    /// Session image downloads are served by the cloud API, separate from auth.
    static let cloudAPIBaseURL = URL(string: "https://api.lody.ai")!
    static let webOrigin = "https://lody.ai"
    /// Same public device-flow client the Lody CLI and the community iOS app use.
    static let deviceClientID = "lody-cli"
}
