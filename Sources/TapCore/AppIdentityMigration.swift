import Foundation

/// Copies legacy local state, retaining originals and any choices made in the renamed app.
public enum AppIdentityMigration {
    private static let preferencesMarker = "appIdentityMigrationCompleted"

    public static func run() {
        let defaults = UserDefaults.standard
        migratePreferences(into: defaults, legacy: defaults.persistentDomain(forName: "com.tapthatx.app") ?? [:])
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            try migrateFiles(in: support)
        } catch {
            // Originals remain available; retry copying missing archives on the next launch.
            NSLog("Tap That Mac could not copy legacy local archives: %@", error.localizedDescription)
        }
    }

    public static func migratePreferences(into defaults: UserDefaults, legacy: [String: Any]) {
        guard !defaults.bool(forKey: preferencesMarker) else { return }
        for (key, value) in legacy where key != preferencesMarker && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: preferencesMarker)
    }

    public static func migrateFiles(in applicationSupport: URL) throws {
        // TapThatX is the previous Application Support folder, retained for compatibility.
        let legacy = applicationSupport.appendingPathComponent("TapThatX", isDirectory: true)
        let current = applicationSupport.appendingPathComponent("Tap That Mac", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try copyMissing(from: legacy, to: current)
    }

    private static func copyMissing(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try files.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if values.isDirectory == true {
                try copyMissing(from: item, to: target)
            } else if !files.fileExists(atPath: target.path) {
                try files.copyItem(at: item, to: target)
            }
        }
    }
}
