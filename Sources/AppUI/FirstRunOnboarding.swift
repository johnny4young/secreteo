/// Storage-independent facts used to decide whether first-run setup should
/// appear. Composition gathers these facts; presentation renders the result.
public struct FirstRunOnboardingContext: Equatable, Sendable {
    public let forceRequested: Bool
    public let automationSuppressed: Bool
    public let hasCompleted: Bool

    public init(
        forceRequested: Bool,
        automationSuppressed: Bool,
        hasCompleted: Bool
    ) {
        self.forceRequested = forceRequested
        self.automationSuppressed = automationSuppressed
        self.hasCompleted = hasCompleted
    }
}

public enum FirstRunOnboardingDecision: Equatable, Sendable {
    case show
    case hide
}

/// Deterministic first-run policy. A forced developer/test presentation wins
/// over every suppression rule; onboarding never owns model readiness.
public enum FirstRunOnboardingPolicy {
    public static func decide(
        _ context: FirstRunOnboardingContext
    ) -> FirstRunOnboardingDecision {
        if context.forceRequested { return .show }
        if context.automationSuppressed || context.hasCompleted { return .hide }
        return .show
    }
}
