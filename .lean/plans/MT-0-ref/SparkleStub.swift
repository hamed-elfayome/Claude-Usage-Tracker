import Foundation
public class SUAppcastItem: NSObject { public var displayVersionString: String = "" }
public class SPUUserUpdateState: NSObject {}
public protocol SPUStandardUserDriverDelegate: NSObjectProtocol {}
public protocol SPUUpdaterDelegate: NSObjectProtocol {}
public class SPUUpdater: NSObject { public var automaticallyChecksForUpdates = false; public var canCheckForUpdates = false; public var lastUpdateCheckDate: Date? = nil }
public class SPUStandardUpdaterController: NSObject { public let updater = SPUUpdater(); public init(startingUpdater: Bool, updaterDelegate: SPUUpdaterDelegate?, userDriverDelegate: SPUStandardUserDriverDelegate?) {}; @objc public func checkForUpdates(_ sender: Any?) {} }
