import os.log
import UIKit

/// The extension runs in its own process with no console of its own, so what
/// it did is only ever visible in the device log.
private let shareLog = OSLog(
    subsystem: "com.verback.YTLite.OpenIn", category: "share"
)

/// `UIApplication.open(_:options:completionHandler:)` is hidden from
/// extensions by the SDK, not by the runtime. Declaring its selector here and
/// binding the live application object to it calls the same method the system
/// still honours.
@objc
private protocol URLOpening {
    @objc(openURL:options:completionHandler:)
    func open(
        _ url: URL,
        options: [String: Any],
        completionHandler: ((Bool) -> Void)?
    )
}

/// Share-sheet entry: rewrites the shared youtube.com link to `ytlite://`
/// and hands it to Opaline. No UI — it opens the app and dismisses itself.
final class ShareViewController: UIViewController {
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // iOS kills a share extension that never returns and then hides it
        // from the share sheet until the next launch of the host app. Nothing
        // here is worth hanging on to, so the request is always closed out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finish()
        }
        loadSharedURL { [weak self] url in
            guard let self else {
                return
            }
            guard let url, let deepLink = self.deepLink(for: url) else {
                os_log(
                    "Opaline share: no video id in %{public}@",
                    log: shareLog,
                    type: .error,
                    url?.absoluteString ?? "nothing shared"
                )
                self.finish()
                return
            }
            self.open(deepLink)
        }
    }

    /// `?t=` and the shorts shape are carried over, so the app starts where
    /// the link points and in the right player.
    private func deepLink(for url: URL) -> URL? {
        let list = YouTubeLinkParser.playlistId(from: url)
        guard let videoId = YouTubeLinkParser.videoId(from: url) else {
            return list.flatMap { URL(string: "ytlite://playlist?list=\($0)") }
        }
        let playlist = list.map { "&list=\($0)" } ?? ""
        let seconds = YouTubeLinkParser.startSeconds(from: url)
        let timecode = seconds.map { "&t=\(Int($0))" } ?? ""
        let shorts = YouTubeLinkParser.isShort(url) ? "&shorts=1" : ""
        return URL(
            string: "ytlite://watch?v=\(videoId)" + timecode + shorts + playlist
        )
    }

    /// A shared item can carry the link as a URL or as plain text — Notes'
    /// share menu sends both — and which one an app registers varies, so every
    /// attachment is inspected and the first usable type wins.
    private func loadSharedURL(completion: @escaping (URL?) -> Void) {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        os_log(
            "Opaline share: %{public}d attachment(s): %{public}@",
            log: shareLog,
            type: .info,
            attachments.count,
            attachments.flatMap(\.registeredTypeIdentifiers).joined(separator: ",")
        )
        guard let match = firstUsable(of: attachments) else {
            completion(nil)
            return
        }
        match.0.loadItem(forTypeIdentifier: match.1, options: nil) { item, error in
            os_log(
                "Opaline share: loaded %{public}@ as %{public}@, error %{public}@",
                log: shareLog,
                type: .info,
                match.1,
                String(describing: type(of: item as Any)),
                error?.localizedDescription ?? "none"
            )
            DispatchQueue.main.async {
                completion(url(from: item))
            }
        }
    }

    /// `UIApplication.shared` is unavailable to extensions. `extensionContext`
    /// opens URLs on older iOS; where it refuses, the responder chain still
    /// reaches the hosting application.
    private func open(_ url: URL) {
        extensionContext?.open(url) { [weak self] opened in
            os_log(
                "Opaline share: context open %{public}@ -> %{public}d",
                log: shareLog,
                type: .info,
                url.absoluteString,
                opened
            )
            if !opened {
                self?.openViaResponderChain(url)
            }
            self?.finish()
        }
    }

    private func firstUsable(
        of attachments: [NSItemProvider]
    ) -> (NSItemProvider, String)? {
        let wanted = ["public.url", "public.plain-text", "public.text"]
        for provider in attachments {
            if let type = wanted.first(where: provider.hasItemConformingToTypeIdentifier) {
                return (provider, type)
            }
        }
        return nil
    }

    /// Restricted to `UIApplication`: other responders can answer an
    /// unrelated `openURL:` of their own, and calling one blind is how an
    /// extension crashes on an OS version it was never tried on.
    ///
    /// The three-argument selector is the one that still works. iOS 26 turned
    /// the old `openURL:` into a no-op that only logs "BUG IN CLIENT OF
    /// UIKIT", and `extensionContext.open` refuses outright from a share
    /// extension, so this is the remaining way to hand the link over.
    private func openViaResponderChain(_ url: URL) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: UIApplication.self),
               current.responds(to: selector) {
                os_log(
                    "Opaline share: opened via responder chain",
                    log: shareLog,
                    type: .info
                )
                unsafeBitCast(current, to: URLOpening.self)
                    .open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
        os_log(
            "Opaline share: no way to open the app",
            log: shareLog,
            type: .error
        )
    }

    private func finish() {
        guard !didFinish else {
            return
        }
        didFinish = true
        extensionContext?.completeRequest(returningItems: nil)
    }
}

/// Pulls the first YouTube link out of a shared plain-text item; passes a
/// shared URL through untouched.
private func url(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url
    }
    // Apps hand the same link over in whatever form they stored it.
    let text: String
    switch item {
    case let string as String:
        text = string
    case let attributed as NSAttributedString:
        text = attributed.string
    case let data as Data:
        guard let decoded = String(bytes: data, encoding: .utf8) else {
            return nil
        }
        text = decoded
    default:
        return nil
    }
    let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    let range = NSRange(text.startIndex..., in: text)
    return detector?
        .matches(in: text, options: [], range: range)
        .compactMap(\.url)
        .first(where: YouTubeLinkParser.handles)
}
