import Foundation

// MARK: - Audio-track (dub) metadata via the IOS player client

// The dub listing is per-video metadata, identical across the clients that
// expose it (track ids like "ru.3" match mweb's), but access cost differs:
// mweb's /player wants a fresh STS and often a pot, while the IOS client
// answers logged-out with neither — the same reason caption tracks are
// fetched through it. Playback itself still goes through mweb; this call
// only feeds the picker.

extension InnertubeClient {
    /// One entry per distinct `audioTrack.id`, original (id suffix ".4")
    /// first — `audioIsDefault` follows the request `hl`, not the upload
    /// language. Fewer than two tracks collapses to `[]`.
    static func extractAudioTrackList(
        _ json: [String: Any]
    ) -> [AudioTrackInfo] {
        let adaptive = ((json["streamingData"] as? [String: Any])?[
            "adaptiveFormats"
        ] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        let tracks: [AudioTrackInfo] = adaptive.compactMap { fmt in
            guard let track = fmt["audioTrack"] as? [String: Any],
                  let id = track["id"] as? String,
                  seen.insert(id).inserted else {
                return nil
            }
            return AudioTrackInfo(
                id: id,
                displayName: (track["displayName"] as? String) ?? id,
                isDefault: (track["audioIsDefault"] as? Bool) ?? false
            )
        }
        guard tracks.count > 1 else {
            return []
        }
        return tracks.sorted { lhs, rhs in
            let lo = lhs.id.hasSuffix(".4")
            if lo != rhs.id.hasSuffix(".4") {
                return lo
            }
            return lhs.displayName < rhs.displayName
        }
    }

    func fetchAudioTrackList(
        videoId: String,
        completion: @escaping ([AudioTrackInfo]) -> Void
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
                AppLog.player("audioTracks(ios): request failed")
                completion([])
                return
            }
            let tracks = Self.extractAudioTrackList(json)
            AppLog.player("audioTracks(ios): \(tracks.count) tracks")
            completion(tracks)
        }
    }
}
