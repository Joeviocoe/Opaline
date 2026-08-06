import Foundation
import JavaScriptCore

// MARK: - n / sig challenge solving

extension HLSStreamResolver {
    /// Challenge kinds the EJS solver understands: `n` (throttling) and `sig`
    /// (the `signatureCipher` `s` value on ciphered formats).
    enum ChallengeKind: String {
        case nThrottle = "n"
        case sig = "sig"
    }

    static var solverBridge: String {
        "var meriyah = (typeof lib !== 'undefined' && lib.meriyah)"
            + " || undefined; var astring = (typeof lib !== 'undefined'"
            + " && lib.astring) || undefined;"
    }

    static var solverWrapper: String {
        """
        function __ytSolve(playerText, kind, value) {
          try {
            var r = jsc({
              type: 'player', player: playerText,
              requests: [{ type: kind, challenges: [value] }]
            });
            if (r && r.responses && r.responses[0]
              && r.responses[0].data) {
              var s = r.responses[0].data[value];
              return (typeof s === 'string' && s !== value) ? s : '';
            }
          } catch (e) { return 'ERR:' + e; }
          return '';
        }
        """
    }

    static func playerJSURL(_ jsPath: String) -> URL? {
        if jsPath.hasPrefix("http") {
            return URL(string: jsPath)
        }
        return URL(string: "https://www.youtube.com" + jsPath)
    }

    /// Solves the n-throttling signature. See `solve(kind:)`.
    func solveN(
        unsolved: String,
        jsPath: String?,
        completion: @escaping (String?) -> Void
    ) {
        solve(
            kind: .nThrottle, unsolved: unsolved, jsPath: jsPath, completion: completion
        )
    }

    /// Deciphers a `signatureCipher` `s` challenge. See `solve(kind:)`.
    func solveSig(
        unsolved: String,
        jsPath: String?,
        completion: @escaping (String?) -> Void
    ) {
        solve(kind: .sig, unsolved: unsolved, jsPath: jsPath, completion: completion)
    }

    /// Solves a player challenge. Results are memoized per (kind, player JS,
    /// value) — repeated values skip solving entirely. Tries the on-device
    /// JSContext solver (iOS 14+) first, then falls back to the remote solver
    /// (required on iOS 12/13, where base.js ES2020 syntax cannot be parsed
    /// on-device).
    private func solve(
        kind: ChallengeKind,
        unsolved: String,
        jsPath: String?,
        completion: @escaping (String?) -> Void
    ) {
        let cacheKey = "\(kind.rawValue)|\(jsPath ?? "")|\(unsolved)"
        if let cached = cachedSolvedN(for: cacheKey) {
            AppLog.player("hlsResolve: \(kind.rawValue) cache hit")
            completion(cached)
            return
        }
        solveOnDevice(kind: kind, unsolved: unsolved, jsPath: jsPath) { [weak self] solved in
            if let solved {
                self?.storeSolvedN(solved, for: cacheKey)
                completion(solved)
                return
            }
            self?.solveRemote(kind: kind, unsolved: unsolved, jsPath: jsPath) { solved in
                if let solved {
                    self?.storeSolvedN(solved, for: cacheKey)
                }
                completion(solved)
            }
        }
    }

    private func solveOnDevice(
        kind: ChallengeKind,
        unsolved: String,
        jsPath: String?,
        completion: @escaping (String?) -> Void
    ) {
        guard #available(iOS 14.0, *) else {
            AppLog.player("hlsResolve: on-device solve needs iOS 14+")
            completion(nil)
            return
        }
        guard let jsPath, let baseURL = Self.playerJSURL(jsPath) else {
            completion(nil)
            return
        }
        if let cached = cachedPlayerJS(path: jsPath) {
            runSolverAsync(
                baseJS: cached, kind: kind, unsolved: unsolved, completion: completion
            )
            return
        }
        fetchText(url: baseURL) { [weak self] result in
            guard let self, case let .success(baseJS) = result else {
                completion(nil)
                return
            }
            storePlayerJS(baseJS, path: jsPath)
            runSolverAsync(
                baseJS: baseJS, kind: kind, unsolved: unsolved, completion: completion
            )
        }
    }

    private func runSolverAsync(
        baseJS: String,
        kind: ChallengeKind,
        unsolved: String,
        completion: @escaping (String?) -> Void
    ) {
        solverQueue.async { [weak self] in
            completion(
                self?.runSolver(baseJS: baseJS, kind: kind, unsolved: unsolved)
            )
        }
    }

    /// Loads the solver library once into a reused context. Must run on
    /// `solverQueue` (a `JSContext` is not thread-safe).
    private func sharedSolverContext() -> JSContext? {
        if let context = solverContext {
            return context
        }
        guard let context = JSContext() else {
            return nil
        }
        context.exceptionHandler = { _, value in
            AppLog.player("hlsResolve: JS exception \(value?.toString() ?? "")")
        }
        context.evaluateScript(WebViewHLSSolverJS.lib)
        context.evaluateScript(Self.solverBridge)
        context.evaluateScript(WebViewHLSSolverJS.core)
        context.evaluateScript(Self.solverWrapper)
        solverContext = context
        return context
    }

    /// Runs on `solverQueue`. Reuses the shared context and reclaims the garbage
    /// from parsing the (multi-MB) player JS after each solve so the JS heap
    /// doesn't grow across videos.
    private func runSolver(
        baseJS: String, kind: ChallengeKind, unsolved: String
    ) -> String? {
        guard let context = sharedSolverContext(),
              let fn = context.objectForKeyedSubscript("__ytSolve") else {
            return nil
        }
        let value = fn.call(withArguments: [baseJS, kind.rawValue, unsolved])
        let result = value?.toString()
        JSGarbageCollect(context.jsGlobalContextRef)
        guard let solved = result, !solved.isEmpty, !solved.hasPrefix("ERR:") else {
            if let result, result.hasPrefix("ERR:") {
                AppLog.player("hlsResolve: solver \(result)")
            }
            return nil
        }
        return solved
    }
}
