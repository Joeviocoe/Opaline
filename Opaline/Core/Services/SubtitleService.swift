import Foundation

final class SubtitleService {
    static let shared = SubtitleService()

    private var cache: [URL: [SubtitleCue]] = [:]
    private var pending: [URL: [(([SubtitleCue]) -> Void)]] = [:]
    private let queue = DispatchQueue(
        label: "com.verback.YTLite.subtitles"
    )
    private let transport: HTTPTransport

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
    }

    func load(
        track: SubtitleTrack,
        completion: @escaping ([SubtitleCue]) -> Void
    ) {
        // Append format=vtt to get WebVTT
        guard var comps = URLComponents(
            url: track.url,
            resolvingAgainstBaseURL: false
        ) else {
            completion([])
            return
        }
        var queryItems = comps.queryItems ?? []
        // Replace existing fmt param (YouTube default is srv3/XML)
        queryItems.removeAll { $0.name == "fmt" }
        queryItems.append(
            URLQueryItem(name: "fmt", value: "vtt")
        )
        comps.queryItems = queryItems
        guard let url = comps.url else {
            completion([])
            return
        }
        queue.async { [weak self] in
            self?.fetchCached(url: url, completion: completion)
        }
    }

    private func fetchCached(
        url: URL,
        completion: @escaping ([SubtitleCue]) -> Void
    ) {
        if let cached = cache[url] {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        if pending[url] != nil {
            pending[url]?.append(completion)
            return
        }
        pending[url] = [completion]
        performFetch(url: url)
    }

    private func performFetch(url: URL) {
        transport.send(
            HTTPRequest(method: .get, url: url),
            cancellationToken: nil
        ) { [weak self] result in
            switch result {
            case .success(let response):
                if response.status != 200 {
                    AppLog.player(
                        "subtitle fetch: HTTP \(response.status)"
                            + " url=\(url.absoluteString.prefix(120))"
                    )
                }
                self?.handleFetchResponse(
                    url: url,
                    data: response.data
                )
            case .failure(let error):
                AppLog.player(
                    "subtitle fetch failed: \(error)"
                        + " url=\(url.absoluteString.prefix(120))"
                )
                self?.handleFetchResponse(url: url, data: nil)
            }
        }
    }

    private func handleFetchResponse(
        url: URL,
        data: Data?
    ) {
        let cues: [SubtitleCue]
        if let data,
           let text = String(data: data, encoding: .utf8) {
            cues = VTTParser.parse(text)
            if cues.isEmpty && !text.isEmpty {
                let preview = String(text.prefix(200))
                AppLog.player(
                    "subtitle parse: 0 cues from"
                        + " \(data.count)b, preview=\(preview)"
                )
            }
        } else {
            cues = []
        }
        queue.async { [weak self] in
            self?.cache[url] = cues
            let callbacks = self?.pending.removeValue(forKey: url) ?? []
            DispatchQueue.main.async {
                callbacks.forEach { $0(cues) }
            }
        }
    }

    func clearCache() {
        queue.async { [weak self] in
            self?.cache = [:]
        }
    }
}
