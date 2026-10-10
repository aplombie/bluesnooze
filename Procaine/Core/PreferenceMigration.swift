import Foundation

enum PreferenceMigration {
    static let legacyDomain = "com.oliverpeate.Bluesnooze"

    /// Copy supported preferences once. Never change the upstream domain or login registration.
    static func migrate(into defaults: UserDefaults, legacy: [String: Any]?) {
        guard !defaults.bool(forKey: "didMigrateBluesnoozePreferences") else { return }
        if defaults.object(forKey: "hideIcon") == nil, let hidden = legacy?["hideIcon"] as? Bool {
            defaults.set(hidden, forKey: "hideIcon")
        }
        defaults.set(true, forKey: "didMigrateBluesnoozePreferences")
    }
}
