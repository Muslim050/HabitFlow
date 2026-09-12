import CoreLocation
import Foundation
import HabitCore

/// Geofence habits via classic region monitoring: system-managed, survives termination,
/// relaunches the app on entry/exit. `CLMonitor` can replace this later behind the same protocol.
@MainActor
final class LocationProvider: NSObject, HabitSourceProvider {
    nonisolated static let maxRegions = 20
    nonisolated static let radiusRange: ClosedRange<Double> = 100...500

    private let manager = CLLocationManager()
    private let repository: any HabitRepository
    private var onChange: (@Sendable @MainActor (HabitSourceKind) async -> Void)?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    init(repository: any HabitRepository) {
        self.repository = repository
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    let supportedKinds: Set<HabitSourceKind> = [.geofence]

    var isAvailable: Bool { CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) }
    var hasAlwaysAuthorization: Bool { authorizationStatus == .authorizedAlways }
    var hasAnyAuthorization: Bool { authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse }
    var monitoredRegionCount: Int { manager.monitoredRegions.count }

    nonisolated static func clampedRadius(_ radius: Double) -> Double {
        min(max(radius, radiusRange.lowerBound), radiusRange.upperBound)
    }

    // MARK: Authorization

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestAlwaysAuthorization() { manager.requestAlwaysAuthorization() }

    func requestAuthorization(for rules: [HabitRule]) async throws {
        guard rules.contains(where: { $0.kind == .geofence }) else { return }
        switch authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    // MARK: Snapshot

    func snapshot(for rule: HabitRule, habitID: UUID, window: DateInterval, now: Date) async throws -> ProgressSnapshot {
        guard case .geofence = rule else { throw ProviderError.unsupportedRule }
        let visits = try repository.visits(habitID: habitID, overlapping: window, now: now).map { $0.interval(now: now) }
        return GeofenceEvaluator.snapshot(rule: rule, visits: visits, window: window, now: now)
    }

    // MARK: Observing

    func startObserving(habits: [(id: UUID, rule: HabitRule)], onChange: @escaping @Sendable @MainActor (HabitSourceKind) async -> Void) {
        self.onChange = onChange
        guard isAvailable else { return }

        var wanted: [(UUID, CLLocationCoordinate2D, Double)] = []
        for (id, rule) in habits {
            guard case .geofence(let lat, let lon, let radius, _, _) = rule else { continue }
            wanted.append((id, CLLocationCoordinate2D(latitude: lat, longitude: lon), Self.clampedRadius(radius)))
            if wanted.count == Self.maxRegions { break }
        }
        let wantedIDs = Set(wanted.map { $0.0.uuidString })

        for region in manager.monitoredRegions where !wantedIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        let existing = Set(manager.monitoredRegions.map(\.identifier))
        for (id, center, radius) in wanted {
            let region = CLCircularRegion(center: center, radius: radius, identifier: id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            if existing.contains(id.uuidString) {
                // Replace so radius/center edits take effect.
                if let old = manager.monitoredRegions.first(where: { $0.identifier == id.uuidString }) {
                    manager.stopMonitoring(for: old)
                }
            }
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }
    }

    func stopObserving() {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
    }

    /// At launch the system already restored monitored regions; refresh state for each.
    func restoreMonitoring() {
        authorizationStatus = manager.authorizationStatus
        for region in manager.monitoredRegions { manager.requestState(for: region) }
    }

    // MARK: Events

    private func handle(identifier: String, entered: Bool, at date: Date) async {
        guard let habitID = UUID(uuidString: identifier) else { return }
        do {
            let open = try repository.openVisit(habitID: habitID)
            if entered {
                guard open == nil else { return }
                repository.insert(GeofenceVisit(habitID: habitID, enteredAt: date))
                Log.location.info("Entered region for \(habitID)")
            } else {
                guard let open else { return }
                open.exitedAt = date
                open.updatedAt = date
                Log.location.info("Exited region for \(habitID) after \(Int(date.timeIntervalSince(open.enteredAt) / 60)) min")
            }
            try repository.save()
        } catch {
            Log.location.error("Visit update failed: \(error.localizedDescription)")
        }
        await onChange?(.geofence)
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        let now = Date()
        Task { @MainActor in await self.handle(identifier: identifier, entered: true, at: now) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier
        let now = Date()
        Task { @MainActor in await self.handle(identifier: identifier, entered: false, at: now) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let identifier = region.identifier
        let now = Date()
        switch state {
        case .inside: Task { @MainActor in await self.handle(identifier: identifier, entered: true, at: now) }
        case .outside: Task { @MainActor in await self.handle(identifier: identifier, entered: false, at: now) }
        case .unknown: break
        @unknown default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            Log.location.info("Authorization changed: \(status.rawValue)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let identifier = region?.identifier ?? "?"
        let message = error.localizedDescription
        Task { @MainActor in Log.location.error("Monitoring failed for \(identifier): \(message)") }
    }
}
