import AVFoundation
import Foundation

/// Serves one googlevideo stream to AVFoundation as bounded ranged fetches.
///
/// **Why this is mandatory, not an optimisation.** An `AVURLAsset` pointed
/// straight at a googlevideo URL issues an open-ended GET, and googlevideo
/// refuses it: a throttled visitor identity is cut off after roughly
/// `HLSPlaybackBuilder.throttleWindowBytes` (~1 MiB), and "asking for more than
/// this in one range is refused outright". Measured on an iPad 3 against a
/// 78 MB 720p stream: `loadValuesAsynchronously` never called back at all, and
/// the app sat on "Resolving stream…" indefinitely with flat memory and no
/// network progress.
///
/// So the asset is given a custom scheme instead, AVFoundation asks this
/// delegate for byte ranges, and each one is fetched under the window and
/// handed back.
///
/// One loader instance serves one stream; `CompositionDelivery` makes two, one
/// for video and one for audio, and keeps both alive for the item's lifetime —
/// AVFoundation holds the delegate weakly, and a released loader stalls
/// playback exactly like the open-ended GET did.
final class CompositionResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    /// Custom scheme, so AVFoundation hands the request to us rather than
    /// fetching it itself.
    static let scheme = "opaline-stream"

    /// Stay under googlevideo's throttle window. Chosen a little below
    /// `HLSPlaybackBuilder.throttleWindowBytes` so a request that straddles a
    /// boundary still lands inside it.
    private static let chunkSize: Int64 = 900_000

    /// The other stream's loader, held so a single `PreparedPlayback.resourceLoader`
    /// keeps both alive. AVFoundation holds delegates weakly and the player
    /// retains only one of them, so without this the audio loader is released
    /// the moment `prepare` returns and audio silently never loads.
    var companion: CompositionResourceLoader?

    /// Delegate callbacks arrive here; `setDelegate(_:queue:)` requires one.
    let loaderQueue = DispatchQueue(label: "opaline.composition.loader")

    private let url: URL
    /// "video" or "audio", for logs only -- two loaders run at once and their
    /// messages are otherwise indistinguishable.
    private let label: String
    private let headers: [String: String]
    private let contentLength: Int64
    private let contentType: String
    private let session: URLSession
    /// Requests in flight, so cancellation can stop the work behind them.
    private var tasks: [ObjectIdentifier: URLSessionTask] = [:]
    /// Log the first handful of chunks only: a 78 MB stream is ~87 of them and
    /// the log rotates at 512 KB.
    private var chunkLogBudget = 6
    private var logChunks: Bool { chunkLogBudget > 0 }
    private let lock = NSLock()

    init(url: URL, headers: [String: String], contentLength: Int64, mimeType: String) {
        self.url = url
        self.headers = headers
        self.contentLength = contentLength
        // AVFoundation wants a UTI here, not a MIME type, and it must match what
        // the bytes actually are: an audio-only MP4 declared as the movie UTI
        // gives "tracks failed" with no further detail.
        contentType = mimeType.contains("audio")
            ? "com.apple.m4a-audio"
            : "public.mpeg-4"
        label = mimeType.contains("audio") ? "audio" : "video"
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        // No caching, and this is load-bearing rather than hygiene. URLCache
        // keys on the URL alone and ignores the Range header, so every ranged
        // request to the same stream is answered from the cache with whatever
        // the FIRST one returned. Measured on the device: after an opening
        // 2-byte probe, every subsequent "asked 900000" came back "got 2", the
        // offsets crawled forward two bytes at a time, and AVFoundation gave up
        // with "Cannot Open".
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: config)
        super.init()
    }

    /// The URL to hand `AVURLAsset`, which routes loading through this delegate.
    static func maskedURL(for original: URL, tag: String) -> URL {
        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        // Video and audio would otherwise be indistinguishable to AVFoundation's
        // cache when their googlevideo URLs differ only in query order.
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "__opaline", value: tag))
        components?.queryItems = items
        return components?.url ?? original
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = contentLength
            // Without this AVFoundation asks for the whole file in one request,
            // which is the very thing that stalls.
            info.isByteRangeAccessSupported = true
            AppLog.player(
                "composition loader[\(label)]: content info -> \(contentType),"
                    + " \(contentLength) B"
            )
        }
        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        AppLog.player(
            "composition loader[\(label)]: want \(dataRequest.requestedOffset)"
                + "+\(dataRequest.requestedLength)"
                + (dataRequest.requestsAllDataToEndOfResource ? " (to end)" : "")
        )
        fetch(from: dataRequest.currentOffset, for: loadingRequest)
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let key = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: key)
        lock.unlock()
        task?.cancel()
    }

    // MARK: - Fetching

    /// Serves one loading request as a chain of bounded ranged fetches.
    ///
    /// Each call fetches at most `chunkSize`, hands it over, and recurses from
    /// the new offset until the request is satisfied. The recursion runs through
    /// URLSession completion handlers, so it does not grow the stack.
    ///
    /// **`requestsAllDataToEndOfResource` is the case that matters.** AVFoundation
    /// asks for the entire stream up front — 78 MB for the 720p video — and an
    /// earlier version treated one chunk as the whole answer and called
    /// `finishLoading()`. From AVFoundation's side the file then simply ended at
    /// 900 KB, so it had no parseable tracks and reported the useless
    /// "The operation could not be completed". Serving it in pieces is the point;
    /// finishing early defeats it. In practice AVFoundation cancels the request
    /// once it has the moov atom it needs, so the whole file is rarely fetched.
    private func fetch(from start: Int64, for loadingRequest: AVAssetResourceLoadingRequest) {
        guard !loadingRequest.isCancelled,
              let dataRequest = loadingRequest.dataRequest else {
            return
        }
        let targetEnd = dataRequest.requestsAllDataToEndOfResource
            ? contentLength
            : min(
                dataRequest.requestedOffset + Int64(dataRequest.requestedLength),
                contentLength
            )
        guard start < targetEnd else {
            loadingRequest.finishLoading()
            return
        }
        let end = min(start + Self.chunkSize, targetEnd) - 1

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

        let key = ObjectIdentifier(loadingRequest)
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            self.lock.lock()
            self.tasks.removeValue(forKey: key)
            self.lock.unlock()
            guard !loadingRequest.isCancelled else { return }

            if let error = error {
                AppLog.player(
                    "composition loader[\(self.label)]: transport error"
                        + " on bytes=\(start)-\(end): \(error.localizedDescription)"
                )
                loadingRequest.finishLoading(with: error)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 206 for a satisfied range, 200 if the server ignored it.
            guard (200...299).contains(status), let data = data, !data.isEmpty else {
                AppLog.player(
                    "composition loader[\(self.label)]: HTTP \(status)"
                        + " for bytes=\(start)-\(end), \(data?.count ?? 0) B"
                )
                loadingRequest.finishLoading(with: NSError(
                    domain: "CompositionResourceLoader",
                    code: status,
                    userInfo: [NSLocalizedDescriptionKey: "range refused (HTTP \(status))"]
                ))
                return
            }
            // Serve no more than was asked for. A server that ignores `Range`
            // answers 200 with the entire body, and handing AVFoundation
            // megabytes where it asked for two bytes makes it reject the asset
            // outright -- which looks identical to a corrupt container.
            let wanted = Int(end - start + 1)
            let slice = data.count > wanted ? data.prefix(wanted) : data[...]
            if data.count < wanted, end + 1 < self.contentLength {
                AppLog.player(
                    "composition loader[\(self.label)]: SHORT READ"
                        + " bytes=\(start)-\(end) asked \(wanted) got \(data.count)"
                )
            }
            if self.logChunks {
                AppLog.player(
                    "composition loader[\(self.label)]: HTTP \(status)"
                        + " bytes=\(start)-\(end) asked \(wanted) got \(data.count)"
                        + (status == 200 ? "  <-- RANGE IGNORED" : "")
                )
                self.chunkLogBudget -= 1
            }
            dataRequest.respond(with: Data(slice))
            self.fetch(from: start + Int64(slice.count), for: loadingRequest)
        }
        lock.lock()
        tasks[key] = task
        lock.unlock()
        task.priority = URLSessionTask.highPriority
        task.resume()
    }
}
