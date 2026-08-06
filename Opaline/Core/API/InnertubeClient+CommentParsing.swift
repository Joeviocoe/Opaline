import Foundation

/// Comment responses are read *structurally*, never by recursive search.
///
/// Every comments page (first load, next page, replies) answers with
/// `onResponseReceivedEndpoints[].{reload,append}ContinuationItems`, a flat
/// list holding the header, the threads, and — as its final element — the
/// token for the next page. A recursive first-match scan for a
/// `continuationItemRenderer` used to find the *reply* token buried inside a
/// thread instead (dictionary order is arbitrary), so paging wandered into
/// one comment's replies and dead-ended after ~30 rows. Reading the flat list
/// also walks a few hundred dictionaries instead of the whole 280 KB tree,
/// three times over.
extension InnertubeClient {
    /// The flat top-level item list of a comments response.
    static func commentsItems(in json: [String: Any]) -> [[String: Any]] {
        let endpoints = json["onResponseReceivedEndpoints"]
            as? [[String: Any]] ?? []
        return endpoints.flatMap { endpoint -> [[String: Any]] in
            let action = (endpoint["reloadContinuationItemsCommand"]
                as? [String: Any])
                ?? (endpoint["appendContinuationItemsAction"]
                    as? [String: Any])
            return action?["continuationItems"] as? [[String: Any]] ?? []
        }
    }

    /// The next page's token: the last top-level continuation in the list.
    static func commentsNextContinuation(
        in items: [[String: Any]]
    ) -> String? {
        items.compactMap { continuationToken(from: $0) }.last
    }

    static func commentsTitle(in items: [[String: Any]]) -> String? {
        items.compactMap { commentsTitleFromDict($0) }.first
    }

    /// Sort choices from the header, already localized by `hl`.
    static func commentsSortOptions(
        in items: [[String: Any]]
    ) -> [CommentSortOption] {
        let menu = items
            .compactMap { $0["commentsHeaderRenderer"] as? [String: Any] }
            .compactMap { $0["sortMenu"] as? [String: Any] }
            .compactMap { $0["sortFilterSubMenuRenderer"] as? [String: Any] }
            .first
        let entries = menu?["subMenuItems"] as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            let endpoint = entry["serviceEndpoint"] as? [String: Any]
            let command = endpoint?["continuationCommand"] as? [String: Any]
            guard let title = entry["title"] as? String,
                  let token = command?["token"] as? String
            else {
                return nil
            }
            return CommentSortOption(
                title: title,
                token: token,
                isSelected: entry["selected"] as? Bool == true
            )
        }
    }

    /// One item is either a top-level thread (`commentThreadRenderer`) or a
    /// bare reply (`commentViewModel`); both parse into the same `Comment`.
    static func parseComment(
        item: [String: Any],
        mutations: [[String: Any]]
    ) -> Comment? {
        let thread = (item["commentThreadRenderer"] as? [String: Any]) ?? item
        guard let viewModel = commentViewModel(in: thread),
              let commentId = viewModel["commentId"] as? String
        else {
            return nil
        }
        return buildComment(
            commentId: commentId,
            viewModel: viewModel,
            thread: thread,
            mutations: mutations,
            replyContinuation: repliesContinuation(in: thread)
        )
    }

    static func attributedText(
        from value: Any?
    ) -> String? {
        guard let dict = value as? [String: Any]
        else {
            return nil
        }
        if let content = dict["content"] as? String,
           !content.isEmpty {
            return content
        }
        return simpleText(from: value)
    }
}

private extension InnertubeClient {
    /// A thread wraps its view model one level deeper than a reply does.
    static func commentViewModel(
        in thread: [String: Any]
    ) -> [String: Any]? {
        guard let outer = thread["commentViewModel"] as? [String: Any]
        else {
            return nil
        }
        return (outer["commentViewModel"] as? [String: Any]) ?? outer
    }

    /// The token that loads a thread's first page of replies, if it has any.
    static func repliesContinuation(
        in thread: [String: Any]
    ) -> String? {
        guard let replies = thread["replies"] as? [String: Any],
              let renderer = replies["commentRepliesRenderer"]
                  as? [String: Any],
              let contents = renderer["contents"] as? [[String: Any]]
        else {
            return nil
        }
        return contents.compactMap { continuationToken(from: $0) }.first
    }

    static func continuationToken(
        from dict: [String: Any]
    ) -> String? {
        guard let renderer = dict[
            "continuationItemRenderer"
        ] as? [String: Any]
        else {
            return nil
        }
        let endpoint = renderer[
            "continuationEndpoint"
        ] as? [String: Any]
        let command = endpoint?[
            "continuationCommand"
        ] as? [String: Any]
        guard let token = command?["token"] as? String,
              !token.isEmpty
        else {
            return nil
        }
        return token
    }

    static func commentsTitleFromDict(
        _ dict: [String: Any]
    ) -> String? {
        if let renderer = dict[
            "commentsHeaderRenderer"
        ] as? [String: Any] {
            return simpleText(
                from: renderer["countText"]
            ) ?? simpleText(
                from: renderer["commentsCount"]
            ) ?? simpleText(
                from: renderer["titleText"]
            )
        }
        if let renderer = dict[
            "commentsEntryPointHeaderRenderer"
        ] as? [String: Any] {
            return simpleText(
                from: renderer["commentCount"]
            ) ?? simpleText(
                from: renderer["headerText"]
            )
        }
        return nil
    }
}
