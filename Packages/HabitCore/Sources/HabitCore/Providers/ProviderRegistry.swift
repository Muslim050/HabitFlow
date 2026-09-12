import Foundation

/// Maps each source kind to the provider that can evaluate it.
@MainActor
public final class ProviderRegistry {
    private var providers: [HabitSourceKind: any HabitSourceProvider] = [:]

    public init() {}

    public func register(_ provider: any HabitSourceProvider) {
        for kind in provider.supportedKinds { providers[kind] = provider }
    }

    public func provider(for kind: HabitSourceKind) -> (any HabitSourceProvider)? {
        providers[kind]
    }

    /// Distinct providers, each once.
    public var all: [any HabitSourceProvider] {
        var seen: [ObjectIdentifier] = []
        var result: [any HabitSourceProvider] = []
        for provider in providers.values {
            let id = ObjectIdentifier(provider)
            if !seen.contains(id) { seen.append(id); result.append(provider) }
        }
        return result
    }
}
