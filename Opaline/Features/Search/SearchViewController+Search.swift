import UIKit

// MARK: - Search flow

extension SearchViewController {
    func search(query: String) {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else {
            clearSearchResults()
            return
        }

        searchHistory.add(normalizedQuery)
        setPanel(.hidden)
        let cancellationToken = beginSearch(for: normalizedQuery)
        let onPage: (Result<SearchPage, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                guard self.shouldApplyResult(
                    for: normalizedQuery,
                    cancellationToken: cancellationToken
                ) else {
                    return
                }
                self.applySearchResult(result, append: false)
            }
        }
        if filters.sort == .uploadDate, filters.uploadDate == .any {
            searchAcrossDateWindows(
                query: normalizedQuery,
                cancellationToken: cancellationToken,
                completion: onPage
            )
        } else {
            service.search(
                query: normalizedQuery,
                filters: filters,
                continuation: nil,
                cancellationToken: cancellationToken,
                completion: onPage
            )
        }
    }

    /// Newest-first with no date window chosen. The server's unfiltered
    /// "sort by date" is a relevance pick that skips most of the recent
    /// uploads (see `orderedForSort`), while a date *window* is honored.
    /// So the first page is assembled from one page of each window — the
    /// server's top matches for today, this week, this month — plus the
    /// unfiltered page, deduplicated and ordered by age. One page per window
    /// on purpose: deeper pages of a narrow window are ever weaker matches
    /// and would bury relevant older videos. Load-more continues the
    /// unfiltered list alone. "Last hour" is left out: it is empty for
    /// nearly every query and would be a wasted round-trip.
    private func searchAcrossDateWindows(
        query: String,
        cancellationToken: CancellationToken,
        completion: @escaping (Result<SearchPage, Error>) -> Void
    ) {
        let windows: [SearchFilters.UploadDate] = [
            .today, .thisWeek, .thisMonth, .any
        ]
        var pages = [SearchFilters.UploadDate: Result<SearchPage, Error>]()
        let lock = NSLock()
        let group = DispatchGroup()
        for window in windows {
            var windowFilters = filters
            windowFilters.uploadDate = window
            group.enter()
            service.search(
                query: query,
                filters: windowFilters,
                continuation: nil,
                cancellationToken: cancellationToken
            ) { result in
                lock.lock()
                pages[window] = result
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .global()) {
            // The unfiltered page carries the continuation; without it there
            // is no list to page through, so its failure is the search's.
            guard case .success(let base)? = pages[.any] else {
                completion(
                    pages[.any] ?? .failure(APIError.decodingFailed)
                )
                return
            }
            var seen = Set<String>()
            var merged: [Video] = []
            for window in windows {
                guard case .success(let page)? = pages[window] else {
                    continue
                }
                for video in page.videos where !seen.contains(video.id) {
                    seen.insert(video.id)
                    merged.append(video)
                }
            }
            completion(
                .success(
                    SearchPage(videos: merged, continuation: base.continuation)
                )
            )
        }
    }

    func loadNextPage() {
        guard let token = continuationToken,
              !isLoadingNextPage,
              !lastQuery.isEmpty else {
            return
        }
        isLoadingNextPage = true
        let query = lastQuery
        let cancellationToken = searchCancellationToken
        service.search(
            query: query,
            filters: nil,
            continuation: token,
            cancellationToken: cancellationToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                self.isLoadingNextPage = false
                guard self.shouldApplyResult(
                    for: query,
                    cancellationToken: cancellationToken
                ) else {
                    return
                }
                self.applySearchResult(result, append: true)
            }
        }
    }

    private func beginSearch(for query: String) -> CancellationToken {
        searchCancellationToken.cancel()
        let cancellationToken = CancellationToken()
        searchCancellationToken = cancellationToken
        lastQuery = query
        activeSearchQuery = query
        return cancellationToken
    }

    private func applySearchResult(
        _ result: Result<SearchPage, Error>,
        append: Bool
    ) {
        refreshControl.endRefreshing()
        switch result {
        case .success(let page):
            var videos = orderedForSort(page.videos)
            if append {
                // The window pages already showed some of what the
                // unfiltered continuation now returns.
                let seen = Set(results.map { $0.id })
                videos = videos.filter { !seen.contains($0.id) }
            }
            results = append ? results + videos : videos
            continuationToken = page.continuation
            tableView.reloadData()
        case .failure(let error):
            // Silently keep the current page when a next-page load fails.
            if !append {
                presentSearchError(error)
            }
        }
    }

    /// YouTube no longer honors the "upload date" sort: /search with the
    /// sort param returns a relevance mix on every Innertube client
    /// (WEB, MWEB; TV ignores it; probed 2026-11-14), so a query with that
    /// sort shows years-old videos between today's. The upload-date
    /// *filter* is still honored server-side, which is why "This week"
    /// helped. Order each page here by its relative "N hours ago" text.
    /// Pages are sorted independently so a load-more never reshuffles rows
    /// the user has already scrolled past. Without a date window the first
    /// page is stitched from several windows by `searchAcrossDateWindows`.
    private func orderedForSort(_ videos: [Video]) -> [Video] {
        guard filters.sort == .uploadDate else {
            return videos
        }
        let dated: [(Int, Date)] = videos.indices.map { index in
            let date = videos[index].publishedAt.flatMap {
                VideoFormatters.approximateDate(fromRelative: $0)
            } ?? .distantPast
            return (index, date)
        }
        return dated
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0 < rhs.0
            }
            .map { videos[$0.0] }
    }

    private func presentSearchError(_ error: Error) {
        let alert = UIAlertController(
            title: "common.error".localized,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "common.ok".localized, style: .default)
        )
        present(alert, animated: true)
    }

    private func shouldApplyResult(
        for query: String,
        cancellationToken: CancellationToken
    ) -> Bool {
        searchCancellationToken === cancellationToken
            && activeSearchQuery == query
            && !cancellationToken.isCancelled
    }

    func clearSearchResults() {
        searchCancellationToken.cancel()
        searchCancellationToken = CancellationToken()
        activeSearchQuery = nil
        lastQuery = ""
        results = []
        continuationToken = nil
        isLoadingNextPage = false
        refreshControl.endRefreshing()
        tableView.reloadData()
    }
}
