import Foundation

enum AppLanguage: String, CaseIterable {
    case japanese = "ja"
    case english = "en"

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true ? .japanese : .english
    }

    var displayName: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
        }
    }
}

enum AppPreferences {
    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let launchAtLogin = "launchAtLogin"
        static let displaySleepOnLidClose = "displaySleepOnLidClose"
        static let language = "language"
        static let didCompleteInitialSetup = "didCompleteInitialSetup"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.launchAtLogin: true,
            Key.displaySleepOnLidClose: true,
            Key.language: AppLanguage.systemDefault.rawValue,
            Key.didCompleteInitialSetup: false
        ])
    }

    static var showMenuBarIcon: Bool {
        get { UserDefaults.standard.bool(forKey: Key.showMenuBarIcon) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showMenuBarIcon) }
    }

    static var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: Key.launchAtLogin) }
        set { UserDefaults.standard.set(newValue, forKey: Key.launchAtLogin) }
    }

    static var displaySleepOnLidClose: Bool {
        get { UserDefaults.standard.bool(forKey: Key.displaySleepOnLidClose) }
        set { UserDefaults.standard.set(newValue, forKey: Key.displaySleepOnLidClose) }
    }

    static var language: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.language),
                  let value = AppLanguage(rawValue: raw) else {
                return .systemDefault
            }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.language) }
    }

    static var didCompleteInitialSetup: Bool {
        get { UserDefaults.standard.bool(forKey: Key.didCompleteInitialSetup) }
        set { UserDefaults.standard.set(newValue, forKey: Key.didCompleteInitialSetup) }
    }
}

struct AppStrings {
    let openSettings: String
    let retry: String
    let quit: String
    let title: String
    let statusHeading: String
    let settingsHeading: String
    let showMenuBarIcon: String
    let launchAtLogin: String
    let displaySleepOnLidClose: String
    let language: String
    let done: String
    let warning: String
    let statusOn: String
    let statusOff: String
    let statusSynchronizing: String
    let statusError: String

    static func current() -> AppStrings {
        switch AppPreferences.language {
        case .japanese:
            AppStrings(
                openSettings: "設定を開く",
                retry: "再試行",
                quit: "終了",
                title: "Capsomnia",
                statusHeading: "現在の状態",
                settingsHeading: "設定",
                showMenuBarIcon: "メニューバーに状態を表示",
                launchAtLogin: "ログイン時に起動",
                displaySleepOnLidClose: "蓋を閉じたら画面をスリープ",
                language: "言語",
                done: AppPreferences.didCompleteInitialSetup ? "閉じる" : "使用を開始",
                warning: "Caps Lock ON 中はシステムスリープを抑止します。蓋を閉じる場合は発熱とバッテリー消費に注意してください。",
                statusOn: "スリープ抑止を確認済み",
                statusOff: "通常のスリープを確認済み",
                statusSynchronizing: "状態を確認中",
                statusError: "スリープ設定を確認できません。再試行します"
            )
        case .english:
            AppStrings(
                openSettings: "Open Settings",
                retry: "Retry",
                quit: "Quit",
                title: "Capsomnia",
                statusHeading: "Current status",
                settingsHeading: "Settings",
                showMenuBarIcon: "Show status in the menu bar",
                launchAtLogin: "Open at login",
                displaySleepOnLidClose: "Sleep the display when the lid closes",
                language: "Language",
                done: AppPreferences.didCompleteInitialSetup ? "Close" : "Get Started",
                warning: "Caps Lock ON prevents system sleep. Watch temperature and battery use when the lid is closed.",
                statusOn: "Sleep prevention verified",
                statusOff: "Normal sleep verified",
                statusSynchronizing: "Checking the system state",
                statusError: "Could not verify the sleep setting. Retrying"
            )
        }
    }
}

