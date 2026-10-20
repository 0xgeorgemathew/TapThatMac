import AppKit
import XCTest
import TapCore
@testable import TapThatMac

@MainActor
final class StartupPersistenceTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        suite = "StartupPersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func calibratedSettings() -> DetectorSettings {
        var settings = DetectorSettings()
        settings.sensitivity = 2.3
        settings.suppressTyping = false
        settings.minimumRiseRate = 2.2
        settings.impulseMinimumRiseRate = 4.3
        settings.maximumPulseDuration = 0.028
        settings.maximumTapInterval = 0.65
        return settings
    }

    private func seedProfile(settings: DetectorSettings) throws -> CalibrationProfile {
        let session = CalibrationSession(context: .init(surface: "Desk", placement: "Startup test",
            device: "Test", os: "Test", input: "Direct sensor", requestedRate: 800,
            initialSettings: settings))
        let profile = CalibrationProfile(session: session, settings: settings)
        defaults.set(try JSONEncoder().encode(settings), forKey: "detectorSettings")
        defaults.set(try JSONEncoder().encode([profile]), forKey: "calibrationProfiles")
        defaults.set(profile.id.uuidString, forKey: "activeCalibrationProfileID")
        defaults.set(profile.id.uuidString, forKey: "calibrationSessionID")
        return profile
    }

    private func launch() -> AppModel {
        AppModel(startServices: false, modeDefaults: defaults, settingsDefaults: defaults)
    }

    private func persistedSettings() throws -> DetectorSettings {
        try JSONDecoder().decode(DetectorSettings.self, from: XCTUnwrap(defaults.data(forKey: "detectorSettings")))
    }

    func testRepeatedLaunchesRestoreFullSettingsAndProfileWithoutRewritingPreferences() throws {
        let settings = calibratedSettings()
        let profile = try seedProfile(settings: settings)
        let saved = try XCTUnwrap(defaults.persistentDomain(forName: suite)) as NSDictionary
        for _ in 0..<2 {
            let model = launch()
            XCTAssertEqual(model.activeCalibrationProfile, profile)
            XCTAssertEqual(model.calibrationProfiles, [profile])
            XCTAssertEqual(model.sensitivity, 2.3)
            XCTAssertFalse(model.suppressTyping)
            XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, saved)
            XCTAssertEqual(try persistedSettings(), settings)
            model.shutdown()
        }
        // A normal edit on the next launch persists the restored detector's full settings.
        let model = launch()
        defer { model.shutdown() }
        model.suppressTyping = true
        var expected = settings
        expected.suppressTyping = true
        XCTAssertEqual(try persistedSettings(), expected)
        XCTAssertEqual(model.activeCalibrationProfile, profile)
    }

    func testManualSensitivityChangeStillPersistsAndClearsActiveProfileMetadata() throws {
        let settings = calibratedSettings()
        _ = try seedProfile(settings: settings)
        let model = launch()
        defer { model.shutdown() }
        model.sensitivity = 1.7
        var expected = settings
        expected.sensitivity = 1.7
        XCTAssertEqual(try persistedSettings(), expected)
        XCTAssertEqual(defaults.double(forKey: "knockSensitivity"), 1.7)
        XCTAssertNil(model.activeCalibrationProfile)
        XCTAssertNil(defaults.object(forKey: "activeCalibrationProfileID"))
        XCTAssertNil(defaults.object(forKey: "calibrationSessionID"))
        XCTAssertEqual(model.calibrationProfiles.count, 1)
    }

    func testExplicitProfileActivationPersistsFullSettingsAcrossLaunch() throws {
        let settings = calibratedSettings()
        let profile = try seedProfile(settings: settings)
        defaults.set(try JSONEncoder().encode(DetectorSettings()), forKey: "detectorSettings")
        defaults.removeObject(forKey: "activeCalibrationProfileID")
        let model = launch()
        model.activateCalibrationProfile(profile.id)
        var expected = settings
        expected.suppressTyping = true // Activation preserves the current typing preference.
        XCTAssertEqual(try persistedSettings(), expected)
        XCTAssertEqual(model.activeCalibrationProfile, profile)
        XCTAssertEqual(defaults.string(forKey: "activeCalibrationProfileID"), profile.id.uuidString)
        model.shutdown()
        let restored = launch()
        defer { restored.shutdown() }
        XCTAssertEqual(restored.activeCalibrationProfile, profile)
        XCTAssertEqual(try persistedSettings(), expected)
    }
}
