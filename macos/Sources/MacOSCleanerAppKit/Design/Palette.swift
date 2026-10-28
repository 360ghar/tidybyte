import SwiftUI
import MacOSCleanerCore

public struct CategoricalPalette {
    public let soft: Color
    public let mid: Color
    public let ink: Color

    private init(_ color: Color) {
        soft = color.opacity(0.12)
        mid = color
        ink = .primary
    }
}

public extension CategoricalPalette {
    static var blue: Self { Self(Color(nsColor: .systemBlue)) }
    static var purple: Self { Self(Color(nsColor: .systemPurple)) }
    static var green: Self { Self(Color(nsColor: .systemGreen)) }
    static var yellow: Self { Self(Color(nsColor: .systemYellow)) }
    static var orange: Self { Self(Color(nsColor: .systemOrange)) }
    static var teal: Self { Self(Color(nsColor: .systemTeal)) }
    static var pink: Self { Self(Color(nsColor: .systemPink)) }
    static var coral: Self { Self(Color(nsColor: .systemRed)) }
    static var protected: Self { Self(Color(nsColor: .systemPurple)) }
}

public enum FolderPastel {
    private static var colors: [CategoricalPalette] {
        [.blue, .teal, .green, .orange, .purple, .pink, .coral, .yellow, .blue, .teal]
    }
    public static func palette(forFolderName name: String) -> CategoricalPalette {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in name.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return colors[Int(hash % UInt64(colors.count))]
    }
    public static var count: Int { colors.count }
}

public extension FindingCategory {
    /// Returns the categorical color palette associated with this finding type.
    var palette: CategoricalPalette {
        switch self {
        case .largeFile:
            return .coral
        case .duplicate:
            return .blue
        case .cache:
            return .green
        case .log:
            return .yellow
        case .developerArtifact:
            return .orange
        case .appLeftover:
            return .teal
        case .oldDownload:
            return .purple
        case .organization:
            return .pink
        case .packageManagerCleanup:
            return .green
        case .dockerCleanup:
            return .blue
        case .codingAgentArtifact:
            return .orange
        case .protected:
            return .protected
        case .oldInstaller:
            return .purple
        case .screenshot:
            return .yellow
        // mo clean sections
        case .systemDeep:
            return .blue
        case .userEssentials:
            return .green
        case .finderMetadata:
            return .teal
        case .macOSSystemCache:
            return .blue
        case .sandboxedAppCache:
            return .teal
        case .browserCache:
            return .purple
        case .cloudStorageCache:
            return .blue
        case .officeAppCache:
            return .orange
        case .developerToolCache:
            return .green
        case .developmentAppCache:
            return .orange
        case .vmToolCache:
            return .blue
        case .applicationSupportCache:
            return .green
        case .uninstalledAppData:
            return .teal
        case .appleSiliconUpdate:
            return .purple
        case .iosDeviceBackup:
            return .coral
        case .timeMachineBackup:
            return .coral
        case .largeFileReview:
            return .coral
        }
    }
}
