import UIKit

// swiftlint:disable redundant_string_enum_value
enum ThemeMode: String {
    case dark = "dark"
    case light = "light"
    case auto = "auto"
}
// swiftlint:enable redundant_string_enum_value

class ThemeManager {
    static let shared = ThemeManager()
    static let didChangeNotification = Notification.Name("ThemeManagerDidChange")

    // Cached resolved colors — recomputed only when theme changes
    private(set) var background: UIColor   = .black
    private(set) var surface: UIColor      = UIColor(white: 0.1, alpha: 1)
    private(set) var primaryText: UIColor  = .white
    private(set) var secondaryText: UIColor = UIColor(white: 0.55, alpha: 1)
    private(set) var separator: UIColor    = UIColor(white: 0.15, alpha: 1)
    private(set) var accent: UIColor       = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private(set) var durationBackground: UIColor = UIColor.black.withAlphaComponent(0.8)
    private(set) var liveBadgeBackground: UIColor = UIColor(red: 1, green: 0, blue: 0, alpha: 0.9)
    private(set) var thumbnailPlaceholder: UIColor = UIColor(white: 0.15, alpha: 1)
    private(set) var newContentDot: UIColor = UIColor(
        red: 62 / 255, green: 166 / 255, blue: 1, alpha: 1
    )
    private(set) var skeletonBase: UIColor    = UIColor(white: 0.13, alpha: 1)
    private(set) var skeletonShimmer: UIColor = UIColor(white: 0.22, alpha: 1)
    private(set) var skeletonBlock: UIColor   = UIColor(white: 0.18, alpha: 1)
    private(set) var barStyle: UIBarStyle = .black
    private(set) var statusBarStyle: UIStatusBarStyle = .lightContent

    /// What `isDark` resolved to when the palette was last rebuilt — lets
    /// `refreshAutoTheme` detect that the auto answer changed over time.
    private var resolvedDark = true
    /// iOS 12 only: fires at the next schedule boundary while the app runs.
    private var boundaryTimer: Timer?

    var themeMode: ThemeMode {
        get {
            let raw = UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Theme.mode
            ) ?? ThemeMode.dark.rawValue
            return ThemeMode(rawValue: raw) ?? .dark
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.Theme.mode)
            rebuildCache()
            applyGlobal()
            scheduleBoundaryRefresh()
            NotificationCenter.default.post(name: ThemeManager.didChangeNotification, object: nil)
        }
    }

    var isDark: Bool {
        get {
            switch themeMode {
            case .dark:
                return true
            case .light:
                return false
            case .auto:
                return autoResolvesDark
            }
        }
        set { themeMode = newValue ? .dark : .light }
    }

    /// Auto mode: the system appearance where it exists (iOS 13+), a
    /// user-configurable hour schedule on iOS 12 (Night Shift's schedule has
    /// no public API).
    private var autoResolvesDark: Bool {
        if #available(iOS 13.0, *) {
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark
        }
        return Self.scheduleSaysDark(
            hour: Calendar.current.component(.hour, from: Date()),
            start: autoDarkStartHour,
            end: autoDarkEndHour
        )
    }

    /// Hour (0–23) when the iOS 12 auto schedule turns dark. Default 19.
    var autoDarkStartHour: Int {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Theme.autoDarkStartHour
            ) as? Int ?? 19
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.Theme.autoDarkStartHour
            )
            refreshAutoTheme()
        }
    }

    /// Hour (0–23) when the iOS 12 auto schedule turns light again. Default 7.
    var autoDarkEndHour: Int {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Theme.autoDarkEndHour
            ) as? Int ?? 7
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.Theme.autoDarkEndHour
            )
            refreshAutoTheme()
        }
    }

    private init() {
        rebuildCache()
        scheduleBoundaryRefresh()
    }

    /// Dark between `start` and `end` hours, wrapping past midnight
    /// (19 → 7 means dark evenings and nights). Equal hours = never dark.
    static func scheduleSaysDark(hour: Int, start: Int, end: Int) -> Bool {
        if start == end {
            return false
        }
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }

    /// The one nav-chevron style used everywhere: the global back indicator
    /// and the watch screen's custom back/minimize buttons.
    @available(iOS 13.0, *)
    static func navChevron(systemName: String) -> UIImage? {
        let cfg = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        return UIImage(systemName: systemName, withConfiguration: cfg)
    }

    /// Re-evaluates auto mode (schedule boundary crossed, system appearance
    /// changed, app foregrounded) and republishes the theme when the answer
    /// flipped. No-op outside auto mode or when nothing changed.
    func refreshAutoTheme() {
        scheduleBoundaryRefresh()
        guard themeMode == .auto, isDark != resolvedDark else {
            return
        }
        rebuildCache()
        applyGlobal()
        NotificationCenter.default.post(
            name: ThemeManager.didChangeNotification, object: nil
        )
    }

    private func scheduleBoundaryRefresh() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        if #available(iOS 13.0, *) {
            return
        }
        guard themeMode == .auto else {
            return
        }
        let now = Date()
        let next = [autoDarkStartHour, autoDarkEndHour]
            .compactMap {
                Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(hour: $0, minute: 0),
                    matchingPolicy: .nextTime
                )
            }
            .min()
        guard let next else {
            return
        }
        let timer = Timer(
            fire: next.addingTimeInterval(1), interval: 0, repeats: false
        ) { [weak self] _ in
            self?.refreshAutoTheme()
        }
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    private func rebuildCache() {
        let dark = isDark
        resolvedDark = dark
        background    = dark ? .black : UIColor(white: 0.96, alpha: 1)
        surface       = dark ? UIColor(white: 0.1, alpha: 1) : .white
        primaryText   = dark ? .white : UIColor(white: 0.1, alpha: 1)
        secondaryText = dark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.45, alpha: 1)
        separator     = dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.88, alpha: 1)
        accent        = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        durationBackground = UIColor.black.withAlphaComponent(0.8)
        liveBadgeBackground = UIColor(red: 1, green: 0, blue: 0, alpha: 0.9)
        thumbnailPlaceholder = dark
            ? UIColor(white: 0.15, alpha: 1)
            : UIColor(white: 0.85, alpha: 1)
        newContentDot = dark
            ? UIColor(red: 62 / 255, green: 166 / 255, blue: 1, alpha: 1)
            : UIColor(red: 6 / 255, green: 95 / 255, blue: 212 / 255, alpha: 1)
        skeletonBase    = dark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.88, alpha: 1)
        skeletonShimmer = dark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.78, alpha: 1)
        skeletonBlock   = dark ? UIColor(white: 0.18, alpha: 1) : UIColor(white: 0.82, alpha: 1)
        barStyle = dark ? .black : .default
        statusBarStyle = dark ? .lightContent : .default
    }

    func applyGlobal() {
        let nav = UINavigationBar.appearance()
        nav.barStyle = barStyle
        nav.tintColor = isDark ? .white : accent
        nav.titleTextAttributes = [.foregroundColor: primaryText]

        let tab = UITabBar.appearance()
        tab.barStyle = barStyle
        tab.tintColor = isDark ? .white : accent

        // Appearance only affects fields created afterwards; long-lived
        // fields (e.g. the search bar) re-apply it on theme change.
        UITextField.appearance().keyboardAppearance = isDark ? .dark : .default
    }
}
