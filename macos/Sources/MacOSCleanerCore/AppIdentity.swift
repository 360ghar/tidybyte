import Foundation

/// Every name the app shows or writes to disk. Change the brand here only.
public enum AppIdentity {
    public static let displayName = "Tidybyte"
    public static let bundleIdentifier = "com.sakshammittal.tidybyte"
    public static let autoscanLabel = bundleIdentifier + ".autoscan"
    public static let urlScheme = "tidybyte"
    public static let supportFolderName = "Tidybyte"
    public static let databaseFileName = "Tidybyte.sqlite"
    public static let mcpServerName = "tidybyte-mcp"

    public static let reportsFolderName = "Tidybyte Reports"
    public static let inboxFolderName = "Tidybyte Inbox"
    public static let aliasesFolderName = "Tidybyte Aliases"
    public static let linksFolderName = "Tidybyte Links"
    public static let archiveFolderName = "Tidybyte Archive"
}
