/// The bundle identities. Each keeps its own preferences, data and permissions, so a Dev
/// build or a UI test never touches a user's real setup.
public enum AppIdentity: String, Sendable, CaseIterable {
    case release = "com.johnny4young.secreteo"
    case development = "com.johnny4young.secreteo.dev"
    case debug = "com.johnny4young.secreteo.debug"
}
