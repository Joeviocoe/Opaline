import UIKit

/// Shared cache for the authenticated user's profile data (avatar + display name).
/// Loaded once after sign-in and cleared on sign-out.
final class UserProfileStore {
    static let shared = UserProfileStore()
    static let didUpdateNotification = Notification.Name("UserProfileStoreDidUpdate")

    private(set) var avatarImage: UIImage?
    private(set) var displayName: String?
    private var accountService: AccountService?
    private var isLoading = false
    private let transport: HTTPTransport

    init(transport: HTTPTransport = ServiceContainer.mediaTransport) {
        self.transport = transport
    }

    func configure(accountService: AccountService) {
        self.accountService = accountService
    }

    func load() {
        guard OAuthClient.shared.isSignedIn, !isLoading
        else { return }
        guard let accountService else {
            assertionFailure("UserProfileStore is not configured")
            return
        }
        isLoading = true

        accountService.fetchAccountInfo { [weak self] result in
            guard let self
            else { return }
            switch result {
            case .failure(let err):
                AppLog.auth("fetchAccountInfo failed: \(err)")
                self.isLoading = false
            case .success(let info):
                self.handleAccountInfo(info)
            }
        }
    }

    private func handleAccountInfo(_ info: (name: String, avatarURL: String?)) {
        displayName = info.name
        guard let urlStr = info.avatarURL,
              let avatarURL = URL(string: urlStr)
        else {
            isLoading = false
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.didUpdateNotification,
                    object: nil
                )
            }
            return
        }
        transport.send(
            HTTPRequest(method: .get, url: avatarURL),
            cancellationToken: nil
        ) { [weak self] result in
            guard let self
            else { return }
            self.isLoading = false
            if let data = try? result.get().data, let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.avatarImage = img
                    NotificationCenter.default.post(
                        name: Self.didUpdateNotification,
                        object: nil
                    )
                }
            }
        }
    }

    func clear() {
        avatarImage = nil
        displayName = nil
        isLoading = false
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }
}
