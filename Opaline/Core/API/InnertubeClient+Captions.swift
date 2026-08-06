import Foundation

// MARK: - Caption tracks via the IOS player client

// Timedtext URLs from the WEB client (watch-page HTML) are gated behind a
// proof-of-origin token and come back with empty bodies. The IOS client's
// caption URLs are still served without a token, so sources that resolve
// playback outside Innertube (WebView HLS) fetch caption tracks here.

extension InnertubeClient {
    func fetchCaptionTracks(
        videoId: String,
        completion: @escaping ([SubtitleTrack]) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/player?prettyPrint=false") else {
            completion([])
            return
        }
        var body = InnertubeContexts.ios
        body["videoId"] = videoId
        body["contentCheckOk"] = true
        body["racyCheckOk"] = true
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion([])
            return
        }
        let headers = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.userAgent: UserAgent.iosYouTube
        ]
        api.post(url: url, body: bodyData, headers: headers) { result in
            guard let data = try? result.get(),
                  let json = (try? JSONSerialization.jsonObject(with: data))
                  as? [String: Any]
            else {
                AppLog.player("captionTracks(ios): request failed")
                completion([])
                return
            }
            let tracks = Self.extractCaptionTracks(json)
            AppLog.player("captionTracks(ios): \(tracks.count) tracks")
            completion(tracks)
        }
    }
}
