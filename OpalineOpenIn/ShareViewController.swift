import MobileCoreServices
import UIKit

/// Share-sheet entry: rewrites the shared youtube.com link to `ytlite://`
/// and hands it to Opaline. No UI — it opens the app and dismisses itself.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadSharedURL { [weak self] url in
            guard let self else {
                return
            }
            guard let url, let deepLink = self.deepLink(for: url) else {
                self.finish()
                return
            }
            self.open(deepLink)
        }
    }

    /// `?t=` is carried over so the app starts where the link points.
    private func deepLink(for url: URL) -> URL? {
        guard let videoId = YouTubeLinkParser.videoId(from: url) else {
            return nil
        }
        let seconds = YouTubeLinkParser.startSeconds(from: url)
        let timecode = seconds.map { "&t=\(Int($0))" } ?? ""
        return URL(string: "ytlite://watch?v=\(videoId)" + timecode)
    }

    /// A shared item can carry the link as a URL or as plain text — Notes'
    /// share menu sends both — so both are accepted, first match wins.
    private func loadSharedURL(completion: @escaping (URL?) -> Void) {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let types = [kUTTypeURL as String, kUTTypePlainText as String]
        guard let type = types.first(where: { type in
            attachments.contains { $0.hasItemConformingToTypeIdentifier(type) }
        }), let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(type)
        }) else {
            completion(nil)
            return
        }
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
            DispatchQueue.main.async {
                completion(url(from: item))
            }
        }
    }

    /// `UIApplication.shared` is unavailable to extensions. `extensionContext`
    /// opens URLs on most iOS versions; where it refuses, the responder chain
    /// still reaches the hosting application.
    private func open(_ url: URL) {
        extensionContext?.open(url) { [weak self] opened in
            if !opened {
                self?.openViaResponderChain(url)
            }
            self?.finish()
        }
    }

    private func openViaResponderChain(_ url: URL) {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

/// Pulls the first YouTube link out of a shared plain-text item; passes a
/// shared URL through untouched.
private func url(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url
    }
    guard let text = item as? String else {
        return nil
    }
    let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    let range = NSRange(text.startIndex..., in: text)
    return detector?
        .matches(in: text, options: [], range: range)
        .compactMap(\.url)
        .first { YouTubeLinkParser.videoId(from: $0) != nil }
}
