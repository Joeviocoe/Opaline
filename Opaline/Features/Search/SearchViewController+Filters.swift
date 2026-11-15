import UIKit

// MARK: - Persistence

/// Filters survive relaunches: a user who always wants newest-first should
/// not have to re-pick it for every query.
extension SearchFilters {
    static var stored: SearchFilters {
        guard let raw = UserDefaults.standard.dictionary(
            forKey: UserDefaultsKeys.Search.filters
        ) as? [String: Int] else {
            return SearchFilters()
        }
        var filters = SearchFilters()
        if let value = raw["sort"].flatMap(Sort.init(rawValue:)) {
            filters.sort = value
        }
        if let value = raw["date"].flatMap(UploadDate.init(rawValue:)) {
            filters.uploadDate = value
        }
        if let value = raw["type"].flatMap(ContentType.init(rawValue:)) {
            filters.type = value
        }
        if let value = raw["duration"].flatMap(Duration.init(rawValue:)) {
            filters.duration = value
        }
        return filters
    }

    func store() {
        let defaults = UserDefaults.standard
        guard !isDefault else {
            defaults.removeObject(forKey: UserDefaultsKeys.Search.filters)
            return
        }
        defaults.set(
            [
                "sort": sort.rawValue,
                "date": uploadDate.rawValue,
                "type": type.rawValue,
                "duration": duration.rawValue
            ],
            forKey: UserDefaultsKeys.Search.filters
        )
    }
}

// MARK: - Search filters UI

extension SearchViewController {
    private struct FilterRow {
        let key: String
        let value: String
        let handler: () -> Void
    }

    private var filterRows: [FilterRow] {
        [
            FilterRow(
                key: "search.filters.sort",
                value: filters.sort.displayName
            ) { [weak self] in self?.showSortPicker() },
            FilterRow(
                key: "search.filters.date",
                value: filters.uploadDate.displayName
            ) { [weak self] in self?.showDatePicker() },
            FilterRow(
                key: "search.filters.type",
                value: filters.type.displayName
            ) { [weak self] in self?.showTypePicker() },
            FilterRow(
                key: "search.filters.duration",
                value: filters.duration.displayName
            ) { [weak self] in self?.showDurationPicker() }
        ]
    }

    func setupFiltersButton() {
        filtersButton.target = self
        filtersButton.action = #selector(filtersTapped)
        navigationItem.rightBarButtonItem = filtersButton
        updateFiltersButton()
    }

    private func updateFiltersButton() {
        filtersButton.title = filters.isDefault
            ? "search.filters".localized
            : "search.filters.active".localized
    }

    @objc
    private func filtersTapped() {
        let sheet = UIAlertController(
            title: "search.filters.title".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        addFilterActions(to: sheet)
        if !filters.isDefault {
            sheet.addAction(
                UIAlertAction(
                    title: "search.filters.reset".localized,
                    style: .destructive
                ) { [weak self] _ in
                    self?.apply { $0 = SearchFilters() }
                }
            )
        }
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = filtersButton
        present(sheet, animated: true)
    }

    private func addFilterActions(to sheet: UIAlertController) {
        for row in filterRows {
            sheet.addAction(
                UIAlertAction(
                    title: row.key.localized(with: row.value),
                    style: .default
                ) { _ in
                    row.handler()
                }
            )
        }
    }

    // MARK: - Pickers

    private func showSortPicker() {
        presentOptions(
            title: "search.filters.sortTitle".localized,
            names: SearchFilters.Sort.allCases.map { $0.displayName },
            selectedIndex: filters.sort.rawValue
        ) { [weak self] index in
            self?.apply { $0.sort = SearchFilters.Sort(rawValue: index) ?? .relevance }
        }
    }

    private func showDatePicker() {
        presentOptions(
            title: "search.filters.dateTitle".localized,
            names: SearchFilters.UploadDate.allCases.map { $0.displayName },
            selectedIndex: filters.uploadDate.rawValue
        ) { [weak self] index in
            self?.apply {
                $0.uploadDate = SearchFilters.UploadDate(rawValue: index) ?? .any
            }
        }
    }

    private func showTypePicker() {
        presentOptions(
            title: "search.filters.typeTitle".localized,
            names: SearchFilters.ContentType.allCases.map { $0.displayName },
            selectedIndex: filters.type.rawValue
        ) { [weak self] index in
            self?.apply {
                $0.type = SearchFilters.ContentType(rawValue: index) ?? .any
            }
        }
    }

    private func showDurationPicker() {
        presentOptions(
            title: "search.filters.durationTitle".localized,
            names: SearchFilters.Duration.allCases.map { $0.displayName },
            selectedIndex: filters.duration.rawValue
        ) { [weak self] index in
            self?.apply {
                $0.duration = SearchFilters.Duration(rawValue: index) ?? .any
            }
        }
    }

    // MARK: - Helpers

    /// `rawValue` doubles as the option index — all filter enums are
    /// declared in raw-value order.
    private func presentOptions(
        title: String,
        names: [String],
        selectedIndex: Int,
        onPick: @escaping (Int) -> Void
    ) {
        let sheet = UIAlertController(
            title: title, message: nil, preferredStyle: .actionSheet
        )
        for (index, name) in names.enumerated() {
            let action = UIAlertAction(title: name, style: .default) { _ in
                onPick(index)
            }
            if index == selectedIndex {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = filtersButton
        present(sheet, animated: true)
    }

    private func apply(_ change: (inout SearchFilters) -> Void) {
        change(&filters)
        filters.store()
        updateFiltersButton()
        if !lastQuery.isEmpty {
            search(query: lastQuery)
        }
    }
}
