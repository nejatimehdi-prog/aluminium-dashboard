import Foundation

/// Persists `AppPreferences` as JSON in UserDefaults (no financial data is stored here).
final class PreferencesStore {
    private let defaults: UserDefaults
    private let key = "chortkeh.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return AppPreferences() }
        return prefs
    }

    func save(_ prefs: AppPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: key)
        }
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
