/// The two bundle identities. Release and Dev keep separate preferences, data and
/// permissions, so a Dev build never touches a user's real setup.
public enum AppIdentity: String, Sendable, CaseIterable {
    case release = "com.johnny4young.secreteo"
    case development = "com.johnny4young.secreteo.dev"
}
