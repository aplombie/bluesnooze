import XCTest
@testable import ProcaineCore

final class PreferenceMigrationTests: XCTestCase {
    private func withDefaults(_ run: (UserDefaults) -> Void) {
        let suite = "ProcaineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        run(defaults)
    }

    func testLegacyPreferenceIsCopiedOnceWithoutModifyingSource() {
        withDefaults { defaults in
            let legacy: [String: Any] = ["hideIcon": true, "unrelated": "do not copy"]
            PreferenceMigration.migrate(into: defaults, legacy: legacy)
            XCTAssertTrue(defaults.bool(forKey: "hideIcon"))
            XCTAssertNil(defaults.object(forKey: "unrelated"))
            defaults.set(false, forKey: "hideIcon")
            PreferenceMigration.migrate(into: defaults, legacy: legacy)
            XCTAssertFalse(defaults.bool(forKey: "hideIcon"))
            XCTAssertEqual(legacy["hideIcon"] as? Bool, true)
        }
    }

    func testNewPreferenceTakesPrecedenceAndMissingDomainIsSafe() {
        withDefaults { defaults in
            defaults.set(false, forKey: "hideIcon")
            PreferenceMigration.migrate(into: defaults, legacy: ["hideIcon": true])
            XCTAssertFalse(defaults.bool(forKey: "hideIcon"))
        }
        withDefaults { defaults in
            PreferenceMigration.migrate(into: defaults, legacy: nil)
            XCTAssertTrue(defaults.bool(forKey: "didMigrateBluesnoozePreferences"))
            XCTAssertNil(defaults.object(forKey: "hideIcon"))
        }
    }
}
