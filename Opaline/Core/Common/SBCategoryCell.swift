import UIKit

/// Row for one SponsorBlock segment category: name, description,
/// current skip behavior and the seek-bar color swatch.
final class SBCategoryCell: UITableViewCell {
    static let reuseID = "SBCategoryCell"

    private let nameLabel     = UILabel()
    private let descLabel     = UILabel()
    private let behaviorLabel = UILabel()
    private let colorSwatch   = UIView()

    override init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?
    ) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        configureLabels()
        configureSwatch()
        contentView.addSubview(nameLabel)
        contentView.addSubview(descLabel)
        contentView.addSubview(behaviorLabel)
        contentView.addSubview(colorSwatch)
        setupSwatchAndBehaviorConstraints()
        setupTextConstraints()
        accessoryType = .disclosureIndicator
    }

    private func configureLabels() {
        nameLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = UIFont.systemFont(ofSize: 12)
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        behaviorLabel.font = UIFont.systemFont(ofSize: 13)
        behaviorLabel.textAlignment = .right
        behaviorLabel.setContentHuggingPriority(.required, for: .horizontal)
        behaviorLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        behaviorLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureSwatch() {
        colorSwatch.layer.cornerRadius = 3
        colorSwatch.layer.borderWidth  = 0.5
        colorSwatch.layer.borderColor =
            UIColor.white.withAlphaComponent(0.3).cgColor
        colorSwatch.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupSwatchAndBehaviorConstraints() {
        NSLayoutConstraint.activate([
            colorSwatch.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -16
            ),
            colorSwatch.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            colorSwatch.widthAnchor.constraint(equalToConstant: 40),
            colorSwatch.heightAnchor.constraint(equalToConstant: 16),
            behaviorLabel.trailingAnchor.constraint(
                equalTo: colorSwatch.leadingAnchor,
                constant: -8
            ),
            behaviorLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor)
        ])
    }

    private func setupTextConstraints() {
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 16
            ),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: behaviorLabel.leadingAnchor,
                constant: -8
            ),
            descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 16
            ),
            descLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -16
            ),
            descLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -12
            )
        ])
    }

    func configure(category: SBCategory) {
        let theme = ThemeManager.shared
        backgroundColor       = theme.surface
        nameLabel.textColor   = theme.primaryText
        descLabel.textColor   = theme.secondaryText
        behaviorLabel.textColor = theme.secondaryText
        nameLabel.text     = category.displayName
        descLabel.text     = category.categoryDescription
        colorSwatch.backgroundColor = category.seekBarColor
        behaviorLabel.text = SponsorBlockService.skipBehavior(
            for: category
        ).displayName
    }
}
