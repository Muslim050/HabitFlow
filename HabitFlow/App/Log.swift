import OSLog

enum Log {
    static let subsystem = "com.muslimahaev.habitflow"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let background = Logger(subsystem: subsystem, category: "background")
}
