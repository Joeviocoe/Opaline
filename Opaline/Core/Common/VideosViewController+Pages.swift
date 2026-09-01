import UIKit

// MARK: - Page Management

extension VideosViewController {
    /// Splits the page's videos into sections following its shelf
    /// partition, deduplicating against already-shown videos.
    private func makeSections(from page: FeedPage) -> [VideoSection] {
        let grouped = groupsByShelf ? page.shelves : nil
        let shelves = grouped
            ?? [FeedShelf(title: nil, count: page.videos.count)]
        var result: [VideoSection] = []
        var index = 0
        for shelf in shelves {
            let end = min(index + shelf.count, page.videos.count)
            let slice = page.videos[index..<end].filter {
                seenVideoIds.insert($0.id).inserted
            }
            index = end
            if !slice.isEmpty {
                result.append(VideoSection(
                    title: shelf.title,
                    videos: slice,
                    continuation: shelf.continuation
                ))
            }
        }
        let rest = page.videos.dropFirst(index).filter {
            seenVideoIds.insert($0.id).inserted
        }
        if !rest.isEmpty {
            result.append(VideoSection(title: nil, videos: rest))
        }
        return result
    }

    func setPage(_ page: FeedPage) {
        isLoadingInitial = false
        seenVideoIds = []
        loadingRailSections = []
        sections = makeSections(from: page)
        continuationToken = page.continuation
        isLoadingMore = false
        collectionView?.reloadData()
    }

    /// Appends a rail's horizontal page to its section; returns the
    /// deduplicated videos that were actually added.
    func appendToRail(
        _ videos: [Video],
        section: Int,
        continuation: String?
    ) -> [Video] {
        sections[section].continuation = continuation
        let fresh = videos.filter {
            seenVideoIds.insert($0.id).inserted
        }
        sections[section].videos.append(contentsOf: fresh)
        return fresh
    }

    func appendPage(_ page: FeedPage) {
        var newSections = makeSections(from: page)
        continuationToken = page.continuation
        isLoadingMore = false

        if isLoadingInitial {
            isLoadingInitial = false
            sections.append(contentsOf: newSections)
            collectionView?.reloadData()
            return
        }
        guard let collectionView = collectionView else {
            _ = mergeIntoLastSection(&newSections)
            sections.append(contentsOf: newSections)
            return
        }
        // `sections` MUST be mutated inside the block. UIKit snapshots the
        // item counts when `performBatchUpdates` is entered, so growing the
        // array first makes its "before" and "after" snapshots identical
        // while the announced inserts say otherwise — which iOS reports as
        // "Invalid batch updates detected" and turns into a crash.
        collectionView.performBatchUpdates {
            let itemPaths = mergeIntoLastSection(&newSections)
            let insertStart = sections.count
            sections.append(contentsOf: newSections)
            if !itemPaths.isEmpty {
                collectionView.insertItems(at: itemPaths)
            }
            if insertStart < sections.count {
                collectionView.insertSections(
                    IndexSet(insertStart..<sections.count)
                )
            }
        }
    }

    /// A flow-layout section always starts a new row, so a page
    /// boundary inside the same (or untitled) shelf would leave a
    /// gap — extend the previous section instead. Rails render one
    /// item per section, so item inserts don't apply there.
    private func mergeIntoLastSection(
        _ newSections: inout [VideoSection]
    ) -> [IndexPath] {
        guard !useRails,
              let first = newSections.first,
              let last = sections.indices.last,
              sections[last].title == first.title
        else {
            return []
        }
        let start = sections[last].videos.count
        sections[last].videos.append(contentsOf: first.videos)
        newSections.removeFirst()
        return (start..<start + first.videos.count).map {
            IndexPath(item: $0, section: last)
        }
    }

    func finishLoadingMore() {
        isLoadingMore = false
    }
}
