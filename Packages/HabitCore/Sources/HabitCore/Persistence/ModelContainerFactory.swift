import Foundation
import SwiftData

public enum AppGroup {
    public static let id = "group.com.muslimahaev.habitflow"
    public static let cloudKitContainer = "iCloud.com.muslimahaev.habitflow"
}

public enum ModelContainerFactory {
    public static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

    /// On-disk store inside the app's own container. Used when the App Group is unavailable —
    /// a free personal signing team cannot always provision one — so that history still survives
    /// a relaunch. The widget cannot read this store: it is a degraded mode, not a supported one.
    public static func local() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: HabitMigrationPlan.self, configurations: [config])
    }

    /// Isolated store for tests and previews.
    public static func inMemory() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: HabitMigrationPlan.self, configurations: [config])
    }

    /// The App Group store shared by the app and the widget.
    /// CloudKit sync is compiled in only with the `ENABLE_CLOUDKIT` flag (needs a paid developer team).
    public static func shared() throws -> ModelContainer {
        #if ENABLE_CLOUDKIT
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.id),
            cloudKitDatabase: .private(AppGroup.cloudKitContainer)
        )
        #else
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.id),
            cloudKitDatabase: .none
        )
        #endif
        return try ModelContainer(for: schema, migrationPlan: HabitMigrationPlan.self, configurations: [config])
    }
}
