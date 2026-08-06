import UIKit

// MARK: - History / suggestions panel

extension SearchViewController {
    enum PanelMode {
        case hidden
        case history
        case suggestions
    }

    private static let suggestDebounce: TimeInterval = 0.25

    var panelItems: [String] {
        switch panelMode {
        case .hidden:
            return []
        case .history:
            return searchHistory.queries
        case .suggestions:
            return suggestions
        }
    }

    func setPanel(_ mode: PanelMode) {
        if mode != .suggestions {
            suggestWorkItem?.cancel()
            suggestToken.cancel()
        }
        guard panelMode != mode else {
            if mode != .hidden {
                tableView.reloadData()
            }
            return
        }
        panelMode = mode
        tableView.reloadData()
    }

    /// Derives the panel from the current input: history for an
    /// empty query, debounced suggestions otherwise.
    func updatePanel(for text: String) {
        guard searchBar.isFirstResponder else {
            return
        }
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty {
            suggestions = []
            setPanel(
                searchHistory.queries.isEmpty ? .hidden : .history
            )
        } else {
            setPanel(.suggestions)
            scheduleSuggestions(for: trimmed)
        }
    }

    /// Row tap in the panel: fill the bar and run the search.
    func executePanelQuery(_ query: String) {
        searchBar.text = query
        searchBar.resignFirstResponder()
        search(query: query)
    }

    func removeHistoryItem(at index: Int) {
        let queries = searchHistory.queries
        guard queries.indices.contains(index) else {
            return
        }
        searchHistory.remove(queries[index])
        if searchHistory.queries.isEmpty {
            setPanel(.hidden)
        } else {
            tableView.reloadData()
        }
    }

    // MARK: - Suggestions fetch

    private func scheduleSuggestions(for query: String) {
        suggestWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fetchSuggestions(for: query)
        }
        suggestWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.suggestDebounce,
            execute: work
        )
    }

    private func fetchSuggestions(for query: String) {
        suggestToken.cancel()
        let token = CancellationToken()
        suggestToken = token
        service.fetchSearchSuggestions(
            query: query,
            cancellationToken: token
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.panelMode == .suggestions,
                      self.suggestToken === token,
                      case .success(let items) = result
                else {
                    return
                }
                self.suggestions = items
                self.tableView.reloadData()
            }
        }
    }
}
