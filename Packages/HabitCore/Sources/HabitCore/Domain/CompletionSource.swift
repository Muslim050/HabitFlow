import Foundation

/// Who decided a log's completion state.
public enum CompletionSource: String, Codable, Sendable, CaseIterable {
    /// Not completed yet (or completion cleared by the engine). Named `unset` so `log?.completionSource == .unset` never resolves to `Optional.none`.
    case unset
    /// A manual habit tapped by the user.
    case manual
    /// The engine satisfied an automatic rule.
    case auto
    /// The user manually forced the state of an automatic habit; the engine leaves it alone.
    case manualOverride
}
