import UIKit
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    /// A sign-in screen was asked for while the app ran in the background;
    /// the decision is re-taken in `applicationDidBecomeActive`.
    var deferredAuthPresentation = false
    private let dependencies = AppDependencies.live()
    /// Built during the splash, handed over by `showMain`.
    private var preloadedMain: UIViewController?
    /// A `ytlite://` or youtube.com link that arrived while the splash or
    /// auth screen was still up — replayed once `showMain` puts the tab
    /// bar on screen. See `AppDelegate+DeepLink.swift`.
    var pendingDeepLink: URL?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AppLog.banner()
        #if LEGACY_IOS9
        // Before anything else: on armv7 a missed 32-bit narrowing kills the
        // process with no crash log, and this is the only thing that says so.
        LegacyDiagnostics.install()
        #endif
        configureServices(application)
        // The player has to know how the phone is held the moment it opens —
        // too late to start asking then.
        HeldOrientation.startTracking()
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = makeSplashViewController()
        window?.makeKeyAndVisible()
        applyWindowTheme()
        // Build the real UI while the splash is still covering the screen.
        // Its fade is a Core Animation animation, so it keeps running on the
        // render server even though this blocks the main thread for a while
        // — the cold-start cost is paid behind the logo instead of in front
        // of the user. Deferred by one turn so the splash gets its first
        // frame out before we take the thread.
        DispatchQueue.main.async { [weak self] in
            self?.preloadMainIfNeeded()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthRequired),
            name: .authorizationRequired,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(warmSecondaryTabs),
            name: .homeFeedDidSettle,
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
        UpdateNotificationService.shared.checkIfNeeded()
        resolveDeferredAuthIfNeeded()
    }

    /// Legacy background fetch is kept as the single code path across iOS
    /// 12…latest instead of BGTaskScheduler; deprecated on iOS 13+.
    @available(iOS, deprecated: 13.0, message: "Single code path for iOS 12+.")
    private func configureLegacyBackgroundFetch(_ application: UIApplication) {
        application.setMinimumBackgroundFetchInterval(
            UIApplication.backgroundFetchIntervalMinimum
        )
    }

    /// The keychain is readable again now, so a "signed out" verdict reached
    /// in the background can be re-checked before it costs the user a
    /// pointless sign-in.
    private func resolveDeferredAuthIfNeeded() {
        guard deferredAuthPresentation else {
            return
        }
        deferredAuthPresentation = false
        if OAuthClient.shared.isSignedIn {
            AppLog.auth("deferred sign-in dropped: token readable again")
            UserProfileStore.shared.load()
            showMain()
        } else {
            showAuth()
        }
    }

    private func configureServices(_ application: UIApplication) {
        runMigrations()
        configureSharedDependencies()
        ThemeManager.shared.applyGlobal()
        BackgroundPlaybackService.apply()
        application.beginReceivingRemoteControlEvents()
        configureLegacyBackgroundFetch(application)
        UNUserNotificationCenter.current().delegate = self
        if ReturnYouTubeDislikeService.enabled {
            ReturnYouTubeDislikeService.shared.prepareIfNeeded()
        }
        #if LEGACY_IOS9
        // On by default here: an A5X stalls the main thread where an A12 never
        // would, so the watchdog is the bring-up's main signal rather than a
        // debug extra. Still switchable in Settings.
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.Debug.mainThreadWatchdog) == nil
            || UserDefaults.standard.bool(forKey: UserDefaultsKeys.Debug.mainThreadWatchdog) {
            startMainThreadWatchdog()
        }
        #else
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.Debug.mainThreadWatchdog) {
            startMainThreadWatchdog()
        }
        #endif
    }

    /// Once per launch: the caches only need filling before the user
    /// first opens those tabs, and the screens revalidate themselves
    /// on every appearance after that.
    @objc
    private func warmSecondaryTabs() {
        NotificationCenter.default.removeObserver(
            self, name: .homeFeedDidSettle, object: nil
        )
        BackgroundRefreshService.shared.warmSecondaryCaches()
        // The same idle moment suits the TV n-solver: waiting for it here costs
        // nobody anything, waiting for it at playback costs the first video.
        TVSolverWarmup.warmIfNeeded()
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

    private func configureSharedDependencies() {
        UserProfileStore.shared.configure(
            accountService: dependencies.accountService
        )
        ChannelInfoStore.shared.configure(
            channelService: dependencies.channelService
        )
        VideoRouter.shared.channelViewControllerFactory = { [dependencies] id, name in
            dependencies.makeChannelViewController(channelId: id, channelName: name)
        }
        VideoRouter.shared.playlistViewControllerFactory = { [dependencies] playlist in
            dependencies.makePlaylistViewController(playlist: playlist)
        }
        VideoRouter.shared.watchViewControllerFactory = { [dependencies] video in
            dependencies.makeWatchViewController(video: video)
        }
        let deps = dependencies
        VideoRouter.shared.shortsViewControllerFactory = { video, entry in
            deps.makeShortsViewController(seedVideo: video, entry: entry)
        }
    }

    func startMainThreadWatchdog() {
        MainThreadWatchdog.shared.start { [weak self] in self?.window?.rootViewController }
    }

    func stopMainThreadWatchdog() {
        MainThreadWatchdog.shared.stop()
    }

    func showMain() {
        preloadMainIfNeeded()
        window?.rootViewController = preloadedMain
            ?? makeMain(dependencies: dependencies)
        preloadedMain = nil
        replayPendingDeepLinkIfNeeded()
    }

    /// Constructs the tab bar and forces the first screen through a full
    /// load-and-layout pass, which is where the ~850ms of cold-start work
    /// lives (three navigation controllers, the tab icons, the feed's cache
    /// read and the first `reloadData`). Idempotent and cheap to call twice.
    private func preloadMainIfNeeded() {
        guard preloadedMain == nil, let window = window else {
            return
        }
        guard OAuthClient.shared.isSignedIn
            || OAuthClient.shared.isAnonymous
        else {
            return
        }
        let main = makeMain(dependencies: dependencies)
        main.view.frame = window.bounds
        main.view.layoutIfNeeded()
        preloadedMain = main
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
