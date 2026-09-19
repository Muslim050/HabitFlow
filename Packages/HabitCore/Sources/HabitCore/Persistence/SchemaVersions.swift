import Foundation
import SwiftData

/// The store's schema, as one version that tracks the current shape of the models.
///
/// ## Why there is only one version
/// A `VersionedSchema` is identified by a checksum over the model shapes it lists. Two versions
/// that list the *same* Swift types therefore hash identically, and Core Data refuses the plan
/// with "Duplicate version checksums detected" at launch. Declaring `SchemaV2` alongside `SchemaV1`
/// only works when V1 keeps frozen copies of the models as they were — nested `@Model` types that
/// are never touched again. That is the price of a second version, and it buys nothing while every
/// change is additive: a new property with a default, or a new model, migrates lightweight on its
/// own, which is how `scheduleData` arrived.
///
/// ## When to split
/// The first change that renames, retypes or removes a stored property. Then, and only then:
/// freeze today's models as `SchemaV1.Habit` and friends, describe the new shape in `SchemaV2`,
/// and add a `.custom` stage whose `willMigrate` copies the old values forward. Losing user
/// history is not acceptable, so that stage gets its own test against a store written by this build.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 2, 0) }

    public static var models: [any PersistentModel.Type] {
        [Habit.self, DailyLog.self, GeofenceVisit.self, HabitPause.self]
    }
}

public enum HabitMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    /// Empty by design — see the note above. The plan is wired into every container already, so
    /// the first real stage needs no change at the call sites.
    public static var stages: [MigrationStage] { [] }
}
