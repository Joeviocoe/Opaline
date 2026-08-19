import Foundation

// MARK: - Transfer

extension VideoDownloader {
    /// One file being pulled down, range by range.
    private struct RangeJob {
        let url: URL
        let handle: FileHandle
        let size: Int64
        var offset: Int64
    }

    /// googlevideo paces an open-ended GET at roughly the speed the video
    /// plays: a 30 MB file took as long to save as it took to watch. Asking
    /// for explicit byte ranges is what makes it serve at line speed, which is
    /// also how playback already reads its segments.
    static let chunkBytes: Int64 = 8 * 1_048_576

    /// Streams straight to disk, one range at a time. The transport hands
    /// chunks over as they arrive, so a two-gigabyte file never sits in
    /// memory.
    func download(
        from url: URL,
        to file: URL,
        size: Int64,
        completion: @escaping (Error?) -> Void
    ) {
        let manager = FileManager.default
        try? manager.removeItem(at: file)
        guard manager.createFile(atPath: file.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: file) else {
            completion(DownloadError.storage)
            return
        }
        let job = RangeJob(url: url, handle: handle, size: size, offset: 0)
        fetchRange(job) { error in
            handle.closeFile()
            // Expected against written: the one number that tells a truncated
            // range loop apart from a container the player misreads.
            let wrote = (try? file.resourceValues(forKeys: [.fileSizeKey]))?
                .fileSize ?? 0
            AppLog.downloads(
                "\(file.lastPathComponent): expected \(size) B, wrote \(wrote) B"
            )
            completion(error)
        }
    }

    /// One range, then the next. Sequential on purpose: parallel ranges over
    /// one link finish no sooner and cost the player its bandwidth while a
    /// video plays next to the download.
    private func fetchRange(
        _ job: RangeJob,
        completion: @escaping (Error?) -> Void
    ) {
        guard job.size <= 0 || job.offset < job.size else {
            completion(nil)
            return
        }
        let token = cancellation
        transport.stream(
            rangeRequest(for: job),
            cancellationToken: token
        ) { [weak self] chunk in
            job.handle.write(chunk)
            self?.advance(by: Int64(chunk.count))
            return token?.isCancelled != true
        } completion: { [weak self] result in
            self?.continueJob(job, after: result, completion: completion)
        }
    }

    private func continueJob(
        _ job: RangeJob,
        after result: Result<HTTPResponse, Error>,
        completion: @escaping (Error?) -> Void
    ) {
        if let error = transferError(result) {
            completion(error)
            return
        }
        // A server that ignored the Range header answered with the whole file
        // in one response; there is nothing left to ask for.
        guard (try? result.get())?.status == 206, job.size > 0 else {
            completion(nil)
            return
        }
        var next = job
        next.offset += Self.chunkBytes
        fetchRange(next, completion: completion)
    }

    private func rangeRequest(for job: RangeJob) -> HTTPRequest {
        var headers = ["User-Agent": client.userAgent]
        if job.size > 0 {
            let end = min(job.offset + Self.chunkBytes, job.size) - 1
            headers["Range"] = "bytes=\(job.offset)-\(end)"
        }
        return HTTPRequest(
            method: .get,
            url: job.url,
            headers: headers,
            sendsCookies: false
        )
    }

    private func transferError(
        _ result: Result<HTTPResponse, Error>
    ) -> Error? {
        switch result {
        case .failure(let error):
            return error
        case .success(let response):
            return (200...299).contains(response.status)
                ? nil
                : DownloadError.http(response.status)
        }
    }
}
