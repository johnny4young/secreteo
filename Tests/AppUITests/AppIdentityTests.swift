import AppUI
import Testing

@Test func devAndReleaseAreDifferentIdentities() {
    #expect(AppIdentity.release.rawValue == "com.johnny4young.secreteo")
    #expect(AppIdentity.development.rawValue == "com.johnny4young.secreteo.dev")
    #expect(AppIdentity.debug.rawValue == "com.johnny4young.secreteo.debug")
}
