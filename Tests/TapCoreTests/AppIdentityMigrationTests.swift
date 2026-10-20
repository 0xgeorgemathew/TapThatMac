import Foundation
import XCTest
import TapCore

final class AppIdentityMigrationTests: XCTestCase {
    func testLegacyPreferencesFillMissingValuesWithoutOverwritingNewChoices() throws {
        let suite = "AppIdentityMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("paused", forKey: "operatingMode")
        let profile = Data([1, 2, 3])
        AppIdentityMigration.migratePreferences(into: defaults, legacy: [
            "operatingMode": "active", "calibrationProfiles": profile,
            "activeCalibrationProfileID": "saved-profile"
        ])
        XCTAssertEqual(defaults.string(forKey: "operatingMode"), "paused")
        XCTAssertEqual(defaults.data(forKey: "calibrationProfiles"), profile)
        XCTAssertEqual(defaults.string(forKey: "activeCalibrationProfileID"), "saved-profile")
        defaults.removeObject(forKey: "activeCalibrationProfileID")
        AppIdentityMigration.migratePreferences(into: defaults, legacy: ["activeCalibrationProfileID": "saved-profile"])
        XCTAssertNil(defaults.string(forKey: "activeCalibrationProfileID"), "Cleared choices must not return on later launches")
    }

    func testLegacyArchivesAreCopiedWithoutReplacingCurrentFilesOrDeletingOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("TapThatX/Calibration")
        let current = root.appendingPathComponent("Tap That Mac/Calibration")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("shared.json"))
        try Data("new".utf8).write(to: current.appendingPathComponent("shared.json"))
        try Data("session".utf8).write(to: legacy.appendingPathComponent("session.json"))
        try AppIdentityMigration.migrateFiles(in: root)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("shared.json")), Data("new".utf8))
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("session.json")), Data("session".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("session.json").path))
        try AppIdentityMigration.migrateFiles(in: root)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("session.json")), Data("session".utf8))
    }
}
