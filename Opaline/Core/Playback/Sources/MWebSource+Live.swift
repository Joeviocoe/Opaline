import Foundation

// MARK: - Live HLS

extension MWebSource {
    /// No DASH ladder usually means a live stream. Unlike android_vr, the mweb
    /// manifest URL carries an unsolved `n` — as a PATH segment, not a query
    /// param — which the manifest server copies verbatim into every generated
    /// segment URL, 403ing them all. So: solve `n`, append the `pot`, and only
    /// then hand the URL to [[LiveHLSPlayback]].
    func loadLiveHLS(
        info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let url = info.hlsManifestURL else {
            completion(.failure(Self.noStreamError))
            return
        }
        solveLiveManifestN(url) { [weak self] solvedURL in
            guard let self else {
                return
            }
            self.potWait.notify(queue: .main) { [weak self] in
                guard let self else {
                    return
                }
                var manifestURL = solvedURL
                if let poToken = self.poToken {
                    manifestURL = Self.appendingQuery(
                        manifestURL, name: "pot", value: poToken
                    )
                }
                self.startLiveHLS(url: manifestURL, info: info, completion: completion)
            }
        }
    }

    // MARK: - Private

    private func solveLiveManifestN(_ url: URL, completion: @escaping (URL) -> Void) {
        guard let unsolved = Self.livePathN(of: url) else {
            completion(url)
            return
        }
        resolver.solveN(unsolved: unsolved, jsPath: Self.cachedJsPath) { solved in
            AppLog.player("mwebSource: live n \(unsolved) -> \(solved ?? "FAILED(nil)")")
            completion(Self.replacingLivePathN(in: url, solved: solved))
        }
    }

    private func startLiveHLS(
        url: URL,
        info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        liveHLS.load(url: url, info: info) { [weak self] prepared in
            guard let self else {
                return
            }
            if !self.liveHLS.qualities.isEmpty {
                self.applyLiveQualityState()
            }
            completion(.success(prepared))
        }
    }
}
