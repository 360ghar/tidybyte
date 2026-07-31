import os

/// Centralized `os.Logger` instances so failures are diagnosable in production
/// instead of being silently swallowed. Use the category that matches the
/// subsystem doing the logging.
enum AppLog {
    private static let subsystem = "com.tidybyte.app"

    static let photo = Logger(subsystem: subsystem, category: "PhotoLibrary")
    static let vision = Logger(subsystem: subsystem, category: "Vision")
    static let compression = Logger(subsystem: subsystem, category: "Compression")
    static let data = Logger(subsystem: subsystem, category: "Data")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let app = Logger(subsystem: subsystem, category: "App")
}
