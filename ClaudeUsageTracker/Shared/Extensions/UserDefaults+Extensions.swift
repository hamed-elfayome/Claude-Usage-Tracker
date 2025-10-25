import Foundation

// MARK: - UserDefaults Extension for KVO
extension UserDefaults {
    @objc dynamic var refreshInterval: Double {
        return double(forKey: Constants.UserDefaultsKeys.refreshInterval)
    }
}
