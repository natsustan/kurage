import Foundation

public enum LodyEndpoints {
    /// Public better-auth host from the Lody web client (`VITE_CONVEX_SITE_URL`).
    public static let authBaseURL = URL(string: "https://backend.lody.ai")!
    /// Session image downloads are served by the cloud API, separate from auth.
    public static let cloudAPIBaseURL = URL(string: "https://api.lody.ai")!
    public static let webOrigin = "https://lody.ai"
    /// Same public device-flow client the Lody CLI and the community iOS app use.
    public static let deviceClientID = "lody-cli"
}
