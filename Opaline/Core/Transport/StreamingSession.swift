import Foundation

/// A `URLSession` that reports a response body as it arrives instead of
/// buffering it whole.
///
/// `dataTask(with:completionHandler:)` only calls back once the last byte has
/// landed. That is fine for a JSON page and wrong for SABR, whose responses run
/// to ten megabytes and carry several media segments: the first segment is
/// complete seconds before the response is, and the player is waiting for it.
final class StreamingSession: NSObject, URLSessionDataDelegate {
    /// What one in-flight task needs to report itself.
    private struct Sink {
        let onChunk: (Data) -> Bool
        let completion: (Result<HTTPResponse, Error>) -> Void
        var status = 0
        var headers: [String: String] = [:]
    }

    private var sinks: [Int: Sink] = [:]
    /// Guards `sinks`. The delegate callbacks arrive on the session's own
    /// serial queue, but `start` is called from the caller's thread.
    private let lock = NSLock()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func start(
        _ request: URLRequest,
        cancellationToken: CancellationToken?,
        onChunk: @escaping (Data) -> Bool,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        let task = session.dataTask(with: request)
        lock.lock()
        sinks[task.taskIdentifier] = Sink(onChunk: onChunk, completion: completion)
        lock.unlock()
        // Everything streamed here is playback: the SABR pump.
        task.priority = URLSessionTask.highPriority
        cancellationToken?.register(task)
        task.resume()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            lock.lock()
            sinks[dataTask.taskIdentifier]?.status = http.statusCode
            sinks[dataTask.taskIdentifier]?.headers =
                URLSessionTransport.stringHeaders(http.allHeaderFields)
            lock.unlock()
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        let sink = sinks[dataTask.taskIdentifier]
        lock.unlock()
        // A refusal has a body too, and it is not the protocol the caller is
        // parsing. Only the status reaches it. Any 2xx counts: a ranged
        // request answers 206, and dropping those left downloads writing
        // empty files while the transfer reported success.
        guard let sink = sink, (200...299).contains(sink.status) else {
            return
        }
        guard sink.onChunk(data) else {
            // The caller has what it asked for. Stop the transfer and report
            // it as the success it is — the rest of the body is not wanted.
            finish(dataTask.taskIdentifier, with: .success(HTTPResponse(
                status: sink.status, headers: sink.headers, data: Data()
            )))
            dataTask.cancel()
            return
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // A task the caller stopped has already reported itself; its sink is
        // gone and the cancellation that follows is nothing to act on.
        if URLSessionTransport.isCancelled(error) {
            lock.lock()
            sinks.removeValue(forKey: task.taskIdentifier)
            lock.unlock()
            return
        }
        if let error = error {
            finish(task.taskIdentifier, with: .failure(APIError.transport(error)))
            return
        }
        lock.lock()
        let sink = sinks[task.taskIdentifier]
        lock.unlock()
        guard let sink = sink else {
            return
        }
        // The body was handed over chunk by chunk; the status is all that is
        // left to report.
        finish(task.taskIdentifier, with: .success(HTTPResponse(
            status: sink.status, headers: sink.headers, data: Data()
        )))
    }

    /// Reports a task's outcome exactly once and forgets it.
    private func finish(_ id: Int, with result: Result<HTTPResponse, Error>) {
        lock.lock()
        let sink = sinks.removeValue(forKey: id)
        lock.unlock()
        sink?.completion(result)
    }
}
