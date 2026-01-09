import Foundation

/// Represents a program discovered in a Wine prefix after installation
public struct DiscoveredProgram: Identifiable, Hashable, Sendable {
    /// Unique identifier for this discovered program
    public let id: UUID

    /// Display name of the program (extracted from filename or shortcut)
    public let name: String

    /// File URL pointing to the executable (.exe) or shortcut (.lnk)
    public let url: URL

    /// Indicates if this program was discovered via a shortcut file
    /// - true: Found via .lnk file in Desktop/Start Menu
    /// - false: Found via direct .exe scan in Program Files
    public let isFromShortcut: Bool

    /// Creates a new discovered program instance
    /// - Parameters:
    ///   - name: Display name of the program
    ///   - url: File URL to the executable or shortcut
    ///   - isFromShortcut: Whether discovered via shortcut (true) or direct scan (false)
    public init(name: String, url: URL, isFromShortcut: Bool) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.isFromShortcut = isFromShortcut
    }

    // MARK: - Convenience Properties

    /// Returns the file extension (e.g., "exe", "lnk")
    public var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// Returns true if this is an executable file
    public var isExecutable: Bool {
        fileExtension == "exe"
    }

    /// Returns true if this is a shortcut file
    public var isShortcut: Bool {
        fileExtension == "lnk"
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredProgram, rhs: DiscoveredProgram) -> Bool {
        lhs.id == rhs.id
    }
}
