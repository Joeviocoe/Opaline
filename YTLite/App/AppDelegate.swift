import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let dependencies = AppDependencies.live()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        runMigrations()
        configureSharedDependencies()
        ThemeManager.shared.applyGlobal()
        BackgroundPlaybackService.apply()
        application.beginReceivingRemoteControlEvents()
        if ReturnYouTubeDislikeService.enabled {
            ReturnYouTubeDislikeService.shared.prepareIfNeeded()
        }
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = makeSplashViewController()
        window?.makeKeyAndVisible()
        applyWindowTheme()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthRequired),
            name: .authorizationRequired,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyWindowTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        return true
    }

    /// System-drawn elements (table section headers/footers, switches,
    /// segmented controls, alerts) resolve dynamic colors from the window's
    /// trait, not the app palette — keep the two in sync.
    @objc
    private func applyWindowTheme() {
        if #available(iOS 13.0, *) {
            window?.overrideUserInterfaceStyle =
                ThemeManager.shared.isDark ? .dark : .light
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Auto theme can go stale in the background (schedule boundary or a
        // system appearance change while suspended).
        ThemeManager.shared.refreshAutoTheme()
    }

    private func makeSplashViewController() -> SplashViewController {
        let splash = SplashViewController()
        splash.onComplete = { [weak self] in
            if OAuthClient.shared.isSignedIn {
                UserProfileStore.shared.load()
                OAuthClient.shared.refreshIfStale()
                self?.showMain()
                WatchProgressSyncService.shared.syncIfNeeded()
            } else if OAuthClient.shared.isAnonymous {
                self?.showMain()
            } else {
                self?.showAuth()
            }
        }
        return splash
    }

    private func runMigrations() {
        // Before the Auto source existed, android_vr was both the default and
        // an explicit picker choice, so stored values are indistinguishable
        // from "never touched it". Move them to Auto once; anyone re-picking
        // Android VR afterwards keeps it.
        let defaults = UserDefaults.standard
        guard !defaults.bool(
            forKey: UserDefaultsKeys.Migration.playbackSourceAuto
        ) else { return }
        defaults.set(
            true,
            forKey: UserDefaultsKeys.Migration.playbackSourceAuto
        )
        let stored = defaults.string(
            forKey: UserDefaultsKeys.Debug.playbackSource
        )
        if stored == PlaybackSource.androidVR.rawValue {
            defaults.removeObject(
                forKey: UserDefaultsKeys.Debug.playbackSource
            )
        }
    }

    private func configureSharedDependencies() {
        UserProfileStore.shared.configure(
            accountService: dependencies.accountService
        )
        ChannelInfoStore.shared.configure(
            channelService: dependencies.channelService
        )
        VideoRouter.shared.watchViewControllerFactory = { [dependencies] video in
            dependencies.makeWatchViewController(video: video)
        }
    }

    func showMain() {
        window?.rootViewController = makeMain(dependencies: dependencies)
    }

    private func makeMain(dependencies: AppDependencies) -> UIViewController {
        RootContainerViewController(
            mainTabBar: MainTabBarController(dependencies: dependencies)
        )
    }

    @objc
    private func handleAuthRequired() {
        DispatchQueue.main.async { [weak self] in
            guard let root = self?.window?.rootViewController,
                  !(root is AuthViewController),
                  !(root is SplashViewController),
                  root.presentedViewController == nil
            else { return }
            let auth = AuthViewController()
            auth.onAuthorized = { [weak self] in
                root.dismiss(animated: true)
                UserProfileStore.shared.load()
                self?.window?.rootViewController = self?.makeMain(
                    dependencies: self?.dependencies ?? AppDependencies.live()
                )
            }
            auth.onContinueAnonymously = { [weak self] in
                root.dismiss(animated: true)
                self?.showMain()
            }
            root.present(auth, animated: true)
        }
    }
}
