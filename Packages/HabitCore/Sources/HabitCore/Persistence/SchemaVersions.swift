import Foundation
import SwiftData

/// The store's schema history. Introduced before Stage 1 added any fields, while no real
/// user data existed — retrofitting versioning onto a populated store is far more expensive.
///
/// ## Adding a version
/// Additive changes — a new property that has a default, a new model — migrate lightweight:
/// declare `SchemaV2` with the same model types and a bumped `versionIdentifier`, then append
/// `MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)` to `stages`.
/// Anything that renames, retypes, or drops a property needs `.custom` with a `willMigrate`
/// that copies the old values forward; losing user history is not acceptable.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Habit.self, DailyLog.self, GeofenceVisit.self]
    }
}

public enum HabitMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    /// Empty until a second version exists; the plan itself is wired into every container now
    /// so that adding a stage later needs no change at the call sites.
    public static var stages: [MigrationStage] { [] }
}
